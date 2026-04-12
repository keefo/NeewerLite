//
//  AudioAnalysisEngine.swift
//  NeewerLite
//
//  Created on 2026-04-11.
//
//  Phase 1 of Sound-to-Light: extracts musically meaningful features
//  from the 60-bin mel spectrum produced by AudioSpectrogram.
//
//  Output: AudioFeatures struct at ~46 Hz (same rate as the mel spectrum).

import Foundation
import Accelerate

// MARK: - Mel Spectrum Normalization

/// Normalize dB-scale mel spectrum bins for AudioAnalysisEngine.
///
/// AudioSpectrogram outputs mel bins in dB after (+50 threshold × 0.683 gain).
/// Silence bins sit around -102 dB; loud music peaks around +5–15 dB.
/// Values > 0 represent audible signal; values ≤ 0 are below the noise floor.
///
/// This maps to [0, 1]: clamp to [0, dbCeiling] and divide by dbCeiling.
/// NaN / Inf bins are forced to 0.
func normalizeMelSpectrum(_ melBins: [Float], dbCeiling: Float = 20.0) -> [Float] {
    let ceiling = max(dbCeiling, 0.001)
    return melBins.map { v -> Float in
        guard v.isFinite else { return 0 }
        return min(max(v / ceiling, 0), 1)
    }
}

// MARK: - AudioFeatures

/// Structured audio features extracted each frame (~46 Hz).
/// All energy/flux values are normalized to 0–1 via per-band AGC.
struct AudioFeatures {
    // Per-band energy (0–1, AGC-normalized)
    var bassEnergy: Float = 0
    var midEnergy: Float = 0
    var highEnergy: Float = 0

    // Spectral flux per band (0–1, half-wave rectified change)
    var bassFlux: Float = 0
    var midFlux: Float = 0
    var highFlux: Float = 0

    // Beat / onset detection
    var isBeat: Bool = false
    var beatIntensity: Float = 0 // 0–1, how strong is the onset
    var bpm: Float = 0           // estimated BPM (0 if not yet locked)
    var beatPhase: Float = 0     // 0–1, position within current beat cycle

    // Overall
    var overallEnergy: Float = 0 // weighted mix of all bands

    // Noise gate
    var spectralFlatness: Float = 0 // 0=tonal/musical, 1=noise/flat
    var noiseGateOpen: Bool = false  // current gate state
    var rawRMS: Float = 0            // pre-AGC RMS for diagnostics

    static let zero = AudioFeatures()
}

// MARK: - AudioAnalysisEngine

/// Processes 60-bin mel spectrum frames and produces AudioFeatures.
///
/// Thread safety: call `analyze(_:)` from the audio capture queue only.
/// Read `latestFeatures` from any thread (it's a value type snapshot).
class AudioAnalysisEngine {

    // MARK: - Band Definitions

    /// Frequency band boundaries in mel-bin indices (0-based, 60 bins total).
    /// Bass:  bins 0–7   (~20–250 Hz)
    /// Mids:  bins 8–25  (~250–2 kHz)
    /// Highs: bins 26–59 (~2–20 kHz)
    struct BandRange {
        static let bass  = 0..<8
        static let mids  = 8..<26
        static let highs = 26..<60
        static let all   = 0..<60
    }

    // MARK: - Configuration

    /// Power-curve exponent for energy compression (< 1 boosts quiet, compresses loud).
    var energyExponent: Float = 0.6

    /// Beat detection sensitivity multiplier.
    /// Higher = fewer beats detected (only strong onsets).
    var beatSensitivity: Float = 1.5

    /// Minimum interval between beats in seconds (prevents double-triggers).
    /// 0.2s = max 5 beats/sec = 300 BPM ceiling.
    var minBeatInterval: Float = 0.2

    /// AGC adaptation speed. Closer to 1.0 = slower adaptation.
    /// At 46 Hz: 0.998 ≈ 7.5s half-life, 0.995 ≈ 3s half-life.
    var agcDecay: Float = 0.997

    /// Spectral flux moving average window size in frames.
    /// At 46 Hz: 46 frames ≈ 1 second.
    var fluxHistorySize: Int = 46

    /// BPM estimation window: number of recent beat timestamps to keep.
    var bpmHistorySize: Int = 16

    // MARK: - Noise Gate Configuration

    /// RMS below this → always gated (silence).
    var rmsFloorThreshold: Float = 0.04

