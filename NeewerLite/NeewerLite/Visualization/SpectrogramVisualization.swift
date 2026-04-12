//
//  SpectrogramVisualization.swift
//  NeewerLite
//
//  Created by Xu Lian on 4/11/26.
//

import Cocoa
import MetalKit

/// Metal-based waterfall visualization — renders only the scrolling
/// spectrogram image without the frequency bar overlay.
class SpectrogramVisualization: MTKView, MTKViewDelegate {

    var volume: Float = 1.0
    var mirror: Bool = false

    private var pendingWaterfallImage: CGImage?
    private let pendingLock = NSLock()

    // MARK: – Metal resources
    private var commandQueue: MTLCommandQueue!
    private var waterfallPipelineState: MTLRenderPipelineState?
    private var waterfallTexture: MTLTexture?
    private var waterfallCtx: CGContext?
    private var waterfallCtxSize: (Int, Int) = (0, 0)

    override var isOpaque: Bool { true }

    init(frame frameRect: CGRect) {
        super.init(frame: frameRect, device: MTLCreateSystemDefaultDevice())
        commonInit()
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        guard let device = device ?? MTLCreateSystemDefaultDevice() else { return }
        self.device = device
        self.delegate = self
        self.isPaused = false
        self.enableSetNeedsDisplay = false
        self.preferredFramesPerSecond = 60
        self.colorPixelFormat = .bgra8Unorm
        self.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        self.layer?.cornerRadius = 14.0
        self.layer?.masksToBounds = true

        commandQueue = device.makeCommandQueue()
        buildPipeline(device: device)
    }

    // MARK: - Metal Shader Source

    private let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

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
    """

    private func buildPipeline(device: MTLDevice) {
        guard let library = try? device.makeLibrary(source: shaderSource, options: nil) else {
            Logger.error("[Waterfall] Metal shader compilation failed")
            return
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "waterfallVertex")
        desc.fragmentFunction = library.makeFunction(name: "waterfallFragment")
        desc.colorAttachments[0].pixelFormat = colorPixelFormat
        waterfallPipelineState = try? device.makeRenderPipelineState(descriptor: desc)
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
        // Waterfall-only visualization does not use frequency data.
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        pendingLock.lock()
        let newWaterfall = pendingWaterfallImage
        pendingWaterfallImage = nil
        pendingLock.unlock()

        guard let img = newWaterfall else { return }

        updateWaterfallTexture(from: img)

        guard let drawable = currentDrawable,
              let descriptor = currentRenderPassDescriptor,
              let cmdBuf = commandQueue?.makeCommandBuffer(),
              let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }

        if let wfPipeline = waterfallPipelineState, let wfTex = waterfallTexture {
            encoder.setRenderPipelineState(wfPipeline)
            encoder.setFragmentTexture(wfTex, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        encoder.endEncoding()
        cmdBuf.present(drawable)
        cmdBuf.commit()
    }

    func clear() {
        waterfallTexture = nil
    }
}

// MARK: - AudioVisualizerPlugin Conformance

extension SpectrogramVisualization: AudioVisualizerPlugin {
    static var displayName: String { "Spectrogram" }
    var visualizerView: NSView { self }
    var needsSpectrogramImage: Bool { true }
}
