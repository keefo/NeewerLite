//
//  SoundToLightModeTests.swift
//  NeewerLiteTests
//
//  Created on 2026-04-11.
//

import XCTest
@testable import NeewerLite

final class SoundToLightModeTests: XCTestCase {

    // MARK: - Pulse Mode Tests

    func test_pulse_beatTriggersHighBrightness() {
        var mode = PulseMode()
        var features = AudioFeatures.zero
        features.isBeat = true
        features.beatIntensity = 1.0

        let cmd = mode.process(features)

        XCTAssertGreaterThan(cmd.brightness, 0.8,
                             "A full-intensity beat should produce high brightness")
    }

    func test_pulse_silenceDecaysToBase() {
        var mode = PulseMode()
        let silent = AudioFeatures.zero

        // Trigger a beat first
        var beat = AudioFeatures.zero
        beat.isBeat = true
        beat.beatIntensity = 1.0
        _ = mode.process(beat)

        // Run many silent frames
        var cmd = LightCommand()
        for _ in 0..<200 {
            cmd = mode.process(silent)
        }

        XCTAssertLessThan(cmd.brightness, mode.baseBrightness + 0.05,
                          "After many silent frames, brightness should decay near base")
    }

    func test_pulse_brightnessClamped() {
        var mode = PulseMode()
        var features = AudioFeatures.zero
        features.isBeat = true
        features.beatIntensity = 1.0

        // Rapid beats should not exceed 1.0
        for _ in 0..<10 {
            let cmd = mode.process(features)
            XCTAssertLessThanOrEqual(cmd.brightness, 1.0)
            XCTAssertGreaterThanOrEqual(cmd.brightness, 0.0)
        }
    }

    func test_pulse_supportsBothModes() {
        let mode = PulseMode()
        XCTAssertTrue(mode.supportsHSI)
        XCTAssertTrue(mode.supportsCCT)
    }

    func test_pulse_reset() {
        var mode = PulseMode()
        var beat = AudioFeatures.zero
        beat.isBeat = true
        beat.beatIntensity = 1.0
        _ = mode.process(beat)

        mode.reset()

        let cmd = mode.process(AudioFeatures.zero)
        XCTAssertLessThanOrEqual(cmd.brightness, mode.baseBrightness + 0.01,
                                 "After reset, should be at base brightness")
    }

    // MARK: - Color Flow Mode Tests

    func test_colorFlow_bassProducesWarmHue() {
        var mode = ColorFlowMode()

        var features = AudioFeatures.zero
        features.bassEnergy = 1.0
        features.midEnergy = 0.0
        features.highEnergy = 0.0
        features.overallEnergy = 0.5

        // Run several frames for smoothing to converge
        var cmd = LightCommand()
        for _ in 0..<100 {
            cmd = mode.process(features)
        }

        // Should be near warmHue (20°)
        let hueDist = min(abs(cmd.hue - mode.warmHue), 360 - abs(cmd.hue - mode.warmHue))
        XCTAssertLessThan(hueDist, 30,
                          "Bass-dominant signal should produce warm hue near \(mode.warmHue)°, got \(cmd.hue)°")
    }

    func test_colorFlow_highsProduceCoolHue() {
        var mode = ColorFlowMode()

        var features = AudioFeatures.zero
        features.bassEnergy = 0.0
        features.midEnergy = 0.0
        features.highEnergy = 1.0
        features.overallEnergy = 0.5

        var cmd = LightCommand()
        for _ in 0..<100 {
            cmd = mode.process(features)
        }

        // Should be near coolHue (260°)
        let hueDist = min(abs(cmd.hue - mode.coolHue), 360 - abs(cmd.hue - mode.coolHue))
        XCTAssertLessThan(hueDist, 30,
                          "Highs-dominant signal should produce cool hue near \(mode.coolHue)°, got \(cmd.hue)°")
    }

    func test_colorFlow_brightnessNeverBelowFloor() {
        var mode = ColorFlowMode()

        let cmd = mode.process(AudioFeatures.zero)

        XCTAssertGreaterThanOrEqual(cmd.brightness, mode.brightnessFloor * 0.9,
                                    "Brightness should never go far below the floor")
    }

