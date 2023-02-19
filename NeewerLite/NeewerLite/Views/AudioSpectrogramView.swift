//
//  AudioSpectrogramView.swift
//  NeewerLite
//
//  Created by Xu Lian on 1/5/21.
//

import Cocoa

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

class AudioSpectrogramView: NSView {

    var bars: [CALayer] = []
    let num: Int = AudioSpectrogram.filterBankCount
    let width: Int = 10
    let height: Int = 128

    override func awakeFromNib() {
        self.wantsLayer = true

        self.window?.title = "Audio Spectrogram"

        self.window?.setContentSize(NSSize(width: num * width,
                                           height: height))
        self.window?.showsResizeIndicator = false
        self.window?.contentResizeIncrements = NSSize(width: Double.greatestFiniteMagnitude,
                                                      height: Double.greatestFiniteMagnitude)
        self.window?.center()

        self.layer?.backgroundColor = NSColor.black.cgColor

        let bgLayer = CAGradientLayer()
        bgLayer.frame = CGRect(x: 0, y: 0, width: width, height: height)
        bgLayer.startPoint = CGPoint(x: 0.0, y: 1.0)
        bgLayer.endPoint = CGPoint(x: 0.0, y: 0.0)
        bgLayer.colors = [NSColor.red.cgColor,
                          NSColor.orange.cgColor,
                          NSColor.yellow.cgColor,
                          NSColor.green.cgColor,
                          NSColor.blue.cgColor,
                          NSColor.purple.cgColor]

        var xOffset = 0
        for _ in 0...num {

            let bar = CALayer()
            bar.frame = CGRect(x: xOffset, y: 0, width: width, height: 10)
            bar.contents = bgLayer.getBitmapImage()
            bar.contentsScale = 1.0
            bar.masksToBounds = true
            bar.contentsGravity = .bottomLeft
            self.layer?.addSublayer(bar)
            bars.append(bar)
            xOffset += width
        }
    }

    func updateFrequency(frequency: [CGFloat]) {
        if frequency.count == num {
            for idx in 0..<num {
                let freq = Int(frequency[idx] < 0 ? 0 : frequency[idx] * 3.8)
                bars[idx].frame = CGRect(x: idx*width, y: 0, width: width, height: freq)
            }
        }
    }

    func clearFrequency() {
        for idx in 0..<num {
            let freq = Int(0)
            bars[idx].frame = CGRect(x: idx*width, y: 0, width: width, height: freq)
        }
    }

}
