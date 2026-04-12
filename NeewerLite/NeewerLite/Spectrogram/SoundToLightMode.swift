//
//  SoundToLightMode.swift
//  NeewerLite
//
//  Created on 2026-04-11.
//
//  Phase 2 of Sound-to-Light: mapping modes that convert AudioFeatures
//  into concrete light commands (HSI or CCT).

import Foundation

// MARK: - Light Command

/// A single frame's light output computed by a mapping mode.
struct LightCommand {
    /// Hue in degrees (0–360). Only used for HSI lights.
    var hue: Float = 0

    /// Saturation (0–1). Only used for HSI lights.
    var saturation: Float = 1.0

    /// Brightness (0–1). Used for all lights.
    var brightness: Float = 0.3

    /// Color temperature in "Neewer units" (32–85, i.e. 3200K–8500K ÷ 100).
    /// Only used for CCT lights.
    var cct: Float = 56

    /// Green-magenta tint (-50 to 50). Only used for CCT lights that support GM.
    var gm: Float = 0

    /// Whether this command targets HSI mode.
    var isHSI: Bool = true
}

// MARK: - Sound-to-Light Mode Protocol

/// A mapping mode that converts AudioFeatures into LightCommands.
///
/// Each mode is a stateful object — it can maintain internal state for
/// smooth transitions, decay envelopes, etc.
protocol SoundToLightMode {
    /// Human-readable name shown in the UI.
    var name: String { get }

    /// Whether this mode supports HSI lights.
    var supportsHSI: Bool { get }

    /// Whether this mode supports CCT-only lights.
    var supportsCCT: Bool { get }

    /// How responsive the mode is to audio changes.
    var reactivity: Reactivity { get set }

    /// Process one frame of audio features and return the desired light state.
    ///
    /// Called at ~46 Hz from the audio capture queue.
    /// - Parameter features: Current audio analysis results
    /// - Returns: The desired light command for this frame
    mutating func process(_ features: AudioFeatures) -> LightCommand

    /// Reset internal state (e.g., when mode is switched or audio stops).
    mutating func reset()
}

// MARK: - Pulse Mode

/// Beat-driven brightness pulsing.
/// Brightness spikes on beat, decays exponentially between beats.
/// Works on all lights (CCT + HSI).
struct PulseMode: SoundToLightMode {
    let name = "Pulse"
    let supportsHSI = true
    let supportsCCT = true
    var reactivity: Reactivity = .moderate

    /// Base brightness when no beat is active (0–1).
    var baseBrightness: Float = 0.15

    /// How much brightness to add on a beat (0–1).
    var beatImpact: Float = 0.85

    /// Exponential decay rate per frame. Higher = faster decay.
    /// At 46 Hz: 0.08 gives ~12 frames to half = ~0.26s decay.
    var decayRate: Float = 0.08

    /// Warm hue (at beat peak). Default: warm amber 30°.
    var warmHue: Float = 30

    /// Cool hue (at pulse floor). When equal to warmHue, hue stays static.
    var coolHue: Float = 30

    /// Base saturation for HSI mode.
    var baseSaturation: Float = 0.8

    /// Base CCT for CCT mode (warm).
    var baseCCT: Float = 32

    // Internal state
    private var currentPulse: Float = 0

    mutating func process(_ features: AudioFeatures) -> LightCommand {
        // On beat: spike to beat intensity, scaled by reactivity
        if features.isBeat {
            currentPulse = max(currentPulse, features.beatIntensity * reactivity.sensitivity)
        }

        // Exponential decay, scaled by reactivity
        let effectiveDecay = decayRate * reactivity.decayScale
        currentPulse *= (1.0 - effectiveDecay)

        // Brightness = floor + pulse
        let effectiveFloor = min(baseBrightness * reactivity.floorScale, 0.5)
        let brr = clamp01(effectiveFloor + currentPulse * beatImpact)

        // Hue sweeps from warmHue (beat peak) → coolHue (decay floor)
        let hue = hueInterpolate(warmHue, coolHue, t: 1.0 - currentPulse)

        var cmd = LightCommand()
        cmd.brightness = brr
        cmd.hue = normalizeHue(hue)
        cmd.saturation = baseSaturation
        cmd.cct = baseCCT
        cmd.gm = 0
        cmd.isHSI = true
        return cmd
    }

