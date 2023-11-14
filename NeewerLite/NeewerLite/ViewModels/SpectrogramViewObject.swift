//
//  SpectrogramViewObject.swift
//  NeewerLite
//
//  Created by Xu Lian on 11/22/22.
//

import Foundation
import Accelerate
import Cocoa

class SpectrogramViewObject {
    var lastTime: CFAbsoluteTime = 0
    // var lastNHUE = [Float](repeating: 0, count: 3)
    // var last_n_BRR = [Float](repeating: 0, count: 8)
    // var hueBase: Float = 0.0
    var hue: Float = 1.0
    var brr: Float = 1.0
    var sat: Float = 1.0
    var amplitude: Float = 1.0
    var gain: Float = 0.05

    func updateFrequency(frequencyData: [Float]) {
//        // Ensure there's data to work with
//        guard !frequencyData.isEmpty else {
//            return 0.0 // Return a default value (e.g., 0 for red) if no data
//        }
//
//        // Find the dominant frequency (e.g., highest amplitude)
//        guard let dominantFrequencyIndex = frequencyData.indices.max(by: { frequencyData[$0] < frequencyData[$1] }) else {
//            return 0.0 // Default hue
//        }
//
//        // Normalize the dominant frequency index to a value between 0 and 1
//        let normalizedIndex = Float(dominantFrequencyIndex) / Float(frequencyData.count)
//
//        // Convert the normalized index to a hue value (0 to 360 degrees)
//        let hue = normalizedIndex * 360.0
        lastTime = CFAbsoluteTimeGetCurrent()

        guard !frequencyData.isEmpty else {
            return// Default hue for no data
        }

        // Calculate total energy to use for normalization
//        let totalEnergy = frequencyData.reduce(0, +)
//        guard totalEnergy > 0 else {
//            self.hue = 0.0
//            return
//        }
//
//        // Calculate weighted sum of hues
//        let weightedHueSum: Float = frequencyData.enumerated().reduce(0.0) { (sum, arg) in
//            let (index, value) = arg
//            let normalizedIndex = Float(index) / Float(frequencyData.count)
//            let hue = normalizedIndex * 360.0 // Map to 0-360 degrees
//            return sum + hue * (value / totalEnergy)
//        }
//
//        self.hue = weightedHueSum

        // Calculate a weighted average frequency
        let total = frequencyData.reduce(0, +)
        if total <= 0 {
            return
        }
        let weightedIndexesSum: Float = frequencyData.enumerated().reduce(0.0) { (sum, arg) in
            let (index, amp) = arg
            return sum + Float(index) * amp
        }
        let weightedAverageIndex = weightedIndexesSum / total

        // Normalize the weighted average index to a value between 0 and 1
        let normalizedIndex = weightedAverageIndex / Float(frequencyData.count)

        // Convert the normalized index to a hue value (0 to 360 degrees)
        self.hue = Float(normalizedIndex * 360.0)
    }

    public func updateAmplitude(amplitude: Float) {
        self.amplitude = amplitude

        // Protect against logarithm of zero or negative numbers
        let safeAmplitude = max(0.01, amplitude)

        // Apply a logarithmic scale
        let logAmplitude = log10(safeAmplitude)

        // Normalize the logarithmic value to a range of 0.0 to 1.0
        // Adjust the scale factor (1000.0 in this example) based on your amplitude range
        let normalizedBrightness = min(logAmplitude / log10(1000.0), 1.0)

        self.brr = max(0.0, min(normalizedBrightness, 1.0))
        // self.brr = 1.0
    }

//    public func update(time: CFAbsoluteTime, frequency: Float) {
//        self.lastTime = time
//        self.lastNHUE.removeFirst()
//        self.lastNHUE.append(frequency)
//    }

//    var hue: Float {
//        var hue = sqrt(vDSP.meanSquare(lastNHUE)) * 2.0 / 128.0 + hueBase
//        if hue > 1.0 {
//            hue -= 1.0
//        }
//        return hue
//    }
}
