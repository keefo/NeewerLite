//
//  AudioSpectrogramVisualization.swift
//  NeewerLite
//
//  Created by Xu Lian on 1/5/21.
//

import Cocoa
import MetalKit
import os.signpost

// MARK: - Stage 3: MTKView Metal Renderer

class AudioSpectrogramVisualization: MTKView, MTKViewDelegate {

    let num: Int = AudioSpectrogram.filterBankCount
    var width: CGFloat = 10.0
    var height: CGFloat = 128.0
    var volume: Float = 1.0
    var reset: Bool = true
    var showWaterfall: Bool = true

    // Cached per-bar X positions — recomputed only on layout change, not every frame.
    private var barXPositions: [Float] = []
    private var barsLeftXPositions: [Float] = []
    // Smoothed display heights — exponentially interpolated toward the target each frame
    // so bars glide smoothly without relying on CA implicit animations.
    // alpha: 0 = frozen, 1 = instant snap. 0.25 matches the feel of the old CA default.
    private var smoothedHeights: [Float] = []
    private let smoothingAlpha: Float = 0.25

    // Thread-safe pending data written by the audio callback thread.
    private var pendingFrequencyData: [Float]?
    private var pendingWaterfallImage: CGImage?
    private let pendingLock = NSLock()

    // MARK: – Metal resources
    private var commandQueue: MTLCommandQueue!
    private var barPipelineState: MTLRenderPipelineState?
    private var waterfallPipelineState: MTLRenderPipelineState?
    private var barDataBuffer: MTLBuffer?
    private var uniformsBuffer: MTLBuffer?
    private var gradientTexture: MTLTexture?
    private var waterfallTexture: MTLTexture?
    // Reusable CGContext for waterfall texture conversion — avoids per-frame allocation.
    private var waterfallCtx: CGContext?
    private var waterfallCtxSize: (Int, Int) = (0, 0)

    // MARK: – Stage-0 baseline instrumentation
    private let renderLog = OSLog(subsystem: "com.beyondcow.neewerlite", category: "SpectrogramRender")

    var mirror: Bool = false {
        didSet {
            setupBars()
        }
    }

    override var isOpaque: Bool { true }

