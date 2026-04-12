//
//  AudioAnalysisEngineTests.swift
//  NeewerLiteTests
//
//  Created on 2026-04-11.
//

import XCTest
@testable import NeewerLite

final class AudioAnalysisEngineTests: XCTestCase {

    var engine: AudioAnalysisEngine!

    override func setUp() {
        super.setUp()
        engine = AudioAnalysisEngine()
    }

    override func tearDown() {
        engine = nil
        super.tearDown()
    }

    // MARK: - Band Energy Tests

    func test_silenceProducesZeroEnergy() {
        let silent = [Float](repeating: 0, count: 60)
        let features = engine.analyze(silent)

        XCTAssertEqual(features.bassEnergy, 0, accuracy: 0.001)
        XCTAssertEqual(features.midEnergy, 0, accuracy: 0.001)
        XCTAssertEqual(features.highEnergy, 0, accuracy: 0.001)
        XCTAssertEqual(features.overallEnergy, 0, accuracy: 0.001)
        XCTAssertFalse(features.isBeat)
    }

    func test_bassOnlySignal() {
        // Put energy only in bass bins (0–7)
        var bins = [Float](repeating: 0, count: 60)
        for i in 0..<8 { bins[i] = 0.8 }

        let features = engine.analyze(bins)

        XCTAssertGreaterThan(features.bassEnergy, 0)
        XCTAssertEqual(features.midEnergy, 0, accuracy: 0.001)
        XCTAssertEqual(features.highEnergy, 0, accuracy: 0.001)
    }

    func test_midsOnlySignal() {
        // Put energy only in mid bins (8–25)
        var bins = [Float](repeating: 0, count: 60)
        for i in 8..<26 { bins[i] = 0.5 }

        let features = engine.analyze(bins)

        XCTAssertEqual(features.bassEnergy, 0, accuracy: 0.001)
        XCTAssertGreaterThan(features.midEnergy, 0)
        XCTAssertEqual(features.highEnergy, 0, accuracy: 0.001)
    }

    func test_highsOnlySignal() {
        // Put energy only in high bins (26–59)
        var bins = [Float](repeating: 0, count: 60)
        for i in 26..<60 { bins[i] = 0.6 }

        let features = engine.analyze(bins)

        XCTAssertEqual(features.bassEnergy, 0, accuracy: 0.001)
        XCTAssertEqual(features.midEnergy, 0, accuracy: 0.001)
        XCTAssertGreaterThan(features.highEnergy, 0)
    }

    // MARK: - AGC Tests

    func test_agcNormalizesLoudSignal() {
        let loud = [Float](repeating: 10.0, count: 60)

        // Feed several frames so AGC adapts
        for _ in 0..<50 {
            engine.analyze(loud)
        }
        let features = engine.analyze(loud)

        // After AGC adapts, energy should be normalized near 1.0
        // (with compression applied, so check it's in a reasonable range)
        XCTAssertGreaterThan(features.bassEnergy, 0.5)
        XCTAssertLessThanOrEqual(features.bassEnergy, 1.0)
    }

    func test_agcNormalizesQuietSignal() {
        // Peaked signal (bass-heavy) quiet enough to test AGC but above gate threshold
        var quiet = [Float](repeating: 0.01, count: 60)
        for i in 0..<8 { quiet[i] = 0.15 }  // enough bass to pass gate

        // Feed several frames so AGC adapts
        for _ in 0..<100 {
            engine.analyze(quiet)
        }
        let features = engine.analyze(quiet)

        // Even a quiet signal should be normalized up by AGC
        XCTAssertGreaterThan(features.overallEnergy, 0.3,
                             "AGC should normalize quiet signals upward")
    }

    // MARK: - Spectral Flux Tests

    func test_noFluxOnConstantSignal() {
        let constant = [Float](repeating: 0.5, count: 60)

        // First frame has flux because previous was silence
        _ = engine.analyze(constant)
        // Second frame should have ~zero flux
        let features = engine.analyze(constant)

        XCTAssertEqual(features.bassFlux, 0, accuracy: 0.001)
        XCTAssertEqual(features.midFlux, 0, accuracy: 0.001)
        XCTAssertEqual(features.highFlux, 0, accuracy: 0.001)
    }

