//
//  AudioSpectrogram.swift
//  NeewerLite
//
//  Created by Xu Lian on 11/28/21.
//

import Foundation
import AVFoundation
import Accelerate

protocol AudioSpectrogramDelegate: AnyObject {
    func updateFrequency(frequency: [Float])
}

public class AudioSpectrogram: NSObject {

    var delegate: AudioSpectrogramDelegate?

    // MARK: Properties
    /// The number of audio samples per frame.
    static let sampleCount = 1024

    /// Determines the overlap between frames.
    static let hopCount = sampleCount / 2

    /// Number of samping buffers — the width of the spectrogram.
    static let bufferCount = 32

    /// The number of mel filter banks  — the height of the spectrogram.
    static let filterBankCount = 20

    let captureSession = AVCaptureSession()
    let audioOutput = AVCaptureAudioDataOutput()
    let captureQueue = DispatchQueue(label: "captureQueue",
                                     qos: .userInitiated,
                                     attributes: [],
                                     autoreleaseFrequency: .workItem)
    let sessionQueue = DispatchQueue(label: "sessionQueue",
                                     attributes: [],
                                     autoreleaseFrequency: .workItem)

    override init() {
        super.init()
        configureCaptureSession()
        audioOutput.setSampleBufferDelegate(self, queue: captureQueue)
    }

    /// Temporary buffers that the FFT operation uses for storing interim results.
    static var fftRealBuffer = [Float](repeating: 0, count: sampleCount / 2)
    static var fftImagBuffer = [Float](repeating: 0, count: sampleCount / 2)

    /// The forward fast Fourier transform object.
    static let fft: FFTSetup = {
        let log2n = vDSP_Length(log2(Float(sampleCount)))

        guard let fft = vDSP_create_fftsetup(log2n,
                                             FFTRadix(kFFTRadix2)) else {
            fatalError("Unable to create FFT.")
        }

        return fft
    }()

    /// The window sequence used to reduce spectral leakage.
    static let hanningWindow = vDSP.window(ofType: Float.self,
                                           usingSequence: .hanningDenormalized,
                                           count: sampleCount,
                                           isHalfWindow: false)

    let dispatchSemaphore = DispatchSemaphore(value: 1)

    /// A buffer that contains the raw audio data from AVFoundation.
    var rawAudioData = [Int16]()

    /// An array that contains the entire spectrogram.
    var melSpectrumValues = [Float](repeating: 0, count: bufferCount * filterBankCount)

    deinit {
    }

    /// A reusable array that contains the current frame of time domain audio data as single-precision
    /// values.
    var timeDomainBuffer = [Float](repeating: 0, count: sampleCount)

    /// A resuable array that contains the frequency domain representation of the current frame of
    /// audio data.
    var frequencyDomainBuffer = [Float](repeating: 0, count: sampleCount)

    /// A matrix of `filterBankCount` rows and `sampleCount` that contains the triangular overlapping
    /// windows for each mel frequency.
    let filterBank = AudioSpectrogram.makeFilterBank(withFrequencyRange: 20 ... 20_000,
                                                   sampleCount: AudioSpectrogram.sampleCount,
                                                   filterBankCount: AudioSpectrogram.filterBankCount)

    static let signalCount = 1
    /// A buffer that contains the matrix multiply result of the current frame of frequency domain values in
    /// `frequencyDomainBuffer` multiplied by the `filterBank` matrix.
    let sgemmResult = UnsafeMutableBufferPointer<Float>
        .allocate(capacity: AudioSpectrogram.signalCount * Int(AudioSpectrogram.filterBankCount))

