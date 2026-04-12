//
//  AudioVisualizerPlugin.swift
//  NeewerLite
//
//  Created by Xu Lian on 4/11/26.
//

import Cocoa

/// Protocol that all audio visualization plugins must conform to.
/// Each plugin provides a named visualization that receives audio frequency data.
protocol AudioVisualizerPlugin: AnyObject {
    /// Display name shown in the visualization picker.
    static var displayName: String { get }

    /// The NSView used for rendering. Owned by the plugin.
    var visualizerView: NSView { get }

    /// Called with frequency bin data (typically 60 floats) from the audio engine.
    func updateFrequency(_ data: [Float])

    /// Called with the spectrogram waterfall image.
    func updateSpectrogramImage(_ image: CGImage)

    /// Volume level (0–1, normalized from amplitude).
    var volume: Float { get set }

    /// Whether to mirror the visualization (e.g., bars mirrored left/right).
    var mirror: Bool { get set }

    /// Reset the visualization to its initial state.
    func clear()

    /// Whether this plugin needs the spectrogram CGImage. When false, the
    /// expensive vImage lookup + CGImage generation is skipped entirely.
    var needsSpectrogramImage: Bool { get }
}

/// Default implementations for optional capabilities.
extension AudioVisualizerPlugin {
    func updateSpectrogramImage(_ image: CGImage) {}
    var needsSpectrogramImage: Bool { false }
}

// MARK: - Shared Frequency Processing

/// Applies peak normalization, power-curve compression, and smoothstep edge
/// tapering to frequency data. Returns values in 0…1 range.
///
/// - Parameters:
///   - data: Raw frequency magnitudes (non-negative floats).
///   - referencePeak: External peak value for normalization. When provided,
///     data is normalized against this instead of the frame’s own maximum.
///     Callers should maintain a decaying peak tracker for smooth results.
///   - exponent: Power-curve exponent (< 1 compresses loud peaks). Default 0.6.
///   - taperFraction: Fraction of bins to taper at each edge. Default 0.1 (10%).
/// - Returns: Array of same length with values in 0…1.
func normalizedFrequencyData(_ data: [Float],
                             referencePeak: Float? = nil,
                             exponent: Float = 0.6,
                             taperFraction: Float = 0.1) -> [Float] {
    let count = data.count
    guard count > 0 else { return [] }

    let peak = referencePeak ?? (data.max() ?? 0)
    let safePeak = max(peak, 1e-4)
    let taperBins = max(3, Int(Float(count) * taperFraction))

    var result = [Float](repeating: 0, count: count)
    for i in 0..<count {
        let raw = data[i]
        guard raw.isFinite else { continue }  // skip NaN / Inf
        let normalized = max(0, raw) / safePeak
        let compressed = powf(normalized, exponent)

        var taper: Float = 1.0
        if i < taperBins {
            let t = Float(i) / Float(taperBins)
            taper = t * t * (3.0 - 2.0 * t)
        } else if i > count - 1 - taperBins {
            let t = Float(count - 1 - i) / Float(taperBins)
            taper = t * t * (3.0 - 2.0 * t)
        }

        result[i] = compressed * taper
    }
    return result
}

// MARK: - Bundle-based plugin support

/// Base class for visualization plugins loaded from external `.bundle` files.
/// Bundle principal classes should subclass this. The @objc attribute ensures
/// the class can be loaded across module boundaries via NSBundle.
@objc(AudioVisualizerPluginBase)
open class AudioVisualizerPluginBase: NSObject, AudioVisualizerPlugin {
    open class var displayName: String { "Unknown" }
    open var visualizerView: NSView { fatalError("Subclass must override visualizerView") }
    open func updateFrequency(_ data: [Float]) {}
    open func updateSpectrogramImage(_ image: CGImage) {}
    open var volume: Float = 1.0
    open var mirror: Bool = false
    open func clear() {}
    open var needsSpectrogramImage: Bool { false }

    public required init(frame: NSRect) {
        super.init()
    }
}