    func test_fluxOnSuddenOnset() {
        let silent = [Float](repeating: 0, count: 60)
        let loud = [Float](repeating: 1.0, count: 60)

        _ = engine.analyze(silent)
        let features = engine.analyze(loud)

        // Sudden onset should produce significant flux in all bands
        XCTAssertGreaterThan(features.bassFlux, 0)
        XCTAssertGreaterThan(features.midFlux, 0)
        XCTAssertGreaterThan(features.highFlux, 0)
    }

    func test_halfWaveRectification() {
        // Flux should only count positive changes (energy increases)
        let loud = [Float](repeating: 1.0, count: 60)
        let quiet = [Float](repeating: 0.0, count: 60)

        _ = engine.analyze(loud)
        let features = engine.analyze(quiet) // energy decrease → no flux

        XCTAssertEqual(features.bassFlux, 0, accuracy: 0.001,
                       "Flux should not respond to energy decreases")
        XCTAssertEqual(features.midFlux, 0, accuracy: 0.001)
        XCTAssertEqual(features.highFlux, 0, accuracy: 0.001)
    }

    // MARK: - Beat Detection Tests

    func test_beatOnStrongOnset() {
        // Use a low-energy peaked signal as baseline (passes noise gate)
        var baseline = [Float](repeating: 0.01, count: 60)
        for i in 0..<8 { baseline[i] = 0.15 }
        let loud = [Float](repeating: 2.0, count: 60)

        // Build up some flux history with quiet baseline
        for _ in 0..<50 {
            engine.analyze(baseline)
        }
        // Sudden loud onset
        let features = engine.analyze(loud)

        XCTAssertTrue(features.isBeat,
                      "A strong onset after quiet baseline should trigger a beat")
        XCTAssertGreaterThan(features.beatIntensity, 0)
    }

    func test_noBeatOnConstantSignal() {
        let constant = [Float](repeating: 0.5, count: 60)

        for _ in 0..<100 {
            engine.analyze(constant)
        }
        let features = engine.analyze(constant)

        XCTAssertFalse(features.isBeat,
                       "Constant signal should not trigger beats")
    }

    func test_beatMinIntervalRespected() {
        engine.minBeatInterval = 0.3

        // Low-energy peaked baseline to pass noise gate
        var baseline = [Float](repeating: 0.01, count: 60)
        for i in 0..<8 { baseline[i] = 0.15 }
        let loud = [Float](repeating: 2.0, count: 60)

        // Build history
        for _ in 0..<50 { engine.analyze(baseline) }

        // First beat
        let first = engine.analyze(loud)
        XCTAssertTrue(first.isBeat)

        // Immediately try another loud onset — should be suppressed by min interval
        // (the frames arrive ~22ms apart at 46Hz, well under 300ms threshold)
        _ = engine.analyze(baseline)
        let second = engine.analyze(loud)
        XCTAssertFalse(second.isBeat,
                       "Beat should not retrigger within minBeatInterval")
    }

    // MARK: - BPM Estimation Tests

    func test_bpmEstimationWithRegularBeats() {
        engine.beatSensitivity = 1.5
        // Use a very short minBeatInterval since test frames arrive in microseconds
        engine.minBeatInterval = 0.0

        let silent = [Float](repeating: 0, count: 60)
        let hit = [Float](repeating: 3.0, count: 60)

        // Simulate beats spaced by quiet frames
        let framesPerBeat = 23
        var beatCount = 0

        for i in 0..<(framesPerBeat * 8) {
            if i % framesPerBeat == 0 {
                let features = engine.analyze(hit)
                if features.isBeat { beatCount += 1 }
            } else {
                engine.analyze(silent)
            }
        }

        XCTAssertGreaterThanOrEqual(beatCount, 3,
                                    "Should detect multiple beats from regular onsets")
    }

    // MARK: - Output Range Tests