    /// Process a frame of raw audio data:
    ///
    /// 1. Convert the `Int16` time-domain audio values to `Float`.
    /// 2. Perform a forward DFT on the time-domain values.
    /// 3. Multiply the `frequencyDomainBuffer` vector by the `filterBank` matrix
    /// to generate `sgemmResult` product.
    /// 4. Convert the matrix multiply results to decibels.
    ///
    /// The matrix multiply effectively creates a  vector of `filterBankCount` elements that summarises
    /// the `sampleCount` frequency-domain values.  For example, given a vector of four frequency-domain
    /// values:
    /// ```
    ///  [ 1, 2, 3, 4 ]
    /// ```
    /// And a filter bank of three filters with the following values:
    /// ```
    ///  [ 0.5, 0.5, 0.0, 0.0,
    ///    0.0, 0.5, 0.5, 0.0,
    ///    0.0, 0.0, 0.5, 0.5 ]
    /// ```
    /// The result contains three values of:
    /// ```
    ///  [ ( 1 * 0.5 + 2 * 0.5) = 1.5,
    ///     (2 * 0.5 + 3 * 0.5) = 2.5,
    ///     (3 * 0.5 + 4 * 0.5) = 3.5 ]
    /// ```
    func processData(values: [Int16]) {

        vDSP.convertElements(of: values,
                             to: &timeDomainBuffer)

        AudioSpectrogram.performForwardDFT(timeDomainValues: &timeDomainBuffer,
                                         frequencyDomainValues: &frequencyDomainBuffer,
                                         temporaryRealBuffer: &realParts,
                                         temporaryImaginaryBuffer: &imaginaryParts)

        vDSP.absolute(frequencyDomainBuffer,
                      result: &frequencyDomainBuffer)

        frequencyDomainBuffer.withUnsafeBufferPointer { frequencyDomainValuesPtr in
            cblas_sgemm(CblasRowMajor,
                        CblasTrans, CblasTrans,
                        Int32(AudioSpectrogram.signalCount),
                        Int32(AudioSpectrogram.filterBankCount),
                        Int32(AudioSpectrogram.sampleCount),
                        1,
                        frequencyDomainValuesPtr.baseAddress, Int32(AudioSpectrogram.signalCount),
                        filterBank.baseAddress, Int32(AudioSpectrogram.sampleCount),
                        0,
                        sgemmResult.baseAddress, Int32(AudioSpectrogram.filterBankCount))
        }

        vDSP_vdbcon(sgemmResult.baseAddress!, 1,
                    [20_000],
                    sgemmResult.baseAddress!, 1,
                    vDSP_Length(sgemmResult.count),
                    0)

        // Scroll the values in `melSpectrumValues` by removing the first
        // `filterBankCount` values and appending the `filterBankCount` elements
        // in `sgemmResult`.
        if melSpectrumValues.count > AudioSpectrogram.filterBankCount {
            melSpectrumValues.removeFirst(AudioSpectrogram.filterBankCount)
        }
        melSpectrumValues.append(contentsOf: sgemmResult)
    }

    /// The real parts of the time- and frequency-domain representations (the code performs DFT in-place)
    /// of the current frame of audio.
    var realParts = [Float](repeating: 0,
                            count: sampleCount / 2)

    /// The imaginary parts of the time- and frequency-domain representations (the code performs DFT
    /// in-place) of the current frame of audio.
    var imaginaryParts = [Float](repeating: 0,
                                 count: sampleCount / 2)

    /// Performs a forward Fourier transform on interleaved `timeDomainValues` writing the result to
    /// interleaved `frequencyDomainValues`.
    static func performForwardDFT(timeDomainValues: inout [Float],
                                  frequencyDomainValues: inout [Float],
                                  temporaryRealBuffer: inout [Float],
                                  temporaryImaginaryBuffer: inout [Float]) {

        vDSP.multiply(timeDomainValues,
                      hanningWindow,
                      result: &timeDomainValues)

        // Populate split real and imaginary arrays with the interleaved values
        // in `timeDomainValues`.
        temporaryRealBuffer.withUnsafeMutableBufferPointer { realPtr in
            temporaryImaginaryBuffer.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!,
                                                   imagp: imagPtr.baseAddress!)

                timeDomainValues.withUnsafeBytes {
                    vDSP_ctoz($0.bindMemory(to: DSPComplex.self).baseAddress!, 2,
                              &splitComplex, 1,
                              vDSP_Length(AudioSpectrogram.sampleCount / 2))
                }
            }
        }

        // Perform forward transform.
        temporaryRealBuffer.withUnsafeMutableBufferPointer { realPtr in
            temporaryImaginaryBuffer.withUnsafeMutableBufferPointer { imagPtr in
                fftRealBuffer.withUnsafeMutableBufferPointer { realBufferPtr in
                    fftImagBuffer.withUnsafeMutableBufferPointer { imagBufferPtr in
                        var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!,
                                                           imagp: imagPtr.baseAddress!)

                        var bufferSplitComplex = DSPSplitComplex(realp: realBufferPtr.baseAddress!,
                                                                 imagp: imagBufferPtr.baseAddress!)

                        let log2n = vDSP_Length(log2(Float(sampleCount)))

                        vDSP_fft_zript(fft,
                                       &splitComplex, 1,
                                       &bufferSplitComplex,
                                       log2n,
                                       FFTDirection(kFFTDirection_Forward))
                    }
                }
            }
        }

        // Populate interleaved `frequencyDomainValues` with the split values
        // from the real and imaginary arrays.
        temporaryRealBuffer.withUnsafeMutableBufferPointer { realPtr in
            temporaryImaginaryBuffer.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!,
                                                   imagp: imagPtr.baseAddress!)

                frequencyDomainValues.withUnsafeMutableBytes { ptr in
                    vDSP_ztoc(&splitComplex, 1,
                              ptr.bindMemory(to: DSPComplex.self).baseAddress!, 2,
                              vDSP_Length(AudioSpectrogram.sampleCount / 2))
                }
            }
        }
    }

    /// Creates an audio spectrogram `CGImage` from `melSpectrumValues` and renders it
    /// to the `spectrogramLayer` layer.
    func createAudioSpectrogram() {

        if melSpectrumValues.count > AudioSpectrogram.filterBankCount {
            let realSignal  = Array(melSpectrumValues.suffix(AudioSpectrogram.filterBankCount))
            if let del = self.delegate {
                del.updateFrequency(frequency: realSignal)
            }
        }
    }
}

