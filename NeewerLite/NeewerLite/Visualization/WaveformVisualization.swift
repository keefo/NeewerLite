//
//  WaveformVisualization.swift
//  NeewerLite
//
//  Created by Xu Lian on 4/11/26.
//

import Cocoa

/// A smooth waveform/mountain visualization drawn with CoreGraphics.
/// Renders frequency data as a filled bezier curve with a color gradient.
final class WaveformVisualization: NSObject, AudioVisualizerPlugin {
    static var displayName: String { "Waveform" }

    private let waveView: WaveformView
    var visualizerView: NSView { waveView }
    var needsSpectrogramImage: Bool { false }

    var volume: Float {
        get { waveView.volume }
        set { waveView.volume = newValue }
    }

    var mirror: Bool {
        get { waveView.mirror }
        set { waveView.mirror = newValue }
    }

    init(frame: NSRect) {
        waveView = WaveformView(frame: frame)
        super.init()
    }

    func updateFrequency(_ data: [Float]) {
        waveView.updateFrequency(data)
    }

    func clear() {
        waveView.clear()
    }
}

// MARK: - WaveformView

/// Internal NSView that renders the waveform using CoreGraphics.
/// Uses a timer-driven render loop similar to MTKView's draw callback.
private final class WaveformView: NSView {

    var volume: Float = 1.0
    var mirror: Bool = false

    private var smoothedData: [Float] = []
    private var pendingData: [Float]?
    private let lock = NSLock()
    private var renderTimer: Timer?