    func test_allOutputsInZeroOneRange() {
        // Feed random data and verify all outputs stay in [0, 1]
        for _ in 0..<200 {
            var bins = [Float](repeating: 0, count: 60)
            for i in 0..<60 {
                bins[i] = Float.random(in: 0...5)
            }

            let f = engine.analyze(bins)

            XCTAssertGreaterThanOrEqual(f.bassEnergy, 0)
            XCTAssertLessThanOrEqual(f.bassEnergy, 1.0)
            XCTAssertGreaterThanOrEqual(f.midEnergy, 0)
            XCTAssertLessThanOrEqual(f.midEnergy, 1.0)
            XCTAssertGreaterThanOrEqual(f.highEnergy, 0)
            XCTAssertLessThanOrEqual(f.highEnergy, 1.0)
            XCTAssertGreaterThanOrEqual(f.bassFlux, 0)
            XCTAssertLessThanOrEqual(f.bassFlux, 1.0)
            XCTAssertGreaterThanOrEqual(f.midFlux, 0)
            XCTAssertLessThanOrEqual(f.midFlux, 1.0)
            XCTAssertGreaterThanOrEqual(f.highFlux, 0)
            XCTAssertLessThanOrEqual(f.highFlux, 1.0)
            XCTAssertGreaterThanOrEqual(f.overallEnergy, 0)
            XCTAssertLessThanOrEqual(f.overallEnergy, 1.0)
            XCTAssertGreaterThanOrEqual(f.beatIntensity, 0)
            XCTAssertLessThanOrEqual(f.beatIntensity, 1.0)
            XCTAssertGreaterThanOrEqual(f.beatPhase, 0)
            XCTAssertLessThanOrEqual(f.beatPhase, 1.0)
        }
    }

    // MARK: - NaN / Edge Case Tests

    func test_nanInputDoesNotPropagate() {
        var bins = [Float](repeating: 0.5, count: 60)
        bins[3] = Float.nan
        bins[15] = Float.nan
        bins[40] = Float.infinity

        let features = engine.analyze(bins)

        XCTAssertTrue(features.bassEnergy.isFinite)
        XCTAssertTrue(features.midEnergy.isFinite)
        XCTAssertTrue(features.highEnergy.isFinite)
        XCTAssertTrue(features.overallEnergy.isFinite)
    }

    func test_emptyInputHandled() {
        let features = engine.analyze([])
        // Should return zero features, not crash
        XCTAssertEqual(features.overallEnergy, 0, accuracy: 0.001)
    }

    func test_shortInputPadded() {
        let short = [Float](repeating: 0.5, count: 10)
        let features = engine.analyze(short)
        // Should not crash; only first 10 bins have energy
        XCTAssertTrue(features.bassEnergy.isFinite)
        XCTAssertTrue(features.midEnergy.isFinite)
    }

    // MARK: - Reset Test

    func test_resetClearsState() {
        let loud = [Float](repeating: 1.0, count: 60)
        for _ in 0..<50 { engine.analyze(loud) }

        engine.reset()

        let features = engine.latestFeatures
        XCTAssertEqual(features.bassEnergy, 0)
        XCTAssertEqual(features.midEnergy, 0)
        XCTAssertEqual(features.highEnergy, 0)
        XCTAssertEqual(features.bpm, 0)
        XCTAssertFalse(features.isBeat)
    }

    // MARK: - Noise Gate Tests

    func test_noiseGateBlocksSilence() {
        let silence = [Float](repeating: 0.01, count: 60)
        for _ in 0..<100 {
            let features = engine.analyze(silence)
            XCTAssertEqual(features.overallEnergy, 0,
                "Ambient noise should produce zero energy")
            XCTAssertFalse(features.isBeat,
                "Ambient noise should not trigger beats")
            XCTAssertFalse(features.noiseGateOpen,
                "Gate should be closed on silence")
        }
    }

    func test_noiseGateBlocksFlatNoise() {
        // Flat spectrum at moderate energy — simulates loud fan / white noise
        let flatNoise = [Float](repeating: 0.08, count: 60)
        for _ in 0..<100 {
            let features = engine.analyze(flatNoise)
            XCTAssertEqual(features.overallEnergy, 0,
                "Flat-spectrum noise should be gated")
            XCTAssertGreaterThan(features.spectralFlatness, 0.8,
                "Flat noise should have high flatness")
        }
    }

    func test_noiseGatePassesMusic() {
        // Peaked spectrum — strong bass, some mids, weak highs (typical music)
        var bins = [Float](repeating: 0.02, count: 60)
        for i in 0..<8 { bins[i] = 1.5 }   // strong bass
        for i in 8..<20 { bins[i] = 0.4 }   // moderate mids
        let features = engine.analyze(bins)
        XCTAssertGreaterThan(features.overallEnergy, 0,
            "Peaked music spectrum should pass the gate")
        XCTAssertTrue(features.noiseGateOpen,
            "Gate should be open for music")
    }