    mutating func reset() {
        currentPulse = 0
    }
}

// MARK: - Color Flow Mode

/// Frequency-driven hue mapping with energy-driven brightness.
/// Bass → warm colors (red/orange), Highs → cool colors (blue/violet).
/// HSI lights only.
struct ColorFlowMode: SoundToLightMode {
    let name = "Color Flow"
    let supportsHSI = true
    let supportsCCT = false
    var reactivity: Reactivity = .moderate

    /// Warm hue (bass-dominant). Default: red-orange (20°).
    var warmHue: Float = 20

    /// Cool hue (highs-dominant). Default: blue-violet (260°).
    var coolHue: Float = 260

    /// Brightness floor — never fully dark.
    var brightnessFloor: Float = 0.25

    /// How much energy modulates brightness.
    var brightnessRange: Float = 0.75

    /// Smoothing factor for hue transitions (0–1, higher = smoother).
    var hueSmoothing: Float = 0.85

    /// Smoothing factor for brightness transitions.
    var brrSmoothing: Float = 0.7

    // Internal state
    private var smoothedHue: Float = 140
    private var smoothedBrr: Float = 0.3

    mutating func process(_ features: AudioFeatures) -> LightCommand {
        let epsilon: Float = 0.001

        // Hue: interpolate between warm and cool based on frequency balance
        let bassWeight = features.bassEnergy + epsilon
        let highWeight = features.highEnergy + epsilon
        let coolRatio = highWeight / (bassWeight + highWeight)

        // Lerp hue (handle wrap-around via shortest-path interpolation)
        let targetHue = hueInterpolate(warmHue, coolHue, t: coolRatio)
        let effectiveSmoothing = reactivity.smoothing
        smoothedHue = hueInterpolate(smoothedHue, targetHue, t: 1.0 - effectiveSmoothing)

        // Saturation: higher with more spectral contrast
        let contrast = abs(features.bassEnergy - features.highEnergy)
        let sat = clamp01(0.6 + contrast * 0.4)

        // Brightness: energy-driven with floor, scaled by reactivity
        let effectiveFloor = min(brightnessFloor * reactivity.floorScale, 0.5)
        let targetBrr = effectiveFloor + features.overallEnergy * brightnessRange
        smoothedBrr = smoothedBrr * effectiveSmoothing + targetBrr * (1.0 - effectiveSmoothing)

        // Beat bump: small brightness kick on beats, scaled by reactivity
        var brr = smoothedBrr
        if features.isBeat {
            brr = clamp01(brr + features.beatIntensity * 0.15 * reactivity.sensitivity)
        }

        var cmd = LightCommand()
        cmd.hue = normalizeHue(smoothedHue)
        cmd.saturation = sat
        cmd.brightness = brr
        cmd.isHSI = true
        return cmd
    }

    mutating func reset() {
        smoothedHue = 140
        smoothedBrr = 0.3
    }
}

// MARK: - Bass Cannon Mode

/// Bass-focused mode for CCT-only and all lights.
/// Bass energy drives brightness; CCT shifts warm on bass hits, cool on quiet.
struct BassCannonMode: SoundToLightMode {
    let name = "Bass Cannon"
    let supportsHSI = true
    let supportsCCT = true
    var reactivity: Reactivity = .moderate

    /// Brightness floor.
    var brightnessFloor: Float = 0.15

    /// How much bass energy drives brightness.
    var brightnessRange: Float = 0.85

    /// Warm CCT on strong bass (Neewer units, 32 = 3200K).
    var warmCCT: Float = 32

    /// Cool CCT on quiet (Neewer units, 56 = 5600K).
    var coolCCT: Float = 56

