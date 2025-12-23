import Combine
import Metal
import MetalKit

public class WaterfallRenderer: NSObject, MTKViewDelegate, ObservableObject {
    public var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    private var spectrumTexture: MTLTexture!
    private var colorMapTexture: MTLTexture!
    private var samplerState: MTLSamplerState!

    // Data State
    private let textureHeight = 512
    private let textureWidth = 512  // Matches FFT size (1024 samples / 2)
    private var ringBufferIndex: Int = 0  // Line we are writing to (0...511)

    private var cancellables = Set<AnyCancellable>()

    public init(metalView: MTKView) {
        super.init()
        self.device = metalView.device ?? MTLCreateSystemDefaultDevice()
        metalView.device = self.device
        metalView.delegate = self
        metalView.framebufferOnly = true

        self.commandQueue = device.makeCommandQueue()

        buildPipeline()
        buildTextures()
        buildColorMap()
    }

    // Public API to ingest data
    public func appendSpectrum(data: [UInt8]) {
        // Data format: [UInt8] bins.
        // Kiwi sends bins. Length varies (e.g. 1024).
        // Update texture row.

        let width = data.count
        guard width > 0 else { return }

        let writeRow = ringBufferIndex

        // Dynamic resize check could go here, but for now strict 512.
        // Crop if too large, invalid if too small?
        // Just take prefix for safety.
        let bytesToCopy = min(width, textureWidth)
        let region = MTLRegionMake2D(0, writeRow, bytesToCopy, 1)

        let bytes = Array(data.prefix(bytesToCopy))

        bytes.withUnsafeBytes { ptr in
            if let baseAddress = ptr.baseAddress {
                spectrumTexture.replace(
                    region: region, mipmapLevel: 0, withBytes: baseAddress,
                    bytesPerRow: textureWidth)
            }
        }

        // increment index (wrap around)
        ringBufferIndex = (ringBufferIndex + 1) % textureHeight
    }

    private func buildPipeline() {
        // Load default library from Bundle.module
        // Note: When using SwiftPM resources, the .metallib is in Bundle.module.
        // However, standard makeDefaultLibrary() looks in Main Bundle.
        // We must find the bundle for this class.

        var library: MTLLibrary?
        do {
            // Try Bundle.module if available (SwiftPM)
            let bundle = Bundle.module
            library = try device.makeDefaultLibrary(bundle: bundle)
        } catch {
            print("Could not load library from Bundle.module: \(error)")
            // Fallback to default (might work if merged)
            library = device.makeDefaultLibrary()
        }

        guard let library = library else {
            print("Failed to load Metal library")
            return
        }

        let vertexFunction = library.makeFunction(name: "waterfallVertex")
        let fragmentFunction = library.makeFunction(name: "waterfallFragment")

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Pipeline creation error: \(error)")
        }

        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .repeat  // Wrap needed for ring buffer logic? Actually we handle wrap manually in logic, but .repeat is safer for v coords
        samplerState = device.makeSamplerState(descriptor: samplerDesc)
    }

    private func buildTextures() {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm, width: 512, height: 512, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]  // We write via replaceRegion
        spectrumTexture = device.makeTexture(descriptor: descriptor)

        // Clear to black
        // (Optional, init is usually 0)
    }

    private func buildColorMap() {
        // Create 1D Gradient (Black -> Blue -> Cyan -> Yellow -> Red)
        var pixels = [UInt32](repeating: 0, count: 256)

        // Define stops: (t, r, g, b)
        // 0.0: 0, 0, 0 (Black)
        // 0.2: 0, 0, 1 (Blue)
        // 0.4: 0, 1, 1 (Cyan)
        // 0.7: 1, 1, 0 (Yellow)
        // 1.0: 1, 0, 0 (Red)

        for i in 0..<256 {
            let t = Float(i) / 255.0
            var r: Float = 0
            var g: Float = 0
            var b: Float = 0

            if t < 0.2 {
                // Black -> Blue
                b = t / 0.2
            } else if t < 0.4 {
                // Blue -> Cyan
                b = 1.0
                g = (t - 0.2) / 0.2
            } else if t < 0.7 {
                // Cyan -> Yellow
                g = 1.0
                b = 1.0 - (t - 0.4) / 0.3
                r = (t - 0.4) / 0.3
            } else {
                // Yellow -> Red
                r = 1.0
                g = 1.0 - (t - 0.7) / 0.3
            }

            let r8 = UInt8(clamp(value: r) * 255)
            let g8 = UInt8(clamp(value: g) * 255)
            let b8 = UInt8(clamp(value: b) * 255)

            let pixel = (UInt32(255) << 24) | (UInt32(r8) << 16) | (UInt32(g8) << 8) | UInt32(b8)
            pixels[i] = pixel
        }

        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type1D
        descriptor.width = 256
        descriptor.pixelFormat = .bgra8Unorm
        descriptor.usage = .shaderRead

        colorMapTexture = device.makeTexture(descriptor: descriptor)
        colorMapTexture.replace(
            region: MTLRegionMake1D(0, 256), mipmapLevel: 0, withBytes: pixels, bytesPerRow: 256 * 4
        )
    }

    private func clamp(value: Float) -> Float {
        return max(0.0, min(1.0, value))
    }

    // MARK: - Draw
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
            let renderPassDescriptor = view.currentRenderPassDescriptor,
            let pipelineState = pipelineState
        else { return }

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: renderPassDescriptor)
        else { return }

        renderEncoder.setRenderPipelineState(pipelineState)

        // Geometry (Full Quad)
        let vertices: [Float] = [
            -1, -1, 0, 1,  // BL
            1, -1, 0, 1,  // BR
            -1, 1, 0, 1,  // TL
            1, -1, 0, 1,  // BR
            1, 1, 0, 1,  // TR
            -1, 1, 0, 1,  // TL
        ]

        let texCoords: [Float] = [
            0, 1,  // Bottom-Left (Oldest?)
            1, 1,
            0, 0,  // Top-Left (Newest?)
            1, 1,
            1, 0,
            0, 0,
        ]
        // Note: Our shader logic assumes v=0 is "Newest" (top).
        // Since we draw a quad, v=0 is top. v=1 is bottom. Matches.

        renderEncoder.setVertexBytes(
            vertices, length: vertices.count * MemoryLayout<Float>.size, index: 0)
        renderEncoder.setVertexBytes(
            texCoords, length: texCoords.count * MemoryLayout<Float>.size, index: 1)

        var offsetUniform = Float(ringBufferIndex) / Float(textureHeight)
        renderEncoder.setFragmentBytes(&offsetUniform, length: MemoryLayout<Float>.size, index: 0)

        renderEncoder.setFragmentTexture(spectrumTexture, index: 0)
        renderEncoder.setFragmentTexture(colorMapTexture, index: 1)
        renderEncoder.setFragmentSamplerState(samplerState, index: 0)

        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)

        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