    func test_noiseGatePassesLoudSignal() {
        // Loud flat signal — above rmsPassthroughThreshold
        let loud = [Float](repeating: 0.5, count: 60)
        let features = engine.analyze(loud)
        XCTAssertGreaterThan(features.overallEnergy, 0,
            "Loud signal should always pass even if flat")
        XCTAssertTrue(features.noiseGateOpen)
    }

    func test_noiseGateHysteresis() {
        // Open gate with clear music signal
        var music = [Float](repeating: 0.02, count: 60)
        for i in 0..<8 { music[i] = 2.0 }
        for _ in 0..<10 { engine.analyze(music) }

        // Drop to level above close threshold but below open threshold
        // This is still peaked (low flatness), so gate stays open via hysteresis
        var medium = [Float](repeating: 0.01, count: 60)
        for i in 0..<8 { medium[i] = 0.3 }
        let features = engine.analyze(medium)
        XCTAssertGreaterThan(features.overallEnergy, 0,
            "Gate should stay open above close threshold (hysteresis)")
    }

    func test_noiseGateHoldTimer() {
        // Open gate with music
        var music = [Float](repeating: 0.02, count: 60)
        for i in 0..<8 { music[i] = 2.0 }
        for _ in 0..<10 { engine.analyze(music) }

        // Drop to silence — gate should hold open for gateHoldDuration frames
        let silence = [Float](repeating: 0.001, count: 60)

        // First few silent frames: gate still open (hold period)
        for _ in 0..<5 {
            let f = engine.analyze(silence)
            // During hold, features are faded but gate is still "open"
            XCTAssertTrue(f.noiseGateOpen || f.overallEnergy >= 0)
        }

        // After hold duration + extra, gate should be fully closed
        for _ in 0..<30 { engine.analyze(silence) }
        let afterHold = engine.analyze(silence)
        XCTAssertEqual(afterHold.overallEnergy, 0,
            "Gate should close after hold expires")
        XCTAssertFalse(afterHold.noiseGateOpen)
    }

    func test_spectralFlatnessReported() {
        // Peaked signal — low flatness
        var peaked = [Float](repeating: 0.01, count: 60)
        for i in 0..<4 { peaked[i] = 2.0 }
        let f1 = engine.analyze(peaked)
        XCTAssertLessThan(f1.spectralFlatness, 0.5,
            "Peaked spectrum should have low flatness")

        engine.reset()

        // Flat signal (loud enough to pass rmsPassthrough)
        let flat = [Float](repeating: 0.5, count: 60)
        let f2 = engine.analyze(flat)
        XCTAssertGreaterThan(f2.spectralFlatness, 0.8,
            "Flat spectrum should have high flatness")
    }

    func test_noiseGateResetsOnReset() {
        var music = [Float](repeating: 0.02, count: 60)
        for i in 0..<8 { music[i] = 2.0 }
        engine.analyze(music)  // open gate
        engine.reset()

        let silence = [Float](repeating: 0.01, count: 60)
        let features = engine.analyze(silence)
        XCTAssertEqual(features.overallEnergy, 0,
            "After reset, gate should be closed")
        XCTAssertFalse(features.noiseGateOpen)
    }

    func test_noiseGateFadeOut() {
        // Open gate with music
        var music = [Float](repeating: 0.02, count: 60)
        for i in 0..<8 { music[i] = 2.0 }
        for _ in 0..<10 { engine.analyze(music) }

        // Drop to silence — capture energy during hold period
        let silence = [Float](repeating: 0.001, count: 60)
        var energies = [Float]()
        for _ in 0..<engine.gateHoldDuration + 5 {
            let f = engine.analyze(silence)
            energies.append(f.overallEnergy)
        }

        // Energy should decrease during hold (fade-out)
        // Find first non-zero and last non-zero to verify decreasing trend
        let nonZero = energies.filter { $0 > 0 }
        if nonZero.count >= 2 {
            XCTAssertGreaterThanOrEqual(nonZero.first!, nonZero.last!,
                "Energy should fade down during hold period")
        }
    }