    private let smoothingAlpha: Float = 0.25

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
    }

    deinit {
        renderTimer?.invalidate()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            startRenderTimer()
        } else {
            stopRenderTimer()
        }
    }

    private func startRenderTimer() {
        guard renderTimer == nil else { return }
        renderTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func stopRenderTimer() {
        renderTimer?.invalidate()
        renderTimer = nil
    }

    func updateFrequency(_ data: [Float]) {
        lock.lock()
        pendingData = data
        lock.unlock()
    }

    func clear() {
        lock.lock()
        pendingData = nil
        lock.unlock()
        smoothedData = []
        needsDisplay = true
    }

    private func tick() {
        lock.lock()
        let data = pendingData
        pendingData = nil
        lock.unlock()

        guard let data = data else { return }

        if smoothedData.count != data.count {
            smoothedData = [Float](repeating: 0, count: data.count)
        }

        let alpha = smoothingAlpha
        let oneMinusAlpha = 1.0 - alpha

        for i in 0..<data.count {
            let target = max(0, data[i])
            smoothedData[i] = smoothedData[i] * oneMinusAlpha + target * alpha
        }

        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let w = bounds.width
        let h = bounds.height

        // Black background
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(bounds)

        guard !smoothedData.isEmpty else { return }

        let count = smoothedData.count
        drawVoiceWaveform(ctx: ctx, w: w, h: h, count: count)
    }

    /// Decaying peak tracker for smooth normalization.
    private var trackingPeak: Float = 0
    private let peakDecay: Float = 0.995

    /// Voice-waveform style: mirrored peaks from center with a horizontal
    /// rainbow gradient (purple → red → orange → yellow → green → cyan → blue).
    /// Uses Catmull-Rom spline interpolation for smooth organic curves.
    private func drawVoiceWaveform(ctx: CGContext, w: CGFloat, h: CGFloat, count: Int) {
        let centerY = h / 2.0
        let stepX = w / CGFloat(count - 1)

        // Leave 12% padding at top and bottom for breathing room.
        let padding: CGFloat = h * 0.12
        let maxAmplitude = centerY - padding

        // Update decaying peak: instant attack, slow release.
        let framePeak = smoothedData.max() ?? 0
        if framePeak.isFinite && framePeak > trackingPeak {
            trackingPeak = framePeak
        } else {
            trackingPeak *= Float(peakDecay)
        }

        let processed = normalizedFrequencyData(smoothedData, referencePeak: trackingPeak)

        // Build point arrays for top and bottom edges.
        var topPoints = [CGPoint](repeating: .zero, count: count)
        var bottomPoints = [CGPoint](repeating: .zero, count: count)

        for i in 0..<count {
            let x = CGFloat(i) * stepX
            let amplitude = CGFloat(processed[i]) * maxAmplitude
            topPoints[i] = CGPoint(x: x, y: centerY + amplitude)
            bottomPoints[i] = CGPoint(x: x, y: centerY - amplitude)
        }

        // Build smooth mirrored path using Catmull-Rom splines.
        let path = CGMutablePath()
        path.move(to: topPoints[0])

        // Top edge: left → right (smooth)
        addCatmullRomCurve(to: path, points: topPoints)

        // Bottom edge: right → left (smooth, reversed)
        let reversedBottom = bottomPoints.reversed().map { $0 }
        path.addLine(to: reversedBottom[0])
        addCatmullRomCurve(to: path, points: reversedBottom)

        path.closeSubpath()

        // Clip to the waveform shape and fill with a horizontal rainbow gradient.
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()

        let cs = CGColorSpaceCreateDeviceRGB()
        let colors = [
            NSColor(calibratedHue: 0.62, saturation: 0.8, brightness: 0.9, alpha: 1).cgColor,  // blue (low freq)
            NSColor(calibratedHue: 0.50, saturation: 0.7, brightness: 0.9, alpha: 1).cgColor,  // cyan
            NSColor(calibratedHue: 0.33, saturation: 0.8, brightness: 0.9, alpha: 1).cgColor,  // green
            NSColor(calibratedHue: 0.15, saturation: 0.9, brightness: 1.0, alpha: 1).cgColor,  // yellow
            NSColor(calibratedHue: 0.08, saturation: 0.9, brightness: 1.0, alpha: 1).cgColor,  // orange
            NSColor(calibratedHue: 0.02, saturation: 0.9, brightness: 1.0, alpha: 1).cgColor,  // red
            NSColor(calibratedHue: 0.95, saturation: 0.9, brightness: 1.0, alpha: 1).cgColor,  // magenta
            NSColor(calibratedHue: 0.85, saturation: 0.8, brightness: 0.9, alpha: 1).cgColor,  // pink (high freq)
        ] as CFArray

        if let gradient = CGGradient(colorsSpace: cs, colors: colors, locations: nil) {
            ctx.drawLinearGradient(gradient,
                                   start: CGPoint(x: 0, y: centerY),
                                   end: CGPoint(x: w, y: centerY),
                                   options: [])
        }
        ctx.restoreGState()

        // Soft glow: draw a second pass with reduced alpha for a blended look.
        ctx.saveGState()
        ctx.setAlpha(0.3)
        ctx.setBlendMode(.screen)
        ctx.addPath(path)
        ctx.clip()

        // Vertical gradient: bright at center, dark at peaks — gives depth.
        let glowColors = [
            NSColor.white.withAlphaComponent(0.6).cgColor,
            NSColor.white.withAlphaComponent(0.0).cgColor,
        ] as CFArray
        if let glowGrad = CGGradient(colorsSpace: cs, colors: glowColors, locations: nil) {
            ctx.drawLinearGradient(glowGrad,
                                   start: CGPoint(x: w / 2, y: centerY),
                                   end: CGPoint(x: w / 2, y: h),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        ctx.restoreGState()
    }

    // MARK: - Catmull-Rom Spline

    /// Appends a Catmull-Rom spline through the given points as cubic Bezier
    /// segments. The path's current point should already be at points[0].
    /// Uses the standard conversion: for segment P1→P2 with neighbors P0, P3:
    ///   cp1 = P1 + (P2 - P0) / 6
    ///   cp2 = P2 - (P3 - P1) / 6
    private func addCatmullRomCurve(to path: CGMutablePath, points: [CGPoint]) {
        let n = points.count
        guard n >= 2 else { return }

        if n == 2 {
            path.addLine(to: points[1])
            return
        }

        for i in 0..<(n - 1) {
            let p0 = points[max(i - 1, 0)]
            let p1 = points[i]
            let p2 = points[min(i + 1, n - 1)]
            let p3 = points[min(i + 2, n - 1)]

            let cp1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6.0,
                              y: p1.y + (p2.y - p0.y) / 6.0)
            let cp2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6.0,
                              y: p2.y - (p3.y - p1.y) / 6.0)

            path.addCurve(to: p2, control1: cp1, control2: cp2)
        }
    }
}