    func test_colorFlow_hsiOnly() {
        let mode = ColorFlowMode()
        XCTAssertTrue(mode.supportsHSI)
        XCTAssertFalse(mode.supportsCCT)
    }

    // MARK: - Bass Cannon Mode Tests

    func test_bassCannon_strongBassHighBrightness() {
        var mode = BassCannonMode()

        var features = AudioFeatures.zero
        features.bassEnergy = 1.0

        var cmd = LightCommand()
        for _ in 0..<50 {
            cmd = mode.process(features)
        }

        XCTAssertGreaterThan(cmd.brightness, 0.7,
                             "Strong bass should produce high brightness")
    }

    func test_bassCannon_strongBassWarmCCT() {
        var mode = BassCannonMode()

        var features = AudioFeatures.zero
        features.bassEnergy = 1.0

        var cmd = LightCommand()
        for _ in 0..<50 {
            cmd = mode.process(features)
        }

        XCTAssertLessThan(cmd.cct, 40,
                          "Strong bass should produce warm CCT (near 32), got \(cmd.cct)")
    }

    func test_bassCannon_silenceQuietAndCool() {
        var mode = BassCannonMode()

        var cmd = LightCommand()
        for _ in 0..<100 {
            cmd = mode.process(AudioFeatures.zero)
        }

        XCTAssertLessThan(cmd.brightness, 0.3,
                          "Silence should produce low brightness")
        XCTAssertGreaterThan(cmd.cct, 48,
                             "Silence should produce cool CCT")
    }

    func test_bassCannon_supportsBothModes() {
        let mode = BassCannonMode()
        XCTAssertTrue(mode.supportsHSI)
        XCTAssertTrue(mode.supportsCCT)
    }

    // MARK: - Strobe Mode Tests

    func test_strobe_flashOnBeat() {
        var mode = StrobeMode()

        // Start with silence
        let silenceCmd = mode.process(AudioFeatures.zero)
        let silenceBrr = silenceCmd.brightness

        // Trigger a beat
        var features = AudioFeatures.zero
        features.isBeat = true
        features.beatIntensity = 1.0
        let flashCmd = mode.process(features)

        XCTAssertGreaterThan(flashCmd.brightness, silenceBrr + 0.5,
                             "Beat should flash to high brightness")
    }

    func test_strobe_decaysAfterFlash() {
        var mode = StrobeMode()

        // Trigger a beat
        var features = AudioFeatures.zero
        features.isBeat = true
        features.beatIntensity = 1.0
        let flashCmd = mode.process(features)

        // Process silence frames — should decay
        var lastBrr = flashCmd.brightness
        for _ in 0..<20 {
            let cmd = mode.process(AudioFeatures.zero)
            XCTAssertLessThanOrEqual(cmd.brightness, lastBrr + 0.001,
                                     "Brightness should decay, not increase")
            lastBrr = cmd.brightness
        }

        XCTAssertLessThan(lastBrr, 0.3,
                          "After 20 frames of decay, brightness should be low")
    }

    func test_strobe_rateLimited() {
        var mode = StrobeMode()
        mode.minFlashInterval = 0.33 // ~3 Hz

        // First beat should trigger
        var features = AudioFeatures.zero
        features.isBeat = true
        features.beatIntensity = 1.0
        let firstFlash = mode.process(features)

        // Immediate second beat should NOT re-trigger (within minFlashInterval)
        let secondFlash = mode.process(features)

        // Second flash brightness should be less than first (decaying, not re-triggered)
        XCTAssertLessThan(secondFlash.brightness, firstFlash.brightness,
                          "Second beat within rate limit should not re-trigger flash")
    }

    func test_strobe_supportsBothModes() {
        let mode = StrobeMode()
        XCTAssertTrue(mode.supportsHSI)
        XCTAssertTrue(mode.supportsCCT)
    }

    func test_strobe_lowSaturation() {
        var mode = StrobeMode()
        var features = AudioFeatures.zero
        features.isBeat = true
        features.beatIntensity = 1.0
        let cmd = mode.process(features)

        XCTAssertLessThan(cmd.saturation, 0.3,
                          "Strobe should have low saturation for white flash effect")
    }

    // MARK: - Aurora Mode Tests