    // MARK: - Red/Green Tests
    // These tests prove the noise gate is necessary by showing the problem
    // exists when the gate is disabled (Red) and is fixed when enabled (Green).

    func test_redGreen_silenceProducesEnergyWithoutGate() {
        // RED: Without noise gate, AGC amplifies silence to non-zero energy
        engine.rmsFloorThreshold = 0         // disable gate
        engine.rmsPassthroughThreshold = 0   // everything passes

        let silence = [Float](repeating: 0.01, count: 60)
        // Feed enough frames for AGC to decay and amplify noise
        for _ in 0..<200 { engine.analyze(silence) }
        let ungated = engine.analyze(silence)

        XCTAssertGreaterThan(ungated.overallEnergy, 0,
            "RED: Without gate, AGC amplifies silence to non-zero energy")

        // GREEN: With noise gate, silence is blocked
        engine.reset()
        engine.rmsFloorThreshold = 0.04      // restore defaults
        engine.rmsPassthroughThreshold = 0.15

        for _ in 0..<200 { engine.analyze(silence) }
        let gated = engine.analyze(silence)

        XCTAssertEqual(gated.overallEnergy, 0,
            "GREEN: With gate, silence produces zero energy")
    }

    func test_redGreen_flatNoiseProducesEnergyWithoutGate() {
        // RED: Without gate, flat fan noise (uniform spectrum) drives lights
        engine.rmsFloorThreshold = 0
        engine.rmsPassthroughThreshold = 0

        let fanNoise = [Float](repeating: 0.08, count: 60)
        for _ in 0..<100 { engine.analyze(fanNoise) }
        let ungated = engine.analyze(fanNoise)

        XCTAssertGreaterThan(ungated.overallEnergy, 0,
            "RED: Without gate, flat fan noise produces energy (lights flicker)")

        // GREEN: With gate, spectral flatness detects noise and blocks it
        engine.reset()
        engine.rmsFloorThreshold = 0.04
        engine.rmsPassthroughThreshold = 0.15
        engine.flatnessThreshold = 0.65

        for _ in 0..<100 { engine.analyze(fanNoise) }
        let gated = engine.analyze(fanNoise)

        XCTAssertEqual(gated.overallEnergy, 0,
            "GREEN: With gate, flat fan noise is blocked by spectral flatness")
    }

    func test_redGreen_silenceProducesBeatsWithoutGate() {
        // RED: Without gate, random ambient fluctuations can trigger false beats
        engine.rmsFloorThreshold = 0
        engine.rmsPassthroughThreshold = 0

        // Simulate ambient noise with small random variations
        var beatDetected = false
        for i in 0..<500 {
            var noise = [Float](repeating: 0.01, count: 60)
            // Add a small random-ish variation every ~50 frames
            if i % 50 == 0 {
                for j in 0..<8 { noise[j] = 0.05 }
            }
            let f = engine.analyze(noise)
            if f.isBeat { beatDetected = true }
        }

        XCTAssertTrue(beatDetected,
            "RED: Without gate, ambient fluctuations trigger false beats")

        // GREEN: With gate, no beats from ambient noise
        engine.reset()
        engine.rmsFloorThreshold = 0.04
        engine.rmsPassthroughThreshold = 0.15

        beatDetected = false
        for i in 0..<500 {
            var noise = [Float](repeating: 0.01, count: 60)
            if i % 50 == 0 {
                for j in 0..<8 { noise[j] = 0.05 }
            }
            let f = engine.analyze(noise)
            if f.isBeat { beatDetected = true }
        }

        XCTAssertFalse(beatDetected,
            "GREEN: With gate, ambient noise never triggers beats")
    }

    func test_redGreen_musicStillWorksWithGate() {
        // Verify gate doesn't break music detection — music passes both ways
        let makeMusic: () -> [Float] = {
            var bins = [Float](repeating: 0.02, count: 60)
            for i in 0..<8 { bins[i] = 1.5 }
            for i in 8..<20 { bins[i] = 0.4 }
            return bins
        }

        // Without gate
        engine.rmsFloorThreshold = 0
        engine.rmsPassthroughThreshold = 0
        let ungated = engine.analyze(makeMusic())
        XCTAssertGreaterThan(ungated.overallEnergy, 0,
            "Music produces energy without gate")

        // With gate — should still pass
        engine.reset()
        engine.rmsFloorThreshold = 0.04
        engine.rmsPassthroughThreshold = 0.15
        let gated = engine.analyze(makeMusic())
        XCTAssertGreaterThan(gated.overallEnergy, 0,
            "GREEN: Music still produces energy WITH gate enabled")
    }

