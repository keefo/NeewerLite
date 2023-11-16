//
//  AudioSpectrogram.swift
//  NeewerLite
//
//  Created by Xu Lian on 11/28/21.
//

import Foundation
import AVFoundation
import Accelerate
import AppKit

// Define the callback type
typealias FrequencyUpdateCallback = ([Float]) -> Void
typealias VolumeUpdateCallback = (Float) -> Void
typealias AmplitudeUpdateCallback = (Float) -> Void
typealias AudioSpectrogramImageUpdateCallback = (CGImage) -> Void

public class AudioSpectrogram: NSObject {

    // Replace the delegate with a callback
    var frequencyUpdateCallback: FrequencyUpdateCallback?
    var volumeUpdateCallback: VolumeUpdateCallback?
    var amplitudeUpdateCallback: AmplitudeUpdateCallback?
    var audioSpectrogramImageUpdateCallback: AudioSpectrogramImageUpdateCallback?

    // MARK: Properties
    // The number of audio samples per frame.
    static let sampleCount = 1024

    // Determines the overlap between frames.
    static let hopCount = sampleCount / 2

    // Number of samping buffers — the width of the spectrogram.
    static let bufferCount = 32

    // The number of mel filter banks  — the height of the spectrogram.
    static let filterBankCount = 60

    static let melSpectrumValueThreshold: Float = 50.0
    static let melSpectrumValueGain: Float = 0.683

    static let frequencyRange: ClosedRange<Float> = 20...20_000

    let captureSession = AVCaptureSession()
    let audioOutput = AVCaptureAudioDataOutput()
    let captureQueue = DispatchQueue(label: "captureQueue",
                                     qos: .userInitiated,
                                     attributes: [],
                                     autoreleaseFrequency: .workItem)
    let sessionQueue = DispatchQueue(label: "sessionQueue",
                                     attributes: [],
                                     autoreleaseFrequency: .workItem)

    let volumeListenerCallback: AudioObjectPropertyListenerProc = { audioObjectId, _, _, selfPointer in
        guard let pointer = selfPointer else { return kAudioHardwareNoError }
        let mySelf = Unmanaged<AudioSpectrogram>.fromOpaque(pointer).takeUnretainedValue()
        var volume = Float32(0.0)
        var size = UInt32(MemoryLayout.size(ofValue: volume))

        var element: AudioObjectPropertyElement
        if #available(macOS 12.0, *) {
            element = kAudioObjectPropertyElementMain
        } else {
            element = kAudioObjectPropertyElementMaster
        }