    func test_aurora_smoothBrightness() {
        var mode = AuroraMode()

        // Feed varying bass — output should be smooth (no sudden jumps)
        var prevBrr: Float = mode.process(AudioFeatures.zero).brightness
        var maxDelta: Float = 0

        for i in 0..<200 {
            var features = AudioFeatures.zero
            features.bassEnergy = Float(i % 50) / 50.0  // ramp up and down
            features.highEnergy = 0.3
            features.overallEnergy = 0.4
            let cmd = mode.process(features)
            let delta = abs(cmd.brightness - prevBrr)
            maxDelta = max(maxDelta, delta)
            prevBrr = cmd.brightness
        }

        XCTAssertLessThan(maxDelta, 0.05,
                          "Aurora brightness should change very smoothly per frame, maxDelta=\(maxDelta)")
    }

    func test_aurora_neverGoesDark() {
        var mode = AuroraMode()

        // Feed complete silence for many frames
        for _ in 0..<500 {
            let cmd = mode.process(AudioFeatures.zero)
            XCTAssertGreaterThan(cmd.brightness, 0.2,
                                 "Aurora should never go dark, got \(cmd.brightness)")
        }
    }

    func test_aurora_hsiOnly() {
        let mode = AuroraMode()
        XCTAssertTrue(mode.supportsHSI)
        XCTAssertFalse(mode.supportsCCT, "Aurora is HSI only")
    }

    func test_aurora_fullWheelDrift() {
        // Aurora ignores palettes — it drifts across the full 360° hue wheel
        var mode = AuroraMode()

        var features = AudioFeatures.zero
        features.bassEnergy = 0.5
        features.highEnergy = 0.5
        features.overallEnergy = 0.5

        var hues: [Float] = []
        // Run for many frames to accumulate drift
        for _ in 0..<2000 {
            let cmd = mode.process(features)
            hues.append(cmd.hue)
        }

        // With continuous drift, hue should span a wide range (well over 90°)
        let minHue = hues.min() ?? 0
        let maxHue = hues.max() ?? 0
        let range = maxHue - minHue
        // If it wraps around 360→0, range will be large anyway
        XCTAssertGreaterThan(range, 50,
                             "Aurora should drift broadly across the hue wheel, range=\(range)")
    }

    func test_aurora_slowColorDrift() {
        var mode = AuroraMode()

        // Feed identical features — hue should continuously advance
        var features = AudioFeatures.zero
        features.bassEnergy = 0.4
        features.highEnergy = 0.4
        features.overallEnergy = 0.4

        let first = mode.process(features).hue
        // Run 100 frames (~2.2s)
        var last: Float = first
        for _ in 0..<100 {
            last = mode.process(features).hue
        }

        // Hue should have moved noticeably from the start
        let drift = abs(last - first)
        XCTAssertGreaterThan(drift, 2.0,
                             "Aurora hue should continuously drift, moved \(drift)°")
    }

    // MARK: - BLE Smart Throttle Tests

    func test_throttle_firstCommandAlwaysSent() {
        let throttle = BLESmartThrottle()
        let cmd = LightCommand()

        XCTAssertTrue(throttle.shouldSend(command: cmd, deviceId: "dev1"),
                      "First command should always be sent")
    }

    func test_throttle_identicalCommandSuppressed() {
        let throttle = BLESmartThrottle()
        var cmd = LightCommand()
        cmd.brightness = 0.5
        cmd.hue = 180

        // Send first
        XCTAssertTrue(throttle.shouldSend(command: cmd, deviceId: "dev1"))
        throttle.didSend(command: cmd, deviceId: "dev1")

        // Immediate identical command should be suppressed (within minSendInterval)
        XCTAssertFalse(throttle.shouldSend(command: cmd, deviceId: "dev1"),
                       "Identical command within minSendInterval should be suppressed")
    }

    func test_throttle_significantChangeAllowed() {
        let throttle = BLESmartThrottle()
        throttle.minSendInterval = 0 // disable rate limit for this test

        var cmd1 = LightCommand()
        cmd1.brightness = 0.5
        cmd1.hue = 180

        XCTAssertTrue(throttle.shouldSend(command: cmd1, deviceId: "dev1"))
        throttle.didSend(command: cmd1, deviceId: "dev1")

        // Large brightness change
        var cmd2 = cmd1
        cmd2.brightness = 0.9

        XCTAssertTrue(throttle.shouldSend(command: cmd2, deviceId: "dev1"),
                      "Significant brightness change should pass throttle")
    }

