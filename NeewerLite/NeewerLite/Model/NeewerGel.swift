//
//  NeewerGel.swift
//  NeewerLite
//
//  Created by Xu Lian on 4/10/26.
//

import Foundation
import AppKit

// MARK: - Model

/// A single gel (colour filter) preset.
public struct NeewerGel: Codable, Identifiable, Equatable {
    public let id: String               // stable key used in Studio Layout JSON
    public let name: String
    public let hue: Double              // 0–360°
    public let saturation: Double       // 0–100
    public let transmissionPercent: Double // physical light-loss; 0–100 (100 = no loss)
    public let mireds: Double           // colour-temperature shift in mireds (positive = warm)
    public let category: GelCategory
    public let manufacturer: String     // e.g. "Lee", "Rosco", ""
    public let code: String             // gel reference code, e.g. "201", "3407"

    public enum GelCategory: String, Codable, CaseIterable {
        case colorCorrection = "CC"
        case creative = "Creative"
        case diffusion = "Diffusion"
    }

    /// NSColor representation (hue/saturation at full brightness for the swatch).
    public var swatchColor: NSColor {
        NSColor(calibratedHue: CGFloat(hue) / 360.0,
                saturation: CGFloat(saturation) / 100.0,
                brightness: 1.0,
                alpha: 1.0)
    }

    // MARK: Stacking

    /// Returns a new virtual gel that is the physical stack of `self` on top of `other`,
    /// using subtractive (multiplicative) colour mixing.
    ///
    /// **RGB multiplication:**
    /// Each channel is treated as a transmission factor in [0,1].
    /// Stacking multiplies them: R_result = R₁ × R₂.
    ///
    /// **Mired addition:**
    /// Colour-temperature shifts add linearly in the mired domain
    /// (unlike Kelvin which is non-linear).
    ///
    /// **Transmission:**
    /// Y_total = Y₁ × Y₂ (light loss compounds).
    public func stacked(with other: NeewerGel) -> StackedGel {
        // Convert both gels to unit-scale RGB
        let rgb1 = hsiToRGB(hue: hue, saturation: saturation / 100.0)
        let rgb2 = hsiToRGB(hue: other.hue, saturation: other.saturation / 100.0)

        // Multiplicative (subtractive) mix
        let rr = rgb1.r * rgb2.r
        let rg = rgb1.g * rgb2.g
        let rb = rgb1.b * rgb2.b

        let (resultHue, resultSat) = rgbToHS(r: rr, g: rg, b: rb)

        let resultMireds = mireds + other.mireds
        let resultTransmission = (transmissionPercent / 100.0) * (other.transmissionPercent / 100.0) * 100.0

        return StackedGel(
            hue: resultHue,
            saturation: resultSat,
            transmissionPercent: resultTransmission,
            mireds: resultMireds,
            sourceGels: [self, other]
        )
    }
}

// MARK: - Stacked Result

/// The computed result of applying multiple gels to a single fixture.
public struct StackedGel {
    public let hue: Double              // 0–360°
    public let saturation: Double       // 0–100
    public let transmissionPercent: Double
    public let mireds: Double
    public let sourceGels: [NeewerGel]

    /// 0–1 factor by which the fixture's maximum brightness should be scaled
    /// to account for physical light loss from all stacked gels.
    public var brightnessScale: Double {
        (transmissionPercent / 100.0).clamped(to: 0...1)
    }

    /// Effective output brightness given a base brightness (0–100).
    public func effectiveBrightness(base: Double) -> Double {
        (base * brightnessScale).clamped(to: 0...100)
    }

    public var swatchColor: NSColor {
        NSColor(calibratedHue: CGFloat(hue) / 360.0,
                saturation: CGFloat(saturation) / 100.0,
                brightness: 1.0,
                alpha: 1.0)
    }
}

// MARK: - Library

/// Loads and caches gels from the light database (`lights.json`).
///
/// Look-up order:
///  1. `ContentManager.shared` (covers both the built-in bundle and the downloaded DB)
///  2. `<app bundle>/Resources/gels.json` (legacy fallback, no longer shipped)
public final class GelLibrary {

    public static let shared = GelLibrary()

    private(set) public var all: [NeewerGel] = []

    private init() {
        all = GelLibrary.load()
    }

    /// Reload gels from the current database (called by ContentManager after DB loads).
    public func reload() {
        let fresh = GelLibrary.load()
        if !fresh.isEmpty {
            all = fresh
        }
    }

    /// Returns gels filtered to a specific category, sorted by name.
    public func gels(in category: NeewerGel.GelCategory) -> [NeewerGel] {
        all.filter { $0.category == category }.sorted { $0.name < $1.name }
    }

    /// Returns gels matching a manufacturer+code pair (for exact preset look-up).
    public func gel(manufacturer: String, code: String) -> NeewerGel? {
        all.first { $0.manufacturer == manufacturer && $0.code == code }
    }

    /// Returns the gel with the given stable `id`.
    public func gel(id: String) -> NeewerGel? {
        all.first { $0.id == id }
    }

    // MARK: Loading

    static func load() -> [NeewerGel] {
        // 1. Read from the ContentManager database (downloaded or bundled lights.json)
        let fromDB = ContentManager.shared.fetchGels()
        if !fromDB.isEmpty {
            return fromDB
        }
        // 2. Legacy fallback: standalone gels.json in app bundle (no longer shipped)
        if let bundleURL = Bundle.main.url(forResource: "gels", withExtension: "json") {
            if let gels = decode(from: bundleURL) {
                return gels
            }
        }
        return []
    }

    private static func decode(from url: URL) -> [NeewerGel]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([NeewerGel].self, from: data)
    }
}

// MARK: - Private colour math helpers

/// Convert HSI (hue 0–360°, saturation 0–1) to linear RGB [0,1].
/// Uses a simplified HSB→RGB conversion at full brightness.
func hsiToRGB(hue: Double, saturation: Double) -> (r: Double, g: Double, b: Double) {
    let h = hue.truncatingRemainder(dividingBy: 360.0)
    let s = saturation.clamped(to: 0...1)
    let c = s
    let x = c * (1.0 - abs((h / 60.0).truncatingRemainder(dividingBy: 2.0) - 1.0))
    let m = 1.0 - c   // offset so unsaturated colour = white (1,1,1), not black
    let (r1, g1, b1): (Double, Double, Double)
    switch h {
    case 0..<60:   (r1, g1, b1) = (c,  x,  0)
    case 60..<120: (r1, g1, b1) = (x,  c,  0)
    case 120..<180:(r1, g1, b1) = (0,  c,  x)
    case 180..<240:(r1, g1, b1) = (0,  x,  c)
    case 240..<300:(r1, g1, b1) = (x,  0,  c)
    default:       (r1, g1, b1) = (c,  0,  x)
    }
    return (r1 + m, g1 + m, b1 + m)
}

/// Convert linear RGB [0,1] back to hue (0–360°) and saturation (0–1).
func rgbToHS(r: Double, g: Double, b: Double) -> (hue: Double, saturation: Double) {
    let maxC = max(r, g, b)
    let minC = min(r, g, b)
    let delta = maxC - minC

    var hue: Double = 0
    if delta > 0 {
        if maxC == r {
            hue = 60.0 * (((g - b) / delta).truncatingRemainder(dividingBy: 6.0))
        } else if maxC == g {
            hue = 60.0 * (((b - r) / delta) + 2.0)
        } else {
            hue = 60.0 * (((r - g) / delta) + 4.0)
        }
    }
    if hue < 0 { hue += 360.0 }

    let saturation = maxC > 0 ? delta / maxC : 0.0
    return (hue, saturation)
}