        var volumePropertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )

        let status = AudioObjectGetPropertyData(
            audioObjectId,
            &volumePropertyAddress,
            0,
            nil,
            &size,
            &volume
        )

        if status == noErr {
            if let safeCallback = mySelf.volumeUpdateCallback {
                safeCallback(volume)
            }
        } else {
            print("Error getting volume in callback")
        }
        return kAudioHardwareNoError
    }

    override init() {
        super.init()
        configureCaptureSession()
    }

    let forwardDCT = vDSP.DCT(count: sampleCount,
                              transformType: .II)!

    // The window sequence used to reduce spectral leakage.
    let hanningWindow = vDSP.window(ofType: Float.self,
                                           usingSequence: .hanningDenormalized,
                                           count: sampleCount,
                                           isHalfWindow: false)

    let dispatchSemaphore = DispatchSemaphore(value: 1)

    // A buffer that contains the raw audio data from AVFoundation.
    var rawAudioData = [Int16]()

    // An array that contains the entire spectrogram.
    var melSpectrumValues = [Float](repeating: 0, count: bufferCount * filterBankCount)

    /// Raw frequency-domain values.
    var frequencyDomainValues = [Float](repeating: 0,
                                        count: bufferCount * sampleCount)

    var rgbImageFormat = vImage_CGImageFormat(
        bitsPerComponent: 32,
        bitsPerPixel: 32 * 3,
        colorSpace: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(
            rawValue: kCGBitmapByteOrder32Host.rawValue |
            CGBitmapInfo.floatComponents.rawValue |
            CGImageAlphaInfo.none.rawValue))!

    /// RGB vImage buffer that contains a vertical representation of the audio spectrogram.

    let redBuffer = vImage.PixelBuffer<vImage.PlanarF>(
        width: AudioSpectrogram.sampleCount,
        height: AudioSpectrogram.bufferCount)

    let greenBuffer = vImage.PixelBuffer<vImage.PlanarF>(
        width: AudioSpectrogram.sampleCount,
        height: AudioSpectrogram.bufferCount)

    let blueBuffer = vImage.PixelBuffer<vImage.PlanarF>(
        width: AudioSpectrogram.sampleCount,
        height: AudioSpectrogram.bufferCount)

    let rgbImageBuffer = vImage.PixelBuffer<vImage.InterleavedFx3>(
        width: AudioSpectrogram.sampleCount,
        height: AudioSpectrogram.bufferCount)

    deinit {
    }

    // A reusable array that contains the current frame of time domain audio data as single-precision
    // values.
    var timeDomainBuffer = [Float](repeating: 0, count: sampleCount)

    // A resuable array that contains the frequency domain representation of the current frame of
    // audio data.
    var frequencyDomainBuffer = [Float](repeating: 0, count: sampleCount)

    // A matrix of `filterBankCount` rows and `sampleCount` that contains the triangular overlapping
    // windows for each mel frequency.
    let filterBank = AudioSpectrogram.makeFilterBank(withFrequencyRange: AudioSpectrogram.frequencyRange,
                                                   sampleCount: AudioSpectrogram.sampleCount,
                                                   filterBankCount: AudioSpectrogram.filterBankCount)

    static let signalCount = 1
    // A buffer that contains the matrix multiply result of the current frame of frequency domain values in
    // `frequencyDomainBuffer` multiplied by the `filterBank` matrix.
    let sgemmResult = UnsafeMutableBufferPointer<Float>
        .allocate(capacity: AudioSpectrogram.signalCount * Int(AudioSpectrogram.filterBankCount))

    public var gain: Double = 0.0288
    public var zeroReference: Double = 1000

    // Process a frame of raw audio data:
    //
    // 1. Convert the `Int16` time-domain audio values to `Float`.
    // 2. Perform a forward DFT on the time-domain values.
    // 3. Multiply the `frequencyDomainBuffer` vector by the `filterBank` matrix
    // to generate `sgemmResult` product.
    // 4. Convert the matrix multiply results to decibels.
    //
    // The matrix multiply effectively creates a  vector of `filterBankCount` elements that summarises
    // the `sampleCount` frequency-domain values.  For example, given a vector of four frequency-domain
    // values:
    // ```
    //  [ 1, 2, 3, 4 ]
    // ```
    // And a filter bank of three filters with the following values:
    // ```
    //  [ 0.5, 0.5, 0.0, 0.0,
    //    0.0, 0.5, 0.5, 0.0,
    //    0.0, 0.0, 0.5, 0.5 ]
    // ```
    // The result contains three values of:
    // ```
    //  [ ( 1 * 0.5 + 2 * 0.5) = 1.5,
    //     (2 * 0.5 + 3 * 0.5) = 2.5,
    //     (3 * 0.5 + 4 * 0.5) = 3.5 ]
    // ```
    func processData(values: [Int16]) {

        if let callback = amplitudeUpdateCallback {
            callback(calculateAmplitude(samples: values.map { Float($0) }))
        }

        vDSP.convertElements(of: values,
                             to: &timeDomainBuffer)

        vDSP.multiply(timeDomainBuffer,
                      hanningWindow,
                      result: &timeDomainBuffer)

        forwardDCT.transform(timeDomainBuffer,
                             result: &frequencyDomainBuffer)

        vDSP.absolute(frequencyDomainBuffer, result: &frequencyDomainBuffer)

        // linear
        vDSP.convert(amplitude: frequencyDomainBuffer,
                     toDecibels: &frequencyDomainBuffer,
                     zeroReference: Float(zeroReference))

        vDSP.multiply(Float(gain),
                      frequencyDomainBuffer,
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
                    [AudioSpectrogram.frequencyRange.upperBound],
                    sgemmResult.baseAddress!, 1,
                    vDSP_Length(sgemmResult.count),
                    0)

        if frequencyDomainValues.count > AudioSpectrogram.sampleCount {
            frequencyDomainValues.removeFirst(AudioSpectrogram.sampleCount)
        }

        frequencyDomainValues.append(contentsOf: frequencyDomainBuffer)

        // Scroll the values in `melSpectrumValues` by removing the first
        // `filterBankCount` values and appending the `filterBankCount` elements
        // in `sgemmResult`.
        if melSpectrumValues.count > AudioSpectrogram.filterBankCount {
            melSpectrumValues.removeFirst(AudioSpectrogram.filterBankCount)
        }
        melSpectrumValues.append(contentsOf: sgemmResult)
        // Filter out `inf` values
        melSpectrumValues.withUnsafeMutableBufferPointer { ptr in
            for idx in 0..<ptr.count {
                if ptr[idx].isNaN {
                    ptr[idx] = 0
                } else {
                    ptr[idx] += AudioSpectrogram.melSpectrumValueThreshold
                    ptr[idx] *= AudioSpectrogram.melSpectrumValueGain
                }
            }
        }
    }

    private func calculateAmplitude(samples: [Float]) -> Float {
        let sumOfSquares = samples.reduce(0) { $0 + $1 * $1 }
        let rms = sqrt(sumOfSquares / Float(samples.count))
        return rms
    }

    // Creates an audio spectrogram `CGImage` from `melSpectrumValues` and renders it
    // to the `spectrogramLayer` layer.
    func createAudioSpectrogram() {
        if melSpectrumValues.count > AudioSpectrogram.filterBankCount {
            let realSignal  = Array(melSpectrumValues.suffix(AudioSpectrogram.filterBankCount))
            if let callback = frequencyUpdateCallback {
                callback(realSignal)
            }
        }

        if let callback = audioSpectrogramImageUpdateCallback {
            frequencyDomainValues.withUnsafeMutableBufferPointer {
                let planarImageBuffer = vImage.PixelBuffer(
                    data: $0.baseAddress!,
                    width: AudioSpectrogram.sampleCount,
                    height: AudioSpectrogram.bufferCount,
                    byteCountPerRow: AudioSpectrogram.sampleCount * MemoryLayout<Float>.stride,
                    pixelFormat: vImage.PlanarF.self)

                AudioSpectrogram.multidimensionalLookupTable.apply(
                    sources: [planarImageBuffer],
                    destinations: [redBuffer, greenBuffer, blueBuffer],
                    interpolation: .half)

                rgbImageBuffer.interleave(
                    planarSourceBuffers: [redBuffer, greenBuffer, blueBuffer])
                let img = rgbImageBuffer.makeCGImage(cgImageFormat: rgbImageFormat) ?? AudioSpectrogram.emptyCGImage
                callback(img)
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
        } else {
            Logger.error("Can't add `microphoneInput`.")
            return
        }

        audioOutput.setSampleBufferDelegate(self, queue: captureQueue)

        captureSession.commitConfiguration()
    }

    private func startVolumeListener() {
        var defaultOutputDeviceID = AudioDeviceID(0)
        var defaultOutputDeviceIDSize = UInt32(MemoryLayout.size(ofValue: defaultOutputDeviceID))

        var element: AudioObjectPropertyElement
        if #available(macOS 12.0, *) {
            element = kAudioObjectPropertyElementMain
        } else {
            element = kAudioObjectPropertyElementMaster
        }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: element
        )

        var status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &defaultOutputDeviceIDSize,
            &defaultOutputDeviceID
        )

        if status == noErr {
            // doesn't called on headphone connection
            let weakSelf = Unmanaged.passUnretained(self).toOpaque()

            var volumePropertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )

            status = AudioObjectAddPropertyListener(
                defaultOutputDeviceID,
                &volumePropertyAddress,
                volumeListenerCallback,
                weakSelf
            )

            if status != noErr {
                Logger.error("Failed to add volume listener")
            }
        } else {
            Logger.error("Failed to get default output device")
        }
    }

    func removeVolumeListener() {
        let objectId = AudioObjectID(kAudioObjectSystemObject)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectRemovePropertyListener(
            objectId,
            &propertyAddress,
            volumeListenerCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        if status != noErr {
            print("Error removing audio property listener")
        }
    }

    // Starts the audio spectrogram.
    func startRunning() {
        sessionQueue.async {
            if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
                self.captureSession.startRunning()
            }
        }
        startVolumeListener()
    }

    func stopRunning() {
        sessionQueue.async {
            if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
                self.captureSession.stopRunning()
            }
        }
        removeVolumeListener()
    }
}