    /// RMS above this → always pass (loud signal, regardless of flatness).
    var rmsPassthroughThreshold: Float = 0.15

    /// In ambiguous RMS range: flatness above this → noise, below → music.
    var flatnessThreshold: Float = 0.65

    /// RMS must drop below this to close an already-open gate (hysteresis).
    /// Defaults to half of rmsFloorThreshold.
    var rmsCloseThreshold: Float = 0.02

    /// Number of frames to hold the gate open after close condition is met.
    /// At 46 Hz: 23 frames ≈ 0.5 seconds.
    var gateHoldDuration: Int = 23

    // MARK: - Internal State

    /// Previous frame's mel bins (for spectral flux calculation).
    private var previousBins = [Float](repeating: 0, count: 60)

    /// Per-band AGC tracking peaks (slow decay, instant attack).
    private var agcPeakBass: Float = 0.001
    private var agcPeakMids: Float = 0.001
    private var agcPeakHighs: Float = 0.001

    /// Spectral flux history for beat detection (circular buffer).
    private var fluxHistory = [Float]()
    private var fluxSum: Float = 0

    /// Recent beat timestamps for BPM estimation.
    private var beatTimestamps = [CFAbsoluteTime]()

    /// Time of last detected beat (for min-interval gating).
    private var lastBeatTime: CFAbsoluteTime = 0

    /// Frame counter (for BPM phase tracking).
    private var frameCount: UInt64 = 0

    /// Estimated beat period in seconds (60 / BPM).
    private var estimatedBeatPeriod: Float = 0

    /// The most recently computed features.
    private(set) var latestFeatures = AudioFeatures.zero

    /// Noise gate state: true when gate is open (music detected).
    private var noiseGateOpen: Bool = false

    /// Frames elapsed since close condition was met (hold counter).
    private var gateHoldFrames: Int = 0

    // MARK: - Public API