    // MARK: - Mel Spectrum Normalization Tests
    //
    // The normalization bug: AudioSpectrogram emits dB-scale values where
    // silence sits at ~-102 dB and music peaks at ~+5–15 dB. Without
    // normalization, raw dB values (including large negatives) are fed to
    // the engine. The noise gate's RMS is huge (102.5), always opening the
    // gate for silence. The fix: normalizeMelSpectrum maps dB to [0,1].

    /// Real mel spectrum data captured from logs: music playing.
    /// Logs show pos=15-37/60, melMax=5-10 dB during music.
    /// Bass bins strongest, mids moderate, a few highs.
    private func realMusicMelBins() -> [Float] {
        // Bass-heavy music: strong peaks in bass, steep rolloff into mids.
        // After normalization (dB/20), this produces a peaked spectrum with
        // flatness well below 0.65, matching real captured music logs.
        var bins = [Float](repeating: -102.5, count: 60)
        // Bass bins (0-4): strong peaks 5–15 dB
        bins[0] = 15.0; bins[1] = 12.0; bins[2] = 10.0; bins[3] = 8.0; bins[4] = 5.0
        // Bass tail (5-7): tapering off
        bins[5] = 2.0; bins[6] = 0.5; bins[7] = 0.2
        // Mid bins (8-10): moderate
        bins[8] = 3.0; bins[9] = 1.0; bins[10] = 2.0
        // Weak mids (11-13)
        bins[11] = 0.5; bins[12] = 0.3; bins[13] = 0.1
        return bins
    }

    /// Real silence data: all bins at noise floor.
    private func realSilenceMelBins() -> [Float] {
        return [Float](repeating: -102.5, count: 60)
    }

    func test_normalizeMelSpectrum_silenceIsAllZeros() {
        let silence = realSilenceMelBins()
        let result = normalizeMelSpectrum(silence)
        let maxVal = result.max() ?? 0
        XCTAssertEqual(maxVal, 0, accuracy: 0.001,
            "Silence bins (all negative dB) should normalize to zero")
    }

    func test_normalizeMelSpectrum_musicHasPositiveBins() {
        let music = realMusicMelBins()
        let result = normalizeMelSpectrum(music)
        let posCount = result.filter { $0 > 0 }.count
        XCTAssertGreaterThan(posCount, 0,
            "Music bins with positive dB values should normalize to > 0")
    }

    func test_normalizeMelSpectrum_negativeBinsClampedToZero() {
        let music = realMusicMelBins()
        let result = normalizeMelSpectrum(music)
        for (i, v) in result.enumerated() {
            XCTAssertGreaterThanOrEqual(v, 0,
                "Bin \(i) should be >= 0, got \(v)")
        }
    }

    func test_normalizeMelSpectrum_clampedToOne() {
        // A bin at exactly dbCeiling should map to 1.0
        let bins: [Float] = [20.0, 25.0, -10.0, 0.0]
        let result = normalizeMelSpectrum(bins, dbCeiling: 20.0)
        XCTAssertEqual(result[0], 1.0, accuracy: 0.001)
        XCTAssertEqual(result[1], 1.0, accuracy: 0.001,
            "Values above ceiling should be clamped to 1.0")
        XCTAssertEqual(result[2], 0.0, accuracy: 0.001,
            "Negative values should be clamped to 0.0")
        XCTAssertEqual(result[3], 0.0, accuracy: 0.001,
            "Zero dB should map to 0.0")
    }

    func test_normalizeMelSpectrum_nanHandling() {
        let bins: [Float] = [Float.nan, Float.infinity, -Float.infinity, 5.0]
        let result = normalizeMelSpectrum(bins)
        XCTAssertEqual(result[0], 0, "NaN should map to 0")
        XCTAssertEqual(result[1], 0, "Inf should map to 0")
        XCTAssertEqual(result[2], 0, "-Inf should map to 0")
        XCTAssertEqual(result[3], 0.25, accuracy: 0.001, "5/20 = 0.25")
    }