    /// HSI warm hue (deep red/orange for bass hits).
    var bassHue: Float = 10

    /// HSI cool hue (neutral warm for quiet).
    var quietHue: Float = 40

    /// Smoothing for brightness.
    var brrSmoothing: Float = 0.6

    // Internal state
    private var smoothedBrr: Float = 0.15
    private var smoothedBass: Float = 0

    mutating func process(_ features: AudioFeatures) -> LightCommand {
        // Smooth bass energy, smoothing scaled by reactivity
        let effectiveSmoothing = reactivity.smoothing
        smoothedBass = smoothedBass * effectiveSmoothing + features.bassEnergy * (1.0 - effectiveSmoothing)

        // Brightness from bass, floor scaled by reactivity
        let effectiveFloor = min(brightnessFloor * reactivity.floorScale, 0.5)
        let targetBrr = effectiveFloor + smoothedBass * brightnessRange
        smoothedBrr = smoothedBrr * 0.5 + targetBrr * 0.5

        // Beat spike, scaled by reactivity
        var brr = smoothedBrr
        if features.isBeat {
            brr = clamp01(brr + features.beatIntensity * 0.3 * reactivity.sensitivity)
        }

        // CCT: warm on bass, cool on quiet
        let cct = warmCCT + (coolCCT - warmCCT) * (1.0 - smoothedBass)

        // HSI: hue shifts from deep red to warm orange
        let hue = bassHue + (quietHue - bassHue) * (1.0 - smoothedBass)

        var cmd = LightCommand()
        cmd.brightness = brr
        cmd.hue = hue
        cmd.saturation = clamp01(0.7 + smoothedBass * 0.3)
        cmd.cct = cct
        cmd.gm = 0
        cmd.isHSI = true
        return cmd
    }

    mutating func reset() {
        smoothedBrr = brightnessFloor
        smoothedBass = 0
    }
}

// MARK: - Strobe Mode

/// Onset-driven strobe: flashes to full brightness on spectral flux spikes,
/// then decays rapidly. Rate-limited to max ~3 Hz for safety.
/// Works on all lights (HSI + CCT). Not palette-aware.
struct StrobeMode: SoundToLightMode {
    let name = "Strobe"
    let supportsHSI = true
    let supportsCCT = true
    var reactivity: Reactivity = .moderate

    /// Brightness floor between flashes.
    var brightnessFloor: Float = 0.05

    /// Decay rate per frame. At 46 Hz, 0.15 gives ~6 frames to half ≈ 0.13s.
    var decayRate: Float = 0.15

    /// Minimum interval between flashes in seconds (~3 Hz safety limit).
    var minFlashInterval: Float = 0.33

    /// Hue for the flash (pure white strobe = high brightness, low saturation).
    var flashHue: Float = 0

    /// Saturation (low = whiter strobe, high = colored strobe).
    var flashSaturation: Float = 0.1

    // Internal state
    private var currentFlash: Float = 0
    private var timeSinceLastFlash: Float = 1.0 // start ready to flash
    private let frameInterval: Float = 1.0 / 46.0 // ~22ms per frame

    mutating func process(_ features: AudioFeatures) -> LightCommand {
        timeSinceLastFlash += frameInterval

        // Trigger flash on beat if rate limit allows
        let effectiveSensitivity = reactivity.sensitivity
        if features.isBeat && timeSinceLastFlash >= minFlashInterval {
            currentFlash = min(features.beatIntensity * effectiveSensitivity, 1.0)
            timeSinceLastFlash = 0
        }

        // Fast exponential decay
        let effectiveDecay = decayRate * reactivity.decayScale
        currentFlash *= (1.0 - effectiveDecay)

        // Brightness
        let effectiveFloor = min(brightnessFloor * reactivity.floorScale, 0.3)
        let brr = clamp01(effectiveFloor + currentFlash * (1.0 - effectiveFloor))

        var cmd = LightCommand()
        cmd.brightness = brr
        cmd.hue = flashHue
        cmd.saturation = flashSaturation
        cmd.cct = 56 // neutral daylight
        cmd.gm = 0
        cmd.isHSI = true
        return cmd
    }

