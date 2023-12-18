//
//  AudioSpectrogramView.swift
//  NeewerLite
//
//  Created by Xu Lian on 1/5/21.
//

import Cocoa
import CoreGraphics
import QuartzCore
import AudioToolbox

extension CALayer {
    func getBitmapImage() -> NSImage {

        let btmpImgRep =
        NSBitmapImageRep(bitmapDataPlanes: nil,
                         pixelsWide: Int(self.frame.width),
                         pixelsHigh: Int(self.frame.height),
                         bitsPerSample: 8, samplesPerPixel: 4,
                         hasAlpha: true, isPlanar: false,
                         colorSpaceName: NSColorSpaceName.deviceRGB,
                         bytesPerRow: 0, bitsPerPixel: 32)

        let ctx = NSGraphicsContext(bitmapImageRep: btmpImgRep!)
        let cgContext = ctx!.cgContext

        self.render(in: cgContext)

        let cgImage = cgContext.makeImage()

        let nsimage = NSImage(cgImage: cgImage!, size: CGSize(width: self.frame.width, height: self.frame.height))

        return nsimage
    }
}

@available(macOS 13.0, *)
class AudioSpectrogramView: NSView {

    var bars: [CALayer] = []
    var barsLeft: [CALayer] = []
    let num: Int = AudioSpectrogram.filterBankCount
    var width: CGFloat = 10.0
    var height: CGFloat = 128.0
    var volume: CGFloat = 1.0
    var reset: Bool = true
    var bgLayer: CAGradientLayer = CAGradientLayer()
    var mirror: Bool = false {
        didSet {
            setupBars()
        }
    }

    override func awakeFromNib() {
        self.wantsLayer = true

        self.layer?.backgroundColor = NSColor.black.cgColor
        self.layer?.cornerRadius = 14.0

        var xOffset = Int(self.bounds.width / 2.0)
        for _ in 0..<num {
            let bar = CALayer()
            bar.frame = CGRect(x: xOffset, y: 0, width: Int(width), height: 10)
            bar.contentsScale = 1.0
            bar.masksToBounds = true
            bar.contentsGravity = .bottomLeft
            bars.append(bar)
            xOffset += Int(width)
        }
        xOffset = Int(self.bounds.width / 2.0) - Int(width)
        for _ in 0..<num {
            let bar = CALayer()
            bar.frame = CGRect(x: xOffset, y: 0, width: Int(width), height: 10)
            bar.contentsScale = 1.0
            bar.masksToBounds = true
            bar.contentsGravity = .bottomLeft
            barsLeft.insert(bar, at: 0)
            xOffset -= Int(width)
        }

        setupBars()
        resizeSubviews(withOldSize: self.bounds.size)
    }

    private func setupBars() {
        width = floor(CGFloat(self.bounds.size.width / CGFloat(mirror ? num + num : num)))
        height = CGFloat(self.bounds.size.height) - 20.0

        for idx in 0..<num {
            let bar1 = bars[idx]
            bar1.removeFromSuperlayer()
            let bar2 = barsLeft[idx]
            bar2.removeFromSuperlayer()
        }

        if mirror {
            var xOffset = Int(self.bounds.width / 2.0)
            for idx in 0..<num {
                let bar = bars[idx]
                self.layer?.addSublayer(bar)
                xOffset += Int(width)
            }
            xOffset = Int(self.bounds.width / 2.0) - Int(width)
            for idx in 0..<num {
                let bar = barsLeft[idx]
                self.layer?.addSublayer(bar)
                xOffset -= Int(width)
            }
        } else {
            var xOffset = 0
            for idx in 0..<num {
                let bar = bars[idx]
                self.layer?.addSublayer(bar)
                xOffset += Int(width)
            }
        }
    }

    func updateFrequencyImage(img: CGImage) {
        self.layer?.contents = img
    }

    func updateFrequency(frequencyData: [CGFloat]) {
        // Draw frequency bars
        width = floor(CGFloat(self.bounds.size.width / CGFloat(mirror ? num + num : num)))
        height = CGFloat(self.bounds.size.height) - 20.0
        let volumeR = volume * 28.0
        if frequencyData.count == num {
            if mirror {
                var xOffset = Int(self.bounds.width / 2.0)
                for idx in 0..<num {
                    let freq = Int(frequencyData[idx] < 0 ? 0 : frequencyData[idx] * volumeR)
                    bars[idx].frame = CGRect(x: Int(xOffset), y: 0, width: Int(width), height: freq)
                    xOffset += Int(width)
                    xOffset += 1
                }
                xOffset = Int(self.bounds.width / 2.0) - Int(width) - 1
                for idx in 0..<num {
                    let freq = Int(frequencyData[idx] < 0 ? 0 : frequencyData[idx] * volumeR)
                    barsLeft[idx].frame = CGRect(x: Int(xOffset), y: 0, width: Int(width), height: freq)
                    xOffset -= Int(width)
                    xOffset -= 1
                }
            } else {
                var xOffset = 0
                for idx in 0..<num {
                    let freq = Int(frequencyData[idx] < 0 ? 0 : frequencyData[idx] * volumeR)
                    bars[idx].frame = CGRect(x: Int(xOffset), y: 0, width: Int(width), height: freq)
                    xOffset += Int(width)
                    xOffset += 1
                }
            }
        } else {
            print("frequencyData num is not match")
        }
    }

    override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        width = floor(CGFloat(self.bounds.size.width / CGFloat(num)))
        height = CGFloat(self.bounds.size.height) + 10.0
        bgLayer = CAGradientLayer()
        bgLayer.frame = CGRect(x: 0, y: 0, width: width, height: height)
        bgLayer.startPoint = CGPoint(x: 0.0, y: 1.0)
        bgLayer.endPoint = CGPoint(x: 0.0, y: 0.0)
        bgLayer.colors = [NSColor.red.cgColor,
                          NSColor.orange.cgColor,
                          NSColor.yellow.cgColor,
                          NSColor.green.cgColor,
                          NSColor.blue.cgColor,
                          NSColor.purple.cgColor]
        let bitmap = bgLayer.getBitmapImage()
        for idx in 0..<num {
            bars[idx].contents = bitmap
            bars[idx].contentsScale = 1.0
            bars[idx].masksToBounds = true
            bars[idx].contentsGravity = .bottomLeft
            barsLeft[idx].contents = bitmap
            barsLeft[idx].contentsScale = 1.0
            barsLeft[idx].masksToBounds = true
            barsLeft[idx].contentsGravity = .bottomLeft
        }
        CATransaction.commit()
    }

    func clearFrequency() {
        width = floor(CGFloat(self.bounds.size.width / CGFloat(mirror ? num + num : num)))
        let freq = Int(1)
        if mirror {
            var xOffset = Int(self.bounds.width / 2.0)
            for idx in 0..<num {
                bars[idx].frame = CGRect(x: xOffset, y: 0, width: Int(width), height: freq)
                xOffset += Int(width)
            }
            xOffset = Int(self.bounds.width / 2.0) - Int(width)
            for idx in 0..<num {
                barsLeft[idx].frame = CGRect(x: xOffset, y: 0, width: Int(width), height: freq)
                xOffset -= Int(width)
            }
        } else {
            var xOffset = 0
            for idx in 0..<num {
                bars[idx].frame = CGRect(x: xOffset, y: 0, width: Int(width), height: freq)
                xOffset += Int(width)
            }
        }
    }
}