    func test_throttle_hueChangeAllowed() {
        let throttle = BLESmartThrottle()
        throttle.minSendInterval = 0

        var cmd1 = LightCommand()
        cmd1.hue = 100

        XCTAssertTrue(throttle.shouldSend(command: cmd1, deviceId: "dev1"))
        throttle.didSend(command: cmd1, deviceId: "dev1")

        var cmd2 = cmd1
        cmd2.hue = 120 // 20° change > 5° threshold

        XCTAssertTrue(throttle.shouldSend(command: cmd2, deviceId: "dev1"),
                      "Significant hue change should pass throttle")
    }

    func test_throttle_perDeviceIndependence() {
        let throttle = BLESmartThrottle()

        let cmd = LightCommand()

        XCTAssertTrue(throttle.shouldSend(command: cmd, deviceId: "dev1"))
        throttle.didSend(command: cmd, deviceId: "dev1")

        // Different device should still accept
        XCTAssertTrue(throttle.shouldSend(command: cmd, deviceId: "dev2"),
                      "Different device should have independent throttle state")
    }

    func test_throttle_reset() {
        let throttle = BLESmartThrottle()

        let cmd = LightCommand()
        XCTAssertTrue(throttle.shouldSend(command: cmd, deviceId: "dev1"))
        throttle.didSend(command: cmd, deviceId: "dev1")

        throttle.reset()

        // After reset, first command should be accepted again
        XCTAssertTrue(throttle.shouldSend(command: cmd, deviceId: "dev1"),
                      "After reset, should accept commands again")
    }

    // MARK: - Mode Registry Tests

    func test_modeRegistry_allModesCreateSuccessfully() {
        for modeType in SoundToLightModeType.allCases {
            let mode = modeType.createMode()
            XCTAssertFalse(mode.name.isEmpty, "\(modeType.rawValue) should have a name")
        }
    }

    func test_modeRegistry_count() {
        XCTAssertEqual(SoundToLightModeType.allCases.count, 5,
                       "Should have 5 modes (Pulse, Color Flow, Bass Cannon, Strobe, Aurora)")
    }

    // MARK: - LightCommand Output Range Tests

    func test_allModes_outputInValidRange() {
        let modes: [SoundToLightMode] = [PulseMode(), ColorFlowMode(), BassCannonMode(), StrobeMode(), AuroraMode()]

        for var mode in modes {
            // Feed various audio features
            for _ in 0..<100 {
                var features = AudioFeatures.zero
                features.bassEnergy = Float.random(in: 0...1)
                features.midEnergy = Float.random(in: 0...1)
                features.highEnergy = Float.random(in: 0...1)
                features.overallEnergy = Float.random(in: 0...1)
                features.isBeat = Bool.random()
                features.beatIntensity = Float.random(in: 0...1)

                let cmd = mode.process(features)

                XCTAssertGreaterThanOrEqual(cmd.brightness, 0, "\(mode.name) brightness < 0")
                XCTAssertLessThanOrEqual(cmd.brightness, 1.0, "\(mode.name) brightness > 1")
                XCTAssertGreaterThanOrEqual(cmd.hue, 0, "\(mode.name) hue < 0")
                XCTAssertLessThan(cmd.hue, 360, "\(mode.name) hue >= 360")
                XCTAssertGreaterThanOrEqual(cmd.saturation, 0, "\(mode.name) sat < 0")
                XCTAssertLessThanOrEqual(cmd.saturation, 1.0, "\(mode.name) sat > 1")
                XCTAssertGreaterThanOrEqual(cmd.cct, 25, "\(mode.name) cct < 25")
                XCTAssertLessThanOrEqual(cmd.cct, 90, "\(mode.name) cct > 90")
                XCTAssertTrue(cmd.brightness.isFinite, "\(mode.name) brightness NaN")
                XCTAssertTrue(cmd.hue.isFinite, "\(mode.name) hue NaN")
            }
        }
    }

    // MARK: - Reactivity Tests

    func test_reactivity_allCasesHaveDisplayName() {
        for r in Reactivity.allCases {
            XCTAssertFalse(r.displayName.isEmpty, "\(r) should have a display name")
        }
    }

