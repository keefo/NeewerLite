//
//  SpectrogramViewObject.swift
//  NeewerLite
//
//  Created by Xu Lian on 11/22/22.
//

import Foundation
import Accelerate

class SpectrogramViewObject {
    var lastTime: CFAbsoluteTime = 0
    var lastNHUE = [Float](repeating: 0, count: 3)
    // var last_n_BRR = [Float](repeating: 0, count: 8)
    var hueBase: Float = 0.0

    public func update(time: CFAbsoluteTime, frequency: Float) {
        self.lastTime = time
        self.lastNHUE.removeFirst()
        self.lastNHUE.append(frequency)
    }

    var hue: Float {
        var hue = sqrt(vDSP.meanSquare(lastNHUE)) * 2.0 / 128.0 + hueBase
        if hue > 1.0 {
            hue -= 1.0
        }
        return hue
    }
}