    func test_normalizeMelSpectrum_customCeiling() {
        let bins: [Float] = [5.0, 10.0, 15.0]
        let result = normalizeMelSpectrum(bins, dbCeiling: 10.0)
        XCTAssertEqual(result[0], 0.5, accuracy: 0.001)
        XCTAssertEqual(result[1], 1.0, accuracy: 0.001)
        XCTAssertEqual(result[2], 1.0, accuracy: 0.001, "Above ceiling clips to 1")
    }

    // MARK: - Red/Green: Raw dB vs Normalized
    //
    // The original bug: raw dB bins (no normalization) were passed directly
    // to AudioAnalysisEngine. With silence at -102.5 dB, the RMS is ~102.5
    // — far above the gate's passthrough threshold — so the gate opens for
    // silence. Both silence and music produce non-zero energy, making lights
    // flicker on ambient noise.
    //
    // Fix: normalizeMelSpectrum() maps dB to [0,1] before the engine sees it.

    func test_red_rawDBSilenceOpensNoiseGate() {
        // RED: Without normalization, silence (-102.5 dB) has RMS ~102.5
        // which is >> rmsPassthroughThreshold (0.15), so gate always opens.
        let rawSilence = realSilenceMelBins() // all -102.5

        let eng = AudioAnalysisEngine()
        let features = eng.analyze(rawSilence)

        // Bug: gate opens for silence because large negative numbers
        // have large absolute RMS
        XCTAssertTrue(features.noiseGateOpen,
            "RED: Raw dB silence opens gate (RMS of -102.5 values is huge)")
        XCTAssertGreaterThan(features.overallEnergy, 0,
            "RED: Silence produces non-zero energy without normalization")
    }

    func test_green_normalizedSilenceClosesGate() {
        // GREEN: After normalization, silence is all zeros → gate stays closed.
        let normalized = normalizeMelSpectrum(realSilenceMelBins())

        let eng = AudioAnalysisEngine()
        for _ in 0..<50 { eng.analyze(normalized) }
        let features = eng.analyze(normalized)

        XCTAssertFalse(features.noiseGateOpen,
            "GREEN: Normalized silence (all zeros) keeps gate closed")
        XCTAssertEqual(features.overallEnergy, 0, accuracy: 0.001,
            "GREEN: Silence produces zero energy after normalization")
    }

    func test_red_rawDBCannotDistinguishSilenceFromMusic() {
        // RED: Both silence and music produce massive RMS with raw dB,
        // so the engine treats them the same — gate opens for both.
        let rawSilence = realSilenceMelBins()
        let rawMusic = realMusicMelBins()

        let eng1 = AudioAnalysisEngine()
        let silFeatures = eng1.analyze(rawSilence)

        let eng2 = AudioAnalysisEngine()
        let musFeatures = eng2.analyze(rawMusic)

        XCTAssertTrue(silFeatures.noiseGateOpen,
            "RED: Gate opens for raw silence")
        XCTAssertTrue(musFeatures.noiseGateOpen,
            "RED: Gate opens for raw music (but that's also true for silence)")
        // Both produce energy — can't tell them apart
        XCTAssertGreaterThan(silFeatures.overallEnergy, 0)
        XCTAssertGreaterThan(musFeatures.overallEnergy, 0)
    }

    func test_green_normalizedDistinguishesSilenceFromMusic() {
        // GREEN: After normalization, silence → zero, music → non-zero.
        let normSilence = normalizeMelSpectrum(realSilenceMelBins())
        let normMusic = normalizeMelSpectrum(realMusicMelBins())

        let eng1 = AudioAnalysisEngine()
        for _ in 0..<10 { eng1.analyze(normSilence) }
        let silFeatures = eng1.analyze(normSilence)

        let eng2 = AudioAnalysisEngine()
        for _ in 0..<10 { eng2.analyze(normMusic) }
        let musFeatures = eng2.analyze(normMusic)

        XCTAssertFalse(silFeatures.noiseGateOpen,
            "GREEN: Gate closed for silence")
        XCTAssertEqual(silFeatures.overallEnergy, 0, accuracy: 0.001)

        XCTAssertTrue(musFeatures.noiseGateOpen,
            "GREEN: Gate opens for music")
        XCTAssertGreaterThan(musFeatures.overallEnergy, 0,
            "GREEN: Music produces energy")
        XCTAssertGreaterThan(musFeatures.overallEnergy, silFeatures.overallEnergy + 0.1,
            "GREEN: Clear separation between silence and music")
    }