    func test_reactivity_sensitivityIncreases() {
        XCTAssertLessThan(Reactivity.subtle.sensitivity, Reactivity.moderate.sensitivity)
        XCTAssertLessThan(Reactivity.moderate.sensitivity, Reactivity.intense.sensitivity)
        XCTAssertLessThan(Reactivity.intense.sensitivity, Reactivity.extreme.sensitivity)
    }

    func test_reactivity_subtlePulseProducesLowerPeak() {
        var subtleMode = PulseMode()
        subtleMode.reactivity = .subtle
        var extremeMode = PulseMode()
        extremeMode.reactivity = .extreme

        var beat = AudioFeatures.zero
        beat.isBeat = true
        beat.beatIntensity = 1.0

        let subtleCmd = subtleMode.process(beat)
        let extremeCmd = extremeMode.process(beat)

        XCTAssertLessThan(subtleCmd.brightness, extremeCmd.brightness,
                          "Subtle reactivity should produce lower peak brightness than extreme")
    }

    func test_reactivity_modeDefaultIsModerate() {
        let pulse = PulseMode()
        XCTAssertEqual(pulse.reactivity, .moderate)

        let colorFlow = ColorFlowMode()
        XCTAssertEqual(colorFlow.reactivity, .moderate)

        let bassCannon = BassCannonMode()
        XCTAssertEqual(bassCannon.reactivity, .moderate)
    }

    func test_reactivity_allModesValidOutputAtAllLevels() {
        for reactivity in Reactivity.allCases {
            let modes: [SoundToLightMode] = [
                SoundToLightModeType.pulse.createMode(reactivity: reactivity),
                SoundToLightModeType.colorFlow.createMode(reactivity: reactivity),
                SoundToLightModeType.bassCannon.createMode(reactivity: reactivity),
            ]
            for var mode in modes {
                for _ in 0..<50 {
                    var features = AudioFeatures.zero
                    features.bassEnergy = Float.random(in: 0...1)
                    features.midEnergy = Float.random(in: 0...1)
                    features.highEnergy = Float.random(in: 0...1)
                    features.overallEnergy = Float.random(in: 0...1)
                    features.isBeat = Bool.random()
                    features.beatIntensity = Float.random(in: 0...1)

                    let cmd = mode.process(features)
                    XCTAssertGreaterThanOrEqual(cmd.brightness, 0)
                    XCTAssertLessThanOrEqual(cmd.brightness, 1.0)
                    XCTAssertTrue(cmd.brightness.isFinite)
                    XCTAssertTrue(cmd.hue.isFinite)
                }
            }
        }
    }

    // MARK: - Color Palette Tests

    func test_palette_allPalettesHaveNames() {
        for p in ColorPalette.palettes {
            XCTAssertFalse(p.name.isEmpty)
        }
    }

    func test_palette_huesInValidRange() {
        for p in ColorPalette.palettes {
            XCTAssertGreaterThanOrEqual(p.warmHue, 0)
            XCTAssertLessThan(p.warmHue, 360)
            XCTAssertGreaterThanOrEqual(p.coolHue, 0)
            XCTAssertLessThan(p.coolHue, 360)
        }
    }

    func test_palette_appliedToColorFlow() {
        let firePalette = ColorPalette.palettes[3] // Fire: warm=0, cool=50
        var mode = SoundToLightModeType.colorFlow.createMode(
            reactivity: .moderate, palette: firePalette)

        // Feed bass-heavy audio → should lean toward warmHue (0)
        var bassFeatures = AudioFeatures.zero
        bassFeatures.bassEnergy = 0.9
        bassFeatures.highEnergy = 0.05
        bassFeatures.overallEnergy = 0.6

        // Process many frames to converge
        var cmd = LightCommand()
        for _ in 0..<100 {
            cmd = mode.process(bassFeatures)
        }

        // Hue should be near warm (0°) — within a reasonable range
        let hueNear0 = cmd.hue < 30 || cmd.hue > 350
        XCTAssertTrue(hueNear0,
                      "Fire palette with bass should produce hue near 0°, got \(cmd.hue)")
    }

    // MARK: - Preset Tests