    mutating func reset() {
        currentFlash = 0
        timeSinceLastFlash = 1.0
    }
}

// MARK: - Aurora Mode

/// Ambient mode: slow color drift driven by spectral centroid,
/// brightness gently breathes with bass. Very smooth, low reactivity.
/// HSI lights only. Palette-aware.
struct AuroraMode: SoundToLightMode {
    let name = "Aurora"
    let supportsHSI = true
    let supportsCCT = false
    var reactivity: Reactivity = .moderate

    // Aurora ignores palette — it drifts across the full 360° hue wheel.
    var warmHue: Float = 0    // unused, kept for protocol conformance
    var coolHue: Float = 360  // unused, kept for protocol conformance

    /// Brightness floor — aurora never goes dark.
    var brightnessFloor: Float = 0.35

    /// How much bass breathing affects brightness.
    var breathRange: Float = 0.3

    /// Base drift speed in degrees/second — autonomous hue rotation.
    var baseDriftSpeed: Float = 3.0

    /// Hue smoothing — glacial drift. ~8.7s to target at 46 Hz.
    var hueSmoothing: Float = 0.9975

    /// Brightness smoothing — slow breathing. ~4.3s to target.
    var brrSmoothing: Float = 0.995

    /// Saturation smoothing — gentle transitions. ~2.2s to target.
    var satSmoothing: Float = 0.99

    // Internal state
    private var currentHue: Float = 220
    private var smoothedBrr: Float = 0.45
    private var smoothedSat: Float = 0.65
    private let frameInterval: Float = 1.0 / 46.0

    mutating func process(_ features: AudioFeatures) -> LightCommand {
        let epsilon: Float = 0.001

        // Spectral centroid biases drift direction: bass→slower/reverse, treble→faster
        let bassWeight = features.bassEnergy + epsilon
        let highWeight = features.highEnergy + epsilon
        let centroid = highWeight / (bassWeight + highWeight)  // 0=bass, 1=treble

        // Drift direction: centroid > 0.5 → forward, < 0.5 → backward
        // Audio energy speeds up the drift; reactivity scales how much
        let directionBias = (centroid - 0.5) * 2.0  // -1 to +1
        let energyBoost = 1.0 + features.overallEnergy * reactivity.sensitivity
        let hueStep = baseDriftSpeed * (1.0 + directionBias * 0.5) * energyBoost * frameInterval

        // Advance hue continuously around the wheel
        currentHue = normalizeHue(currentHue + hueStep)

        // Brightness: gentle breathing with bass, reactivity scales breath depth
        let effectiveBreath = breathRange * reactivity.sensitivity
        let breathTarget = brightnessFloor + features.bassEnergy * effectiveBreath
        smoothedBrr = smoothedBrr * brrSmoothing + breathTarget * (1.0 - brrSmoothing)

        // Saturation: smoothed, gently modulated by spectral contrast
        let contrast = abs(features.bassEnergy - features.highEnergy)
        let targetSat = clamp01(0.6 + contrast * 0.3 + features.overallEnergy * 0.1)
        smoothedSat = smoothedSat * satSmoothing + targetSat * (1.0 - satSmoothing)

        var cmd = LightCommand()
        cmd.hue = currentHue
        cmd.saturation = smoothedSat
        cmd.brightness = clamp01(smoothedBrr)
        cmd.isHSI = true
        return cmd
    }

    mutating func reset() {
        currentHue = 220
        smoothedBrr = brightnessFloor
        smoothedSat = 0.65
    }
}

// MARK: - BLE Smart Throttle

/// Determines whether a new light command should actually be sent over BLE,
/// based on perceptual thresholds and minimum send interval.
///
/// Thread-safety: call from the same queue as the audio processing.
class BLESmartThrottle {
    /// Minimum brightness change to trigger a send (0–1 scale).
    var brightnessThreshold: Float = 0.03

    /// Minimum hue change in degrees to trigger a send.
    var hueThreshold: Float = 5.0

