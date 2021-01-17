//
//  NSBezierPathExtensions.swift
//  NeewerLite
//
//  Created by Xu Lian on 1/16/21.
//

import AppKit

extension NSBezierPath {

    var cgPath: CGPath {
        let path = CGMutablePath()
        let points = UnsafeMutablePointer<NSPoint>.allocate(capacity: 3)
        let elementCount = self.elementCount

        if elementCount > 0 {
            var didClosePath = true

            for i in 0 ..< self.elementCount {
                let type = self.element(at: i, associatedPoints: points)
                switch type {
                    case .moveTo:
                        path.move(to: points[0])
                    case .lineTo:
                        path.addLine(to: points[0])
                    case .curveTo:
                        path.addCurve(to: points[2], control1: points[0], control2: points[1])
                    case .closePath:
                        path.closeSubpath()
                        didClosePath = true
                    @unknown default:
                        break
                }
            }

            if !didClosePath { path.closeSubpath() }
        }

        points.deallocate()
        return path
    }
}