    func test_preset_allPresetsValid() {
        for preset in SoundToLightPreset.presets {
            XCTAssertFalse(preset.name.isEmpty)
            XCTAssertTrue(SoundToLightModeType.allCases.contains(preset.modeType))
            XCTAssertTrue(Reactivity.allCases.contains(preset.reactivity))
            if preset.paletteIndex >= 0 {
                XCTAssertLessThan(preset.paletteIndex, ColorPalette.palettes.count)
            }
        }
    }

    func test_preset_createModeFromPreset() {
        for preset in SoundToLightPreset.presets {
            let palette: ColorPalette? = preset.paletteIndex >= 0
                ? ColorPalette.palettes[preset.paletteIndex] : nil
            let mode = preset.modeType.createMode(reactivity: preset.reactivity, palette: palette)
            XCTAssertEqual(mode.reactivity, preset.reactivity)
            XCTAssertFalse(mode.name.isEmpty)
        }
    }

    func test_createMode_withReactivityAndPalette() {
        let palette = ColorPalette(name: "Test", warmHue: 100, coolHue: 200)
        var mode = SoundToLightModeType.colorFlow.createMode(
            reactivity: .intense, palette: palette)

        XCTAssertEqual(mode.reactivity, .intense)

        // Verify palette is applied by checking output hue range
        var features = AudioFeatures.zero
        features.highEnergy = 0.9
        features.bassEnergy = 0.05
        features.overallEnergy = 0.5
        for _ in 0..<100 {
            _ = mode.process(features)
        }
        let cmd = mode.process(features)
        // With high energy dominant, hue should trend toward coolHue (200)
        XCTAssertGreaterThan(cmd.hue, 120, "Should trend toward cool hue 200, got \(cmd.hue)")
        XCTAssertLessThan(cmd.hue, 280, "Should be in range near 200, got \(cmd.hue)")
    }

    // MARK: - Pulse + Palette Tests

    func test_pulse_defaultHueIsAmber() {
        var mode = PulseMode()
        let cmd = mode.process(.zero)
        // No palette → warm/cool both default to 30° (amber)
        XCTAssertEqual(cmd.hue, 30, accuracy: 1,
                       "Default pulse hue should be warm amber ~30°")
    }

    func test_pulse_paletteChangesHue() {
        let neon = ColorPalette(name: "Neon", warmHue: 300, coolHue: 180)
        var mode = PulseMode()
        mode.warmHue = neon.warmHue
        mode.coolHue = neon.coolHue

        // At rest (no beat), pulse=0 → hue should be at coolHue
        let cmd = mode.process(.zero)
        XCTAssertEqual(cmd.hue, 180, accuracy: 5,
                       "At rest, pulse hue should be near coolHue (180)")
    }

    func test_pulse_beatHueSweepsFromWarmToCool() {
        let sunset = ColorPalette(name: "Sunset", warmHue: 0, coolHue: 320)
        var mode = PulseMode()
        mode.warmHue = sunset.warmHue
        mode.coolHue = sunset.coolHue

        // Trigger a beat
        var beat = AudioFeatures.zero
        beat.isBeat = true
        beat.beatIntensity = 1.0
        beat.noiseGateOpen = true
        let onBeat = mode.process(beat)

        // On beat: hue should be near warmHue (0/360)
        let warmDist = min(abs(onBeat.hue - 0), abs(onBeat.hue - 360))
        XCTAssertLessThan(warmDist, 30,
                          "On beat, hue should be near warmHue (0°), got \(onBeat.hue)")

        // Decay for many frames
        var cmd = LightCommand()
        for _ in 0..<200 {
            cmd = mode.process(.zero)
        }

        // After decay: hue drifts toward coolHue (320)
        XCTAssertGreaterThan(cmd.hue, 280,
                             "After decay, hue should drift toward coolHue (320°), got \(cmd.hue)")
    }

    func test_pulse_createdWithPalette() {
        let palette = ColorPalette(name: "Ocean", warmHue: 180, coolHue: 260)
        let mode = SoundToLightModeType.pulse.createMode(
            reactivity: .moderate, palette: palette)

        // Verify palette is applied — at rest hue should be near coolHue
        var mutableMode = mode
        let cmd = mutableMode.process(.zero)
        XCTAssertEqual(cmd.hue, 260, accuracy: 5,
                       "Pulse created with Ocean palette should use coolHue at rest")
    }
}