    /// Minimum saturation change to trigger a send.
    var satThreshold: Float = 0.05

    /// Minimum CCT change (Neewer units) to trigger a send.
    var cctThreshold: Float = 2.0

    /// Maximum time between sends (heartbeat) in seconds.
    var heartbeatInterval: TimeInterval = 0.2

    /// Minimum time between sends in seconds (rate limit).
    /// ~67ms = ~15 Hz max.
    var minSendInterval: TimeInterval = 0.067

    // Internal state per device (keyed by device identifier)
    private var deviceStates: [String: DeviceThrottleState] = [:]

    struct DeviceThrottleState {
        var lastSentCommand: LightCommand
        var lastSendTime: CFAbsoluteTime = 0
    }

    /// Check if this command should be sent to the device.
    /// Returns true if the change exceeds perceptual thresholds or heartbeat expired.
    func shouldSend(command: LightCommand, deviceId: String) -> Bool {
        let now = CFAbsoluteTimeGetCurrent()

        guard let state = deviceStates[deviceId] else {
            // First command for this device — always send
            deviceStates[deviceId] = DeviceThrottleState(
                lastSentCommand: command, lastSendTime: now)
            return true
        }

        // Rate limit: don't send faster than minSendInterval
        let elapsed = now - state.lastSendTime
        if elapsed < minSendInterval {
            return false
        }

        // Heartbeat: always send if too long since last send
        if elapsed >= heartbeatInterval {
            return true
        }

        // Perceptual threshold check
        let last = state.lastSentCommand
        let brrChanged = abs(command.brightness - last.brightness) > brightnessThreshold
        let hueChanged = hueDistance(command.hue, last.hue) > hueThreshold
        let satChanged = abs(command.saturation - last.saturation) > satThreshold
        let cctChanged = abs(command.cct - last.cct) > cctThreshold

        return brrChanged || hueChanged || satChanged || cctChanged
    }

    /// Record that a command was sent to the device.
    func didSend(command: LightCommand, deviceId: String) {
        let now = CFAbsoluteTimeGetCurrent()
        deviceStates[deviceId] = DeviceThrottleState(
            lastSentCommand: command, lastSendTime: now)
    }

    /// Reset state for all devices.
    func reset() {
        deviceStates.removeAll()
    }

    /// Reset state for a specific device.
    func reset(deviceId: String) {
        deviceStates.removeValue(forKey: deviceId)
    }

    /// Shortest angular distance between two hue values (0–360).
    private func hueDistance(_ a: Float, _ b: Float) -> Float {
        let diff = abs(a - b)
        return min(diff, 360 - diff)
    }
}

// MARK: - Mode Registry

/// Available sound-to-light modes.
enum SoundToLightModeType: String, CaseIterable {
    case pulse = "Pulse"
    case colorFlow = "Color Flow"
    case bassCannon = "Bass Cannon"
    case strobe = "Strobe"
    case aurora = "Aurora"

    func createMode() -> SoundToLightMode {
        return createMode(reactivity: .moderate)
    }

    func createMode(reactivity: Reactivity, palette: ColorPalette? = nil) -> SoundToLightMode {
        switch self {
        case .pulse:
            var mode = PulseMode()
            mode.reactivity = reactivity
            if let p = palette {
                mode.warmHue = p.warmHue
                mode.coolHue = p.coolHue
            }
            return mode
        case .colorFlow:
            var mode = ColorFlowMode()
            mode.reactivity = reactivity
            if let p = palette {
                mode.warmHue = p.warmHue
                mode.coolHue = p.coolHue
            }
            return mode
        case .bassCannon:
            var mode = BassCannonMode()
            mode.reactivity = reactivity
            return mode
        case .strobe:
            var mode = StrobeMode()
            mode.reactivity = reactivity
            return mode
        case .aurora:
            var mode = AuroraMode()
            mode.reactivity = reactivity
            return mode
        }
    }
}

// MARK: - Reactivity

