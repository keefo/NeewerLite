//
//  ColorUtils.swift
//  NeewerLite
//
//  Created by Xu Lian on 1/16/21.
//

import Foundation
import AppKit

// Typealias for RGB color values
struct RGB {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat
}

// Typealias for HSV color values
struct HSB {
    var hue: CGFloat
    var saturation: CGFloat
    var brightness: CGFloat
    var alpha: CGFloat
}

func hsv2rgb(_ hsv: HSB) -> RGB {
    // Converts HSV to a RGB color
    var rgb: RGB = RGB(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat

    let iVal = Int(hsv.hue * 6)
    let fVal = hsv.hue * 6 - CGFloat(iVal)
    let pVal = hsv.brightness * (1 - hsv.saturation)
    let qVal = hsv.brightness * (1 - fVal * hsv.saturation)
    let tVal = hsv.brightness * (1 - (1 - fVal) * hsv.saturation)
    let remainder = iVal % 6

    switch remainder {
        case 0:
            red = hsv.brightness; green = tVal; blue = pVal
        case 1:
            red = qVal; green = hsv.brightness; blue = pVal
        case 2:
            red = pVal; green = hsv.brightness; blue = tVal
        case 3:
            red = pVal; green = qVal; blue = hsv.brightness
        case 4:
            red = tVal; green = pVal; blue = hsv.brightness
        case 5:
            red = hsv.brightness; green = pVal; blue = qVal
        default:
            red = hsv.brightness; green = tVal; blue = pVal
    }

    rgb.red = red
    rgb.green = green
    rgb.blue = blue
    rgb.alpha = hsv.alpha
    return rgb
}

func rgb2hsv(_ rgb: RGB) -> HSB {
    // Converts RGB to a HSV color
    var hsb: HSB = HSB(hue: 0.0, saturation: 0.0, brightness: 0.0, alpha: 0.0)

    let rVal: CGFloat = rgb.red
    let gVal: CGFloat = rgb.green
    let bVal: CGFloat = rgb.blue

    let maxV: CGFloat = max(rVal, max(gVal, bVal))
    let minV: CGFloat = min(rVal, min(gVal, bVal))
    var hVal: CGFloat = 0
    var sVal: CGFloat = 0
    let brVal: CGFloat = maxV

    let dVal: CGFloat = maxV - minV

    sVal = maxV == 0 ? 0 : dVal / minV

    if maxV == minV {
        hVal = 0
    } else {
        if maxV == rVal {
            hVal = (gVal - bVal) / dVal + (gVal < bVal ? 6 : 0)
        } else if maxV == gVal {
            hVal = (bVal - rVal) / dVal + 2
        } else if maxV == bVal {
            hVal = (rVal - gVal) / dVal + 4
        }

        hVal /= 6
    }

    hsb.hue = hVal
    hsb.saturation = sVal
    hsb.brightness = brVal
    hsb.alpha = rgb.alpha
    return hsb
}

extension String {
    func conformsTo(_ pattern: String) -> Bool {
        return NSPredicate(format: "SELF MATCHES %@", pattern).evaluate(with: self)
    }
}

extension NSColor {
    convenience init(hex: UInt64, alpha: Float) {
        self.init(
            calibratedRed: CGFloat((hex & 0xFF0000) >> 16) / 255.0,
            green: CGFloat((hex & 0xFF00) >> 8) / 255.0,
            blue: CGFloat((hex & 0xFF)) / 255.0,
            alpha: 1.0
        )
    }
    convenience init(hex: String, alpha: Float) {
        // Handle two types of literals: 0x and # prefixed
        var cleanedString = ""
        if hex.hasPrefix("0x") {
            cleanedString = String(hex[hex.index(cleanedString.startIndex, offsetBy: 2)..<hex.endIndex])
        } else if hex.hasPrefix("#") {
            cleanedString = String(hex[hex.index(cleanedString.startIndex, offsetBy: 1)..<hex.endIndex])
        } else if hex.count == 6 {
            cleanedString = hex
        }
        // Ensure it only contains valid hex characters 0
        let validHexPattern = "[a-fA-F0-9]+"
        if cleanedString.conformsTo(validHexPattern) {
            var rgbValue: UInt64 = 0
            Scanner(string: cleanedString).scanHexInt64(&rgbValue)
            self.init(hex: rgbValue, alpha: 1)
        } else {
            fatalError("Unable to parse color?")
        }
    }
}