    /// Analyze one frame of mel spectrum data and return extracted features.
    ///
    /// - Parameter melBins: 60-element array of mel-frequency energy values
    ///   (as produced by AudioSpectrogram after threshold + gain).
    /// - Returns: Extracted AudioFeatures for this frame.
    @discardableResult
    func analyze(_ melBins: [Float]) -> AudioFeatures {
        let binCount = min(melBins.count, 60)
        guard binCount > 0 else { return latestFeatures }

        // Ensure we work with exactly 60 bins (pad if shorter).
        var bins = melBins
        if bins.count < 60 {
            bins.append(contentsOf: [Float](repeating: 0, count: 60 - bins.count))
        }

        frameCount += 1
        let now = CFAbsoluteTimeGetCurrent()

        // --- 0. Noise Gate: pre-AGC RMS + Spectral Flatness ---
        var sumSq: Float = 0
        vDSP_svesq(bins, 1, &sumSq, vDSP_Length(bins.count))
        let overallRMS = sqrtf(sumSq / Float(bins.count))

        // Spectral flatness: geometric mean / arithmetic mean.
        // Use exp(mean(log(x))) for numerical stability.
        // After mel-spectrum normalization, most bins are 0 (negative dB clipped).
        // Computing flatness over all bins (including zeros) crushes the geometric
        // mean to ≈0, making every spectrum look "peaked" (flatness ≈ 0).
        // Fix: compute flatness only over active bins (> small ε).  If fewer than
        // minActiveBins are active, the spectrum is too sparse to be music → treat
        // as noise (flatness = 1.0).
        let minActiveBins = 8
        let activeBins = bins.filter { $0 > 0.001 }
        let spectralFlatness: Float
        if activeBins.count < minActiveBins {
            spectralFlatness = 1.0  // too sparse → noise
        } else {
            var logSum: Float = 0
            var arithSum: Float = 0
            for v in activeBins {
                logSum += logf(v)
                arithSum += v
            }
            let geometricMean = expf(logSum / Float(activeBins.count))
            let arithmeticMean = arithSum / Float(activeBins.count)
            spectralFlatness = geometricMean / max(arithmeticMean, 1e-10)
        }

        // 2D gate decision
        let shouldBeOpen: Bool
        if overallRMS < rmsFloorThreshold {
            shouldBeOpen = false
        } else if overallRMS > rmsPassthroughThreshold {
            shouldBeOpen = true
        } else {
            shouldBeOpen = spectralFlatness < flatnessThreshold
        }

        // Hysteresis + hold timer
        if noiseGateOpen {
            let shouldClose = overallRMS < rmsCloseThreshold
                || (overallRMS < rmsPassthroughThreshold
                    && spectralFlatness > flatnessThreshold + 0.1)
            if shouldClose {
                gateHoldFrames += 1
                if gateHoldFrames > gateHoldDuration {
                    noiseGateOpen = false
                    gateHoldFrames = 0
                }
            } else {
                gateHoldFrames = 0
            }
        } else {
            if shouldBeOpen {
                noiseGateOpen = true
                gateHoldFrames = 0
            }
        }

        // Gate closed — return silence (keep previousBins updated to avoid flux spike)
        if !noiseGateOpen && gateHoldFrames == 0 {
            previousBins = bins
            var gated = AudioFeatures.zero
            gated.spectralFlatness = clamp01(spectralFlatness)
            gated.noiseGateOpen = false
            gated.rawRMS = overallRMS
            latestFeatures = gated
            return gated
        }

        // --- 1. Band Energy (RMS per band) ---
        let bassRaw = bandRMS(bins, range: BandRange.bass)
        let midsRaw = bandRMS(bins, range: BandRange.mids)
        let highsRaw = bandRMS(bins, range: BandRange.highs)

        // --- 2. AGC Normalization ---
        agcPeakBass = agcUpdate(agcPeakBass, sample: bassRaw)
        agcPeakMids = agcUpdate(agcPeakMids, sample: midsRaw)
        agcPeakHighs = agcUpdate(agcPeakHighs, sample: highsRaw)

        let bassNorm = compress(bassRaw / agcPeakBass)
        let midsNorm = compress(midsRaw / agcPeakMids)
        let highsNorm = compress(highsRaw / agcPeakHighs)

        // --- 3. Spectral Flux (half-wave rectified, per band) ---
        let bassFluxRaw = bandFlux(bins, previous: previousBins, range: BandRange.bass)
        let midsFluxRaw = bandFlux(bins, previous: previousBins, range: BandRange.mids)
        let highsFluxRaw = bandFlux(bins, previous: previousBins, range: BandRange.highs)
        let totalFlux = bassFluxRaw + midsFluxRaw + highsFluxRaw

        // Update flux history for adaptive threshold
        fluxHistory.append(totalFlux)
        fluxSum += totalFlux
        if fluxHistory.count > fluxHistorySize {
            fluxSum -= fluxHistory.removeFirst()
        }

        // Normalize flux per band using AGC peaks for scale reference
        let fluxScale = max(agcPeakBass, max(agcPeakMids, agcPeakHighs))
        let safeDivisor = max(fluxScale, 0.001)
        let bassFluxNorm = clamp01(bassFluxRaw / safeDivisor)
        let midsFluxNorm = clamp01(midsFluxRaw / safeDivisor)
        let highsFluxNorm = clamp01(highsFluxRaw / safeDivisor)

        // --- 4. Beat / Onset Detection ---
        let fluxMean = fluxHistory.isEmpty ? 0 : fluxSum / Float(fluxHistory.count)
        let beatThreshold = fluxMean * beatSensitivity
        let timeSinceLastBeat = Float(now - lastBeatTime)
        let isBeat = totalFlux > beatThreshold
                     && totalFlux > 0.001
                     && timeSinceLastBeat >= minBeatInterval

        var beatIntensity: Float = 0
        if isBeat {
            beatIntensity = clamp01((totalFlux - beatThreshold) / max(beatThreshold, 0.001))
            lastBeatTime = now
            beatTimestamps.append(now)
            if beatTimestamps.count > bpmHistorySize {
                beatTimestamps.removeFirst()
            }
        }

        // --- 5. BPM Estimation ---
        let bpm = estimateBPM()
        if bpm > 0 {
            estimatedBeatPeriod = 60.0 / bpm
        }

        // --- 6. Beat Phase (0–1 position within current beat cycle) ---
        var beatPhase: Float = 0
        if estimatedBeatPeriod > 0 {
            let elapsed = Float(now - lastBeatTime)
            beatPhase = clamp01(elapsed / estimatedBeatPeriod)
        }

        // --- 7. Overall Energy ---
        let overallEnergy = clamp01(bassNorm * 0.4 + midsNorm * 0.35 + highsNorm * 0.25)

        // Store previous frame for next flux calculation
        previousBins = bins

        // Build output
        var features = AudioFeatures()
        features.bassEnergy = bassNorm
        features.midEnergy = midsNorm
        features.highEnergy = highsNorm
        features.bassFlux = bassFluxNorm
        features.midFlux = midsFluxNorm
        features.highFlux = highsFluxNorm
        features.isBeat = isBeat
        features.beatIntensity = beatIntensity
        features.bpm = bpm
        features.beatPhase = beatPhase
        features.overallEnergy = overallEnergy
        features.spectralFlatness = clamp01(spectralFlatness)
        features.noiseGateOpen = true
        features.rawRMS = overallRMS

        // Fade-out during hold period (gate closing)
        if gateHoldFrames > 0 {
            let fadeRatio = 1.0 - Float(gateHoldFrames) / Float(gateHoldDuration)
            features.bassEnergy *= fadeRatio
            features.midEnergy *= fadeRatio
            features.highEnergy *= fadeRatio
            features.overallEnergy *= fadeRatio
            features.isBeat = false
        }

        latestFeatures = features
        return features
    }

