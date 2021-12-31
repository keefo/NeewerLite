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
        NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(self.frame.width), pixelsHigh: Int(self.frame.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: NSColorSpaceName.deviceRGB, bytesPerRow: 0, bitsPerPixel: 32)

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
    let n: Int = AudioSpectrogram.filterBankCount
    let w: Int = 10
    let h: Int = 128

    override func awakeFromNib()
    {
        self.wantsLayer = true

        self.window?.title = "Audio Spectrogram"

        self.window?.setContentSize(NSSize(width: n * w,
                                           height: h))
        self.window?.showsResizeIndicator = false
        self.window?.contentResizeIncrements = NSSize(width: Double.greatestFiniteMagnitude,
                                                      height: Double.greatestFiniteMagnitude)
        self.window?.center()

        self.layer?.backgroundColor = NSColor.black.cgColor

        let bg = CAGradientLayer()
        bg.frame = CGRect(x: 0, y: 0, width: w, height: h)
        bg.startPoint = CGPoint(x:0.0, y:1.0)
        bg.endPoint = CGPoint(x:0.0, y:0.0)
        bg.colors = [NSColor.red.cgColor, NSColor.orange.cgColor, NSColor.yellow.cgColor, NSColor.green.cgColor, NSColor.blue.cgColor, NSColor.purple.cgColor]

        var x = 0
        for _ in 0...n {

            let bar = CALayer()
            bar.frame = CGRect(x: x, y: 0, width: w, height: 10)
            bar.contents = bg.getBitmapImage()
            bar.contentsScale = 1.0
            bar.masksToBounds = true
            bar.contentsGravity = .bottomLeft
            self.layer?.addSublayer(bar)
            bars.append(bar)
            x += w
        }
    }

    func updateFrequency(frequency: [CGFloat]) {
        if frequency.count == n {
            for i in 0..<n {
                let freq = Int(frequency[i] < 0 ? 0 : frequency[i] * 3.8)
                bars[i].frame = CGRect(x: i*w, y: 0, width: w, height: freq)
            }
        }
    }

    func clearFrequency() {
        for i in 0..<n {
            let freq = Int(0)
            bars[i].frame = CGRect(x: i*w, y: 0, width: w, height: freq)
        }
    }

}