/// Controls how responsive the light is to audio changes.
enum Reactivity: Int, CaseIterable {
    case subtle = 0
    case moderate = 1
    case intense = 2
    case extreme = 3

    var displayName: String {
        switch self {
        case .subtle: return "Subtle"
        case .moderate: return "Moderate"
        case .intense: return "Intense"
        case .extreme: return "Extreme"
        }
    }

    /// Scale factor for beat impact / onset sensitivity.
    var sensitivity: Float {
        switch self {
        case .subtle: return 0.3
        case .moderate: return 1.0
        case .intense: return 1.5
        case .extreme: return 2.0
        }
    }

    /// Scale factor for decay speed (higher = faster decay = punchier).
    var decayScale: Float {
        switch self {
        case .subtle: return 0.5
        case .moderate: return 1.0
        case .intense: return 1.5
        case .extreme: return 2.0
        }
    }

    /// Scale factor for brightness floor (higher = brighter minimum).
    var floorScale: Float {
        switch self {
        case .subtle: return 2.0
        case .moderate: return 1.0
        case .intense: return 0.6
        case .extreme: return 0.3
        }
    }

    /// Smoothing factor (higher = smoother transitions).
    var smoothing: Float {
        switch self {
        case .subtle: return 0.95
        case .moderate: return 0.85
        case .intense: return 0.7
        case .extreme: return 0.5
        }
    }
}

// MARK: - Color Palette

/// A named color palette defining warm/cool hue endpoints for Color Flow mode.
struct ColorPalette {
    let name: String
    /// Warm hue endpoint (bass-heavy, 0–360°).
    let warmHue: Float
    /// Cool hue endpoint (treble-heavy, 0–360°).
    let coolHue: Float

    static let palettes: [ColorPalette] = [
        ColorPalette(name: "Sunset", warmHue: 0, coolHue: 320),
        ColorPalette(name: "Ocean", warmHue: 180, coolHue: 260),
        ColorPalette(name: "Neon", warmHue: 300, coolHue: 180),
        ColorPalette(name: "Fire", warmHue: 0, coolHue: 50),
        ColorPalette(name: "Forest", warmHue: 80, coolHue: 160),
    ]
}

// MARK: - Preset

/// A named combination of mode + reactivity + palette for quick setup.
struct SoundToLightPreset {
    let name: String
    let modeType: SoundToLightModeType
    let reactivity: Reactivity
    /// Index into ColorPalette.palettes (-1 = use mode default).
    let paletteIndex: Int

    static let presets: [SoundToLightPreset] = [
        SoundToLightPreset(name: "DJ Booth", modeType: .pulse, reactivity: .intense, paletteIndex: 2),
        SoundToLightPreset(name: "Film Score", modeType: .colorFlow, reactivity: .subtle, paletteIndex: 0),
        SoundToLightPreset(name: "Rock Concert", modeType: .bassCannon, reactivity: .extreme, paletteIndex: 3),
        SoundToLightPreset(name: "Worship", modeType: .colorFlow, reactivity: .moderate, paletteIndex: 1),
        SoundToLightPreset(name: "Party", modeType: .colorFlow, reactivity: .intense, paletteIndex: 2),
        SoundToLightPreset(name: "Podcast", modeType: .pulse, reactivity: .subtle, paletteIndex: -1),
    ]
}

// MARK: - Free Functions

/// Clamp a value to 0–1.
private func clamp01(_ v: Float) -> Float {
    return max(0, min(1, v.isFinite ? v : 0))
}

/// Normalize hue to 0–360.
private func normalizeHue(_ h: Float) -> Float {
    var hue = h
    while hue < 0 { hue += 360 }
    while hue >= 360 { hue -= 360 }
    return hue
}

/// Shortest-path hue interpolation on the 0–360 circle.
private func hueInterpolate(_ from: Float, _ to: Float, t: Float) -> Float {
    var diff = to - from
    if diff > 180 { diff -= 360 }
    if diff < -180 { diff += 360 }
    return normalizeHue(from + diff * t)
}