extension AudioSpectrogram {

    // Populates the specified `filterBank` with a matrix of overlapping triangular windows.
    //
    // For each frequency in `melFilterBankFrequencies`, the function creates a row in `filterBank`
    // that contains a triangular window starting at the previous frequency, having a response of `1` at the
    // frequency, and ending at the next frequency.
    static func makeFilterBank(withFrequencyRange frequencyRange: ClosedRange<Float>,
                               sampleCount: Int,
                               filterBankCount: Int) -> UnsafeMutableBufferPointer<Float> {

        // The `melFilterBankFrequencies` array contains `filterBankCount` elements
        // that are indices of the `frequencyDomainBuffer`. The indices represent evenly spaced
        // monotonically incrementing mel frequencies; that is, they're roughly logarithmically spaced as
        // frequency in hertz.
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

    // Populates the specified `melFilterBankFrequencies` with a monotonically increasing series
    // of indices into `frequencyDomainBuffer` that represent evenly spaced mels.
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

    /// Returns the RGB values from a blue -> red -> green color map for a specified value.
    ///
    /// Values near zero return dark blue, `0.5` returns red, and `1.0` returns full-brightness green.
    static var multidimensionalLookupTable: vImage.MultidimensionalLookupTable = {
        let entriesPerChannel = UInt8(32)
        let srcChannelCount = 1
        let destChannelCount = 3

        let lookupTableElementCount = Int(pow(Float(entriesPerChannel),
                                              Float(srcChannelCount))) *
        Int(destChannelCount)

        let tableData = [UInt16](unsafeUninitializedCapacity: lookupTableElementCount) { buffer, count in

            /// Supply the samples in the range `0...65535`. The transform function
            /// interpolates these to the range `0...1`.
            let multiplier = CGFloat(UInt16.max)
            var bufferIndex = 0

            for gray in ( 0 ..< entriesPerChannel) {
                /// Create normalized red, green, and blue values in the range `0...1`.
                let normalizedValue = CGFloat(gray) / CGFloat(entriesPerChannel - 1)

                // Define `hue` that's blue at `0.0` to red at `1.0`.
                let hue = 0.6666 - (0.6666 * normalizedValue)
                let brightness = sqrt(normalizedValue)

                let color = NSColor(hue: hue,
                                    saturation: 1,
                                    brightness: brightness,
                                    alpha: 1)

                var red = CGFloat()
                var green = CGFloat()
                var blue = CGFloat()

                color.getRed(&red,
                             green: &green,
                             blue: &blue,
                             alpha: nil)

                buffer[ bufferIndex ] = UInt16(green * multiplier)
                bufferIndex += 1
                buffer[ bufferIndex ] = UInt16(red * multiplier)
                bufferIndex += 1
                buffer[ bufferIndex ] = UInt16(blue * multiplier)
                bufferIndex += 1
            }

            count = lookupTableElementCount
        }

        let entryCountPerSourceChannel = [UInt8](repeating: entriesPerChannel,
                                                 count: srcChannelCount)

        return vImage.MultidimensionalLookupTable(entryCountPerSourceChannel: entryCountPerSourceChannel,
                                                  destinationChannelCount: destChannelCount,
                                                  data: tableData)
    }()

    /// A 1x1 Core Graphics image.
    static var emptyCGImage: CGImage = {
        let buffer = vImage.PixelBuffer(
            pixelValues: [0],
            size: .init(width: 1, height: 1),
            pixelFormat: vImage.Planar8.self)

        let fmt = vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            colorSpace: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            renderingIntent: .defaultIntent)

        return buffer.makeCGImage(cgImageFormat: fmt!)!
    }()
}
