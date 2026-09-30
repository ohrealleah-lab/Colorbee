import ColorbeeCore
import Metal
import QuartzCore
import simd

struct QuadUniforms {
    var rect: SIMD4<Float>
    var viewportSize: SIMD2<Float>
    var opacity: Float
    var checkerSize: Float
}

/// Displays a canvas. Layer pixels are read straight from their CPU buffers with no copies.
@MainActor
final class Renderer {
    static let shared = Renderer()

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let layerPipeline: MTLRenderPipelineState
    private let checkerPipeline: MTLRenderPipelineState
    private let nearestSampler: MTLSamplerState
    private let linearSampler: MTLSamplerState
    private var textures: [ObjectIdentifier: LayerTexture] = [:]

    private struct LayerTexture {
        let buffer: PixelBuffer
        let metalBuffer: MTLBuffer
        let texture: MTLTexture
    }

    private init() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else {
            fatalError("Metal is unavailable")
        }
        self.device = device
        self.queue = queue

        func pipeline(fragment: String) -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "quad_vertex")
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            let attachment = descriptor.colorAttachments[0]!
            attachment.pixelFormat = .bgra8Unorm
            attachment.isBlendingEnabled = true
            attachment.sourceRGBBlendFactor = .one
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            do {
                return try device.makeRenderPipelineState(descriptor: descriptor)
            } catch {
                fatalError("Couldn't build the \(fragment) pipeline: \(error)")
            }
        }
        layerPipeline = pipeline(fragment: "layer_fragment")
        checkerPipeline = pipeline(fragment: "checker_fragment")

        func sampler(_ filter: MTLSamplerMinMagFilter) -> MTLSamplerState {
            let descriptor = MTLSamplerDescriptor()
            descriptor.minFilter = filter
            descriptor.magFilter = filter
            descriptor.sAddressMode = .clampToEdge
            descriptor.tAddressMode = .clampToEdge
            return device.makeSamplerState(descriptor: descriptor)!
        }
        nearestSampler = sampler(.nearest)
        linearSampler = sampler(.linear)
    }

    /// Draws `canvas` and presents it. `onRendered` receives the host time the GPU finished the frame;
    /// `onPresented` receives the host time it reached the screen (0 if it never did).
    func render(
        _ canvas: Canvas,
        viewport: Viewport,
        into metalLayer: CAMetalLayer,
        scale: Double,
        surround: MTLClearColor,
        onRendered: @escaping @Sendable (CFTimeInterval) -> Void,
        onPresented: @escaping @Sendable (CFTimeInterval) -> Void
    ) {
        guard let drawable = metalLayer.nextDrawable(),
              let commandBuffer = queue.makeCommandBuffer() else { return }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = surround
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }

        // Snap the canvas origin to device pixels so 100% zoom is exactly 1:1.
        let origin = viewport.viewPoint(fromImage: .zero)
        var uniforms = QuadUniforms(
            rect: SIMD4(
                Float((origin.x * scale).rounded()),
                Float((origin.y * scale).rounded()),
                Float(Double(canvas.size.width) * viewport.zoom * scale),
                Float(Double(canvas.size.height) * viewport.zoom * scale)
            ),
            viewportSize: SIMD2(Float(metalLayer.drawableSize.width), Float(metalLayer.drawableSize.height)),
            opacity: 1,
            checkerSize: Float(8 * scale)
        )
        let uniformsLength = MemoryLayout<QuadUniforms>.stride

        encoder.setRenderPipelineState(checkerPipeline)
        encoder.setVertexBytes(&uniforms, length: uniformsLength, index: 0)
        encoder.setFragmentBytes(&uniforms, length: uniformsLength, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        encoder.setRenderPipelineState(layerPipeline)
        encoder.setFragmentSamplerState(viewport.zoom >= 1 ? nearestSampler : linearSampler, index: 0)
        var liveBuffers = Set<ObjectIdentifier>()
        for layer in canvas.layers where layer.isVisible && layer.opacity > 0 {
            liveBuffers.insert(ObjectIdentifier(layer.buffer))
            uniforms.opacity = Float(layer.opacity)
            encoder.setVertexBytes(&uniforms, length: uniformsLength, index: 0)
            encoder.setFragmentBytes(&uniforms, length: uniformsLength, index: 0)
            encoder.setFragmentTexture(texture(for: layer.buffer), index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        textures = textures.filter { liveBuffers.contains($0.key) }
        encoder.endEncoding()

        drawable.addPresentedHandler { presented in
            onPresented(presented.presentedTime)
        }
        commandBuffer.addCompletedHandler { _ in
            onRendered(CACurrentMediaTime())
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func texture(for buffer: PixelBuffer) -> MTLTexture {
        let key = ObjectIdentifier(buffer)
        if let cached = textures[key] { return cached.texture }

        precondition(
            buffer.bytesPerRow % device.minimumLinearTextureAlignment(for: .bgra8Unorm) == 0,
            "Row alignment is too small for a linear texture"
        )
        guard let metalBuffer = device.makeBuffer(
            bytesNoCopy: buffer.baseAddress,
            length: buffer.byteCount,
            options: .storageModeShared,
            deallocator: nil
        ) else {
            fatalError("Couldn't wrap the layer buffer for the GPU")
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: buffer.width,
            height: buffer.height,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = metalBuffer.makeTexture(descriptor: descriptor, offset: 0, bytesPerRow: buffer.bytesPerRow) else {
            fatalError("Couldn't create the layer texture")
        }
        textures[key] = LayerTexture(buffer: buffer, metalBuffer: metalBuffer, texture: texture)
        return texture
    }
}