    /// Reset all internal state (e.g., when audio source changes).
    func reset() {
        previousBins = [Float](repeating: 0, count: 60)
        agcPeakBass = 0.001
        agcPeakMids = 0.001
        agcPeakHighs = 0.001
        fluxHistory.removeAll()
        fluxSum = 0
        beatTimestamps.removeAll()
        lastBeatTime = 0
        frameCount = 0
        estimatedBeatPeriod = 0
        noiseGateOpen = false
        gateHoldFrames = 0
        latestFeatures = .zero
    }

    // MARK: - Private Helpers

    /// RMS energy of a frequency band.
    private func bandRMS(_ bins: [Float], range: Range<Int>) -> Float {
        guard range.lowerBound < bins.count else { return 0 }
        let upper = min(range.upperBound, bins.count)
        let slice = Array(bins[range.lowerBound..<upper])
        guard !slice.isEmpty else { return 0 }

        var sumOfSquares: Float = 0
        vDSP_svesq(slice, 1, &sumOfSquares, vDSP_Length(slice.count))
        return sqrtf(sumOfSquares / Float(slice.count))
    }

    /// Half-wave rectified spectral flux for a band.
    /// Only positive changes (energy increases) count as flux.
    private func bandFlux(_ current: [Float], previous: [Float], range: Range<Int>) -> Float {
        guard range.lowerBound < current.count,
              range.lowerBound < previous.count else { return 0 }
        let upper = min(range.upperBound, min(current.count, previous.count))

        var flux: Float = 0
        for i in range.lowerBound..<upper {
            let diff = current[i] - previous[i]
            if diff > 0 {
                flux += diff
            }
        }
        return flux
    }

    /// Update AGC tracking peak: instant attack, slow exponential decay.
    private func agcUpdate(_ currentPeak: Float, sample: Float) -> Float {
        if sample > currentPeak {
            return sample // instant attack
        }
        return max(currentPeak * agcDecay, 0.001) // slow decay, never zero
    }

    /// Power-curve compression: boosts quiet signals, compresses loud ones.
    private func compress(_ value: Float) -> Float {
        return clamp01(powf(clamp01(value), energyExponent))
    }

    /// Clamp a value to 0–1.
    private func clamp01(_ value: Float) -> Float {
        return max(0, min(1, value.isFinite ? value : 0))
    }

    /// Estimate BPM from recent beat timestamps using median inter-beat interval.
    private func estimateBPM() -> Float {
        guard beatTimestamps.count >= 4 else { return 0 }

        // Compute inter-beat intervals
        var intervals = [Float]()
        for i in 1..<beatTimestamps.count {
            let interval = Float(beatTimestamps[i] - beatTimestamps[i - 1])
            // Only consider musically plausible intervals (40–300 BPM → 0.2–1.5s)
            if interval >= 0.2 && interval <= 1.5 {
                intervals.append(interval)
            }
        }

        guard intervals.count >= 3 else { return 0 }

        // Median interval is more robust than mean against outliers
        intervals.sort()
        let medianInterval = intervals[intervals.count / 2]

        let bpm = 60.0 / medianInterval
        // Sanity check: only report BPM in musically plausible range
        return (bpm >= 40 && bpm <= 300) ? bpm : 0
    }
}