extension AudioSpectrogram: AVCaptureAudioDataOutputSampleBufferDelegate {

    public func captureOutput(_ output: AVCaptureOutput,
                              didOutput sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {

        var audioBufferList = AudioBufferList()
        var blockBuffer: CMBlockBuffer?

        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout.stride(ofValue: audioBufferList),
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer)

        guard let data = audioBufferList.mBuffers.mData else {
            return
        }

        if self.rawAudioData.count < AudioSpectrogram.sampleCount * 2 {
            let actualSampleCount = CMSampleBufferGetNumSamples(sampleBuffer)

            let ptr = data.bindMemory(to: Int16.self, capacity: actualSampleCount)
            let buf = UnsafeBufferPointer(start: ptr, count: actualSampleCount)

            rawAudioData.append(contentsOf: Array(buf))
        }

        dispatchSemaphore.wait()

        while self.rawAudioData.count >= AudioSpectrogram.sampleCount {
            let dataToProcess = Array(self.rawAudioData[0 ..< AudioSpectrogram.sampleCount])
            self.rawAudioData.removeFirst(AudioSpectrogram.hopCount)
            self.processData(values: dataToProcess)
        }

        createAudioSpectrogram()

        dispatchSemaphore.signal()
    }

    func configureCaptureSession() {
        // Also note that:
        //
        // When running in iOS, you must add a "Privacy - Microphone Usage
        // Description" entry.
        //
        // When running in macOS, you must add a "Privacy - Microphone Usage
        // Description" entry to `Info.plist`, and check "audio input" and
        // "camera access" under the "Resource Access" category of "Hardened
        // Runtime".
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                break
            case .notDetermined:
                sessionQueue.suspend()
                AVCaptureDevice.requestAccess(for: .audio,
                                              completionHandler: { granted in
                    if !granted {
                        Logger.error("App requires microphone access.")
                    } else {
                        self.configureCaptureSession()
                        self.sessionQueue.resume()
                    }
                })
                return
            default:
                // Users can add authorization in "Settings > Privacy > Microphone"
                // on an iOS device, or "System Preferences > Security & Privacy >
                // Microphone" on a macOS device.
                Logger.error("App requires microphone access.")
                return
        }

        captureSession.beginConfiguration()

#if os(macOS)
        // Note than in macOS, you can change the sample rate, for example to
        // `AVSampleRateKey: 22050`. This reduces the Nyquist frequency and
        // increases the resolution at lower frequencies.
        audioOutput.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMBitDepthKey: 16,
            AVNumberOfChannelsKey: 1]