    override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device)
        commonInit()
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        self.device = device
        self.delegate = self
        self.isPaused = false
        self.enableSetNeedsDisplay = false
        self.preferredFramesPerSecond = 60
        self.colorPixelFormat = .bgra8Unorm
        self.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        commandQueue = device.makeCommandQueue()
        buildPipelines(device: device)
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        self.layer?.cornerRadius = 14.0
        self.layer?.masksToBounds = true
        setupBars()
    }

    // MARK: - Metal Shader Source

    private let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    // --- Waterfall fullscreen pass ---
    struct WaterfallVOut {
        float4 position [[position]];
        float2 texCoord;
    };

    vertex WaterfallVOut waterfallVertex(uint vid [[vertex_id]]) {
        float2 pos[4] = { float2(-1,-1), float2(1,-1), float2(-1,1), float2(1,1) };
        float2 uv[4]  = { float2(0,1),   float2(1,1),  float2(0,0),  float2(1,0) };
        WaterfallVOut out;
        out.position = float4(pos[vid], 0.0, 1.0);
        out.texCoord = uv[vid];
        return out;
    }

    fragment float4 waterfallFragment(WaterfallVOut in [[stage_in]],
                                       texture2d<float> tex [[texture(0)]]) {
        constexpr sampler s(filter::linear);
        return tex.sample(s, in.texCoord);
    }

    // --- Bar instanced pass ---
    struct BarData {
        float xPosition;
        float barHeight;
    };

    struct BarUniforms {
        float viewWidth;
        float viewHeight;
        float barWidth;
    };

    struct BarVOut {
        float4 position [[position]];
        float normalizedY;
    };

    vertex BarVOut barVertex(uint vid [[vertex_id]],
                              uint iid [[instance_id]],
                              constant BarData *bars [[buffer(0)]],
                              constant BarUniforms &u [[buffer(1)]]) {
        float2 c[4] = { float2(0,0), float2(1,0), float2(0,1), float2(1,1) };
        float2 corner = c[vid];
        float x = bars[iid].xPosition + corner.x * u.barWidth;
        float y = corner.y * bars[iid].barHeight;
        BarVOut out;
        out.position = float4(x / u.viewWidth * 2.0 - 1.0,
                              y / u.viewHeight * 2.0 - 1.0,
                              0.0, 1.0);
        out.normalizedY = y / u.viewHeight;
        return out;
    }

    fragment float4 barFragment(BarVOut in [[stage_in]],
                                texture2d<float> gradient [[texture(0)]]) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        return gradient.sample(s, float2(0.5, 1.0 - in.normalizedY));
    }
    """

    private func buildPipelines(device: MTLDevice) {
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: shaderSource, options: nil)
        } catch {
            Logger.error("[Spectrogram] Metal shader compilation failed: \(error)")
            return
        }

        let wfDesc = MTLRenderPipelineDescriptor()
        wfDesc.vertexFunction = library.makeFunction(name: "waterfallVertex")
        wfDesc.fragmentFunction = library.makeFunction(name: "waterfallFragment")
        wfDesc.colorAttachments[0].pixelFormat = colorPixelFormat
        waterfallPipelineState = try? device.makeRenderPipelineState(descriptor: wfDesc)

        let barDesc = MTLRenderPipelineDescriptor()
        barDesc.vertexFunction = library.makeFunction(name: "barVertex")
        barDesc.fragmentFunction = library.makeFunction(name: "barFragment")
        barDesc.colorAttachments[0].pixelFormat = colorPixelFormat
        barPipelineState = try? device.makeRenderPipelineState(descriptor: barDesc)
    }

    // MARK: - Bar Layout

    private func setupBars() {
        width = floor(CGFloat(self.bounds.size.width / CGFloat(mirror ? num + num : num)))
        height = CGFloat(self.bounds.size.height) + 10.0

        barXPositions = [Float](repeating: 0, count: num)
        barsLeftXPositions = [Float](repeating: 0, count: num)

        if mirror {
            var xOffset = Float(self.bounds.width / 2.0)
            for idx in 0..<num {
                barXPositions[idx] = xOffset
                xOffset += Float(width) + 1
            }
            xOffset = Float(self.bounds.width / 2.0) - Float(width) - 1
            for idx in 0..<num {
                barsLeftXPositions[idx] = xOffset
                xOffset -= Float(width) + 1
            }
        } else {
            var xOffset: Float = 0
            for idx in 0..<num {
                barXPositions[idx] = xOffset
                xOffset += Float(width) + 1
            }
        }

        buildGradientTexture()
    }

    // MARK: - Gradient Texture

    private func buildGradientTexture() {
        guard let device = device else { return }
        let h = max(Int(height), 1)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil,
                                  width: 1,
                                  height: h,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 4,
                                  space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(
                  colorsSpace: cs,
                  colors: [NSColor.red.cgColor,
                           NSColor.orange.cgColor,
                           NSColor.yellow.cgColor,
                           NSColor.green.cgColor,
                           NSColor.blue.cgColor,
                           NSColor.purple.cgColor] as CFArray,
                  locations: nil)
        else { return }
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: 0, y: CGFloat(h)),
                               end: CGPoint(x: 0, y: 0),
                               options: [])

        guard let data = ctx.data else { return }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 1, height: h, mipmapped: false)
        desc.usage = .shaderRead
        guard let tex = device.makeTexture(descriptor: desc) else { return }
        tex.replace(region: MTLRegionMake2D(0, 0, 1, h),
                    mipmapLevel: 0,
                    withBytes: data,
                    bytesPerRow: 4)
        gradientTexture = tex
    }

    // MARK: - Waterfall Texture

    private func updateWaterfallTexture(from image: CGImage) {
        guard let device = device else { return }
        let w = image.width
        let h = image.height

        if waterfallTexture == nil ||
           waterfallTexture!.width != w ||
           waterfallTexture!.height != h {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: w, height: h, mipmapped: false)
            desc.usage = .shaderRead
            waterfallTexture = device.makeTexture(descriptor: desc)
        }

        guard let tex = waterfallTexture else { return }
        let bytesPerRow = w * 4

        // Reuse CGContext between frames to avoid per-frame allocation.
        if waterfallCtxSize != (w, h) {
            let cs = CGColorSpaceCreateDeviceRGB()
            waterfallCtx = CGContext(data: nil, width: w, height: h,
                                     bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                     space: cs,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            waterfallCtxSize = (w, h)
        }
        guard let ctx = waterfallCtx, let data = ctx.data else { return }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        tex.replace(region: MTLRegionMake2D(0, 0, w, h),
                    mipmapLevel: 0,
                    withBytes: data,
                    bytesPerRow: bytesPerRow)
    }

    // MARK: - Public API (thread-safe)

    func updateSpectrogramImage(_ image: CGImage) {
        pendingLock.lock()
        pendingWaterfallImage = image
        pendingLock.unlock()
    }

    func updateFrequency(_ data: [Float]) {
        pendingLock.lock()
        pendingFrequencyData = data
        pendingLock.unlock()
    }

    // MARK: - Smoothing (CPU — negligible cost)

    private func applyFrequencyData(_ frequencyData: [Float]) {
        os_signpost(.begin, log: renderLog, name: "updateFrequency")
        defer { os_signpost(.end, log: renderLog, name: "updateFrequency") }

        guard frequencyData.count == num, !barXPositions.isEmpty else { return }

        if smoothedHeights.count != num {
            smoothedHeights = [Float](repeating: 0, count: num)
        }

        let volumeR = volume * 28.0
        let alpha = smoothingAlpha
        let oneMinusAlpha = 1.0 - alpha

        for idx in 0..<num {
            let target = max(0, frequencyData[idx] * volumeR)
            smoothedHeights[idx] = smoothedHeights[idx] * oneMinusAlpha + target * alpha
        }
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        setupBars()
        smoothedHeights = [Float](repeating: 0, count: num)
    }

    func draw(in view: MTKView) {
        // Consume pending data from audio thread.
        pendingLock.lock()
        let freqData = pendingFrequencyData
        pendingFrequencyData = nil
        let newWaterfall = pendingWaterfallImage
        pendingWaterfallImage = nil
        pendingLock.unlock()

        // Skip draw when there's no new data — saves ~50% of GPU/CPU draws.
        if freqData == nil && newWaterfall == nil {
            return
        }

        if let data = freqData {
            applyFrequencyData(data)
        }
        if showWaterfall, let img = newWaterfall {
            updateWaterfallTexture(from: img)
        }

        guard let drawable = currentDrawable,
              let descriptor = currentRenderPassDescriptor,
              let cmdBuf = commandQueue?.makeCommandBuffer(),
              let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }

        // Pass 1: Waterfall background
        if showWaterfall, let wfPipeline = waterfallPipelineState, let wfTex = waterfallTexture {
            encoder.setRenderPipelineState(wfPipeline)
            encoder.setFragmentTexture(wfTex, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        // Pass 2: Frequency bars (instanced)
        if let barPipeline = barPipelineState, let gradTex = gradientTexture {
            let barCount = fillBarDataBuffer()
            if barCount > 0 {
                encoder.setRenderPipelineState(barPipeline)
                encoder.setVertexBuffer(barDataBuffer, offset: 0, index: 0)
                encoder.setVertexBuffer(uniformsBuffer, offset: 0, index: 1)
                encoder.setFragmentTexture(gradTex, index: 0)
                encoder.drawPrimitives(type: .triangleStrip,
                                       vertexStart: 0, vertexCount: 4,
                                       instanceCount: barCount)
            }
        }

        encoder.endEncoding()
        cmdBuf.present(drawable)
        cmdBuf.commit()
    }

    // MARK: - Bar Data Buffer

    private struct BarData {
        var xPosition: Float
        var barHeight: Float
    }

    private struct BarUniforms {
        var viewWidth: Float
        var viewHeight: Float
        var barWidth: Float
    }

    private func fillBarDataBuffer() -> Int {
        guard let device = device else { return 0 }

        let maxBars = mirror ? num * 2 : num
        let bufferSize = MemoryLayout<BarData>.stride * maxBars

        if barDataBuffer == nil || barDataBuffer!.length < bufferSize {
            barDataBuffer = device.makeBuffer(length: bufferSize, options: .storageModeShared)
        }
        if uniformsBuffer == nil {
            uniformsBuffer = device.makeBuffer(length: MemoryLayout<BarUniforms>.stride,
                                               options: .storageModeShared)
        }
        guard let barBuf = barDataBuffer, let uniBuf = uniformsBuffer else { return 0 }

        let barPtr = barBuf.contents().bindMemory(to: BarData.self, capacity: maxBars)
        var count = 0

        if mirror {
            for idx in 0..<num {
                let h = smoothedHeights.count > idx ? smoothedHeights[idx] : 0
                guard h > 1 else { continue }
                barPtr[count] = BarData(xPosition: barXPositions[idx], barHeight: h)
                count += 1
                barPtr[count] = BarData(xPosition: barsLeftXPositions[idx], barHeight: h)
                count += 1
            }
        } else {
            for idx in 0..<num {
                let h = smoothedHeights.count > idx ? smoothedHeights[idx] : 0
                guard h > 1 else { continue }
                barPtr[count] = BarData(xPosition: barXPositions[idx], barHeight: h)
                count += 1
            }
        }

        let uniPtr = uniBuf.contents().bindMemory(to: BarUniforms.self, capacity: 1)
        uniPtr.pointee = BarUniforms(
            viewWidth: Float(bounds.width),
            viewHeight: Float(bounds.height),
            barWidth: Float(width)
        )

        return count
    }

    override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        setupBars()
        smoothedHeights = [Float](repeating: 0, count: num)
    }

    func clear() {
        smoothedHeights = [Float](repeating: 1, count: num)
    }
}

// MARK: - AudioVisualizerPlugin Conformance

extension AudioSpectrogramVisualization: AudioVisualizerPlugin {
    static var displayName: String { "Spectrogram" }
    var visualizerView: NSView { self }
    var needsSpectrogramImage: Bool { showWaterfall }
}