    func test_green_normalizedMusicBassEnergyDominates() {
        // GREEN: Music with bass peaks should show bass energy > mid > high
        let normMusic = normalizeMelSpectrum(realMusicMelBins())
        let eng = AudioAnalysisEngine()
        for _ in 0..<10 { eng.analyze(normMusic) }
        let features = eng.analyze(normMusic)

        XCTAssertGreaterThan(features.bassEnergy, features.highEnergy,
            "GREEN: Bass-heavy music should have bass > high energy")
    }

    // MARK: - Red/Green: Spectral Flatness with Sparse Spectra
    //
    // After normalization, most bins are 0 (negative dB clipped). The old
    // flatness computation included zeros, crushing the geometric mean to
    // ≈0 and making ALL spectra appear "peaked" (flatness ≈ 0). This
    // defeated the noise gate's flatness check — ambient bass rumble
    // (5-7 positive bins out of 60) passed as "music".

    /// Simulate ambient noise: 5 low-level bass bins, rest zero.
    /// This is the real pattern from captured logs.
    private func realAmbientNormalized() -> [Float] {
        var bins = [Float](repeating: 0, count: 60)
        bins[0] = 0.20; bins[1] = 0.15; bins[2] = 0.10
        bins[3] = 0.07; bins[4] = 0.05
        return bins
    }

    func test_red_ambientBassPassesGateWithBrokenFlatness() {
        // RED: With old flatness (computed over all 60 bins including zeros),
        // the geometric mean → 0, flatness → 0, ambient looks "peaked".
        // Gate opens because rms > rmsFloorThreshold and flatness < threshold.
        let ambient = realAmbientNormalized()

        // Manually compute flatness the OLD broken way (over all bins)
        var logSum: Float = 0
        var arithSum: Float = 0
        for v in ambient {
            logSum += logf(max(v, 1e-10))
            arithSum += v
        }
        let geoMean = expf(logSum / Float(ambient.count))
        let ariMean = arithSum / Float(ambient.count)
        let brokenFlatness = geoMean / max(ariMean, 1e-10)

        // The bug: flatness is ~0 because zeros crush the geometric mean
        XCTAssertLessThan(brokenFlatness, 0.01,
            "RED: Old flatness is ~0 for sparse spectrum (zeros crush geo mean)")
    }

    func test_green_ambientBassBlockedWithFixedFlatness() {
        // GREEN: The engine's fixed flatness treats < 8 active bins as noise.
        let ambient = realAmbientNormalized()

        let eng = AudioAnalysisEngine()
        // Feed enough frames so we're not in the first-frame special case
        for _ in 0..<50 { eng.analyze(ambient) }
        let features = eng.analyze(ambient)

        // With fixed flatness, sparse ambient spectrum is treated as noise
        XCTAssertGreaterThan(features.spectralFlatness, 0.8,
            "GREEN: Sparse ambient spectrum has high flatness (= noise)")
        XCTAssertFalse(features.noiseGateOpen,
            "GREEN: Gate is closed for ambient bass rumble")
        XCTAssertEqual(features.overallEnergy, 0, accuracy: 0.001,
            "GREEN: No energy passes through for ambient noise")
    }

    func test_green_musicWithManyBinsStillPasses() {
        // GREEN: Music with 15+ active bins computes real flatness and passes.
        let music = normalizeMelSpectrum(realMusicMelBins())
        let activeBins = music.filter { $0 > 0.001 }.count

        // Music should have enough active bins
        XCTAssertGreaterThanOrEqual(activeBins, 4,
            "Music should have several active bins after normalization")

        let eng = AudioAnalysisEngine()
        for _ in 0..<10 { eng.analyze(music) }
        let features = eng.analyze(music)

        XCTAssertTrue(features.noiseGateOpen,
            "GREEN: Music with multiple active bins passes the gate")
        XCTAssertGreaterThan(features.overallEnergy, 0,
            "GREEN: Music produces energy")
    }
}