#endif

        if captureSession.canAddOutput(audioOutput) {
            captureSession.addOutput(audioOutput)
        } else {
            Logger.error("Can't add `audioOutput`.")
            return
        }

        guard
            let microphone = AVCaptureDevice.default(.builtInMicrophone,
                                                     for: .audio,
                                                     position: .unspecified),
            let microphoneInput = try? AVCaptureDeviceInput(device: microphone) else {
                Logger.error("Can't create microphone.")
                return
            }

        if captureSession.canAddInput(microphoneInput) {
            captureSession.addInput(microphoneInput)
        }

        captureSession.commitConfiguration()
    }

    /// Starts the audio spectrogram.
    func startRunning() {
        sessionQueue.async {
            if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
                self.captureSession.startRunning()
            }
        }
    }

    func stopRunning() {
        sessionQueue.async {
            if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
                self.captureSession.stopRunning()
            }
        }
    }
}

extension AudioSpectrogram {

    /// Populates the specified `filterBank` with a matrix of overlapping triangular windows.
    ///
    /// For each frequency in `melFilterBankFrequencies`, the function creates a row in `filterBank`
    /// that contains a triangular window starting at the previous frequency, having a response of `1` at the
    /// frequency, and ending at the next frequency.
    static func makeFilterBank(withFrequencyRange frequencyRange: ClosedRange<Float>,
                               sampleCount: Int,
                               filterBankCount: Int) -> UnsafeMutableBufferPointer<Float> {

        /// The `melFilterBankFrequencies` array contains `filterBankCount` elements
        /// that are indices of the `frequencyDomainBuffer`. The indices represent evenly spaced
        /// monotonically incrementing mel frequencies; that is, they're roughly logarithmically spaced as
        /// frequency in hertz.
        let melFilterBankFrequencies: [Int] = AudioSpectrogram
                .populateMelFilterBankFrequencies(withFrequencyRange: frequencyRange,
                                                  filterBankCount: filterBankCount)

        let capacity = sampleCount * filterBankCount
        let filterBank = UnsafeMutableBufferPointer<Float>.allocate(capacity: capacity)
        filterBank.initialize(repeating: 0)

        var baseValue: Float = 1
        var endValue: Float = 0

        for idx in 0 ..< melFilterBankFrequencies.count {

            let row = idx * AudioSpectrogram.sampleCount

            let startFrequency = melFilterBankFrequencies[ max(0, idx - 1) ]
            let centerFrequency = melFilterBankFrequencies[ idx ]
            let endFrequency = (idx + 1) < melFilterBankFrequencies.count ?
            melFilterBankFrequencies[ idx + 1 ] : sampleCount - 1

            let attackWidth = centerFrequency - startFrequency + 1
            let decayWidth = endFrequency - centerFrequency + 1

            // Create the attack phase of the triangle.
            if attackWidth > 0 {
                vDSP_vgen(&endValue,
                          &baseValue,
                          filterBank.baseAddress!.advanced(by: row + startFrequency),
                          1,
                          vDSP_Length(attackWidth))
            }

            // Create the decay phase of the triangle.
            if decayWidth > 0 {
                vDSP_vgen(&baseValue,
                          &endValue,
                          filterBank.baseAddress!.advanced(by: row + centerFrequency),
                          1,
                          vDSP_Length(decayWidth))
            }
        }

        return filterBank
    }

    /// Populates the specified `melFilterBankFrequencies` with a monotonically increasing series
    /// of indices into `frequencyDomainBuffer` that represent evenly spaced mels.
    static func populateMelFilterBankFrequencies(withFrequencyRange frequencyRange: ClosedRange<Float>,
                                                 filterBankCount: Int) -> [Int] {

        func frequencyToMel(_ frequency: Float) -> Float {
            return 2595 * log10(1 + (frequency / 700))
        }

        func melToFrequency(_ mel: Float) -> Float {
            return 700 * (pow(10, mel / 2595) - 1)
        }

        let minMel = frequencyToMel(frequencyRange.lowerBound)
        let maxMel = frequencyToMel(frequencyRange.upperBound)
        let bankWidth = (maxMel - minMel) / Float(filterBankCount - 1)

        let melFilterBankFrequencies: [Int] = stride(from: minMel, to: maxMel, by: bankWidth).map {
            let mel = Float($0)
            let frequency = melToFrequency(mel)
            return Int((frequency / frequencyRange.upperBound) * Float(AudioSpectrogram.sampleCount))
        }

        return melFilterBankFrequencies
    }
}
