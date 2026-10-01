import ColorbeeCore
import Metal
import QuartzCore
import simd

struct QuadUniforms {
    var rect: SIMD4<Float> = .zero
    var keyColor: SIMD4<Float> = .zero
    var viewportSize: SIMD2<Float> = .zero
    var imageSize: SIMD2<Float> = .zero
    var opacity: Float = 1
    var checkerSize: Float = 16
    var keyEnabled: Float = 0
    var antsPhase: Float = 0
    var pixelSize: Float = 1
}

/// Everything needed to draw one frame of a document.
struct RenderScene {
    let canvas: Canvas
    let viewport: Viewport
    /// The selection outline: a mask drawn stretched over a rect in image coordinates.
    let outline: (mask: SelectionMask, rect: IntRect)?
    let transparentKey: Pixel?
    /// Whether a stretched floating selection is shown smooth rather than as sharp pixels.
    let smoothFloating: Bool
    /// A shape being edited, drawn above the active layer.
    let overlay: (pixels: PixelBuffer, origin: IntPoint)?
    /// Handle positions in image coordinates.
    let handlePoints: [Point2D]
    let showsPixelGrid: Bool
    let antsPhase: Float
    /// Before/After: the earlier image and how to show it.
    let comparison: (before: PixelBuffer, layout: Comparison.Layout, dividerX: Double)?
}

/// Displays a canvas. Layer pixels are read straight from their CPU buffers with no copies.
@MainActor
final class Renderer {
    static let shared = Renderer()
    static let pixelGridMinimumZoom = 4.0

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let layerPipeline: MTLRenderPipelineState
    private let checkerPipeline: MTLRenderPipelineState
    private let antsPipeline: MTLRenderPipelineState
    private let gridPipeline: MTLRenderPipelineState
    private let solidPipeline: MTLRenderPipelineState
    private let nearestSampler: MTLSamplerState
    private let linearSampler: MTLSamplerState
    private let maskSampler: MTLSamplerState
    private var pixelTextures: [ObjectIdentifier: PixelTexture] = [:]
    private var maskTexture: (revision: UInt64, texture: MTLTexture)?

    private struct PixelTexture {
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

        func pipeline(fragment: String, blended: Bool = true) -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "quad_vertex")
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            let attachment = descriptor.colorAttachments[0]!
            attachment.pixelFormat = .bgra8Unorm
            if blended {
                attachment.isBlendingEnabled = true
                attachment.sourceRGBBlendFactor = .one
                attachment.sourceAlphaBlendFactor = .one
                attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
                attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
            do {
                return try device.makeRenderPipelineState(descriptor: descriptor)
            } catch {
                fatalError("Couldn't build the \(fragment) pipeline: \(error)")
            }
        }
        layerPipeline = pipeline(fragment: "layer_fragment")
        checkerPipeline = pipeline(fragment: "checker_fragment")
        antsPipeline = pipeline(fragment: "ants_fragment")
        gridPipeline = pipeline(fragment: "grid_fragment", blended: false)
        solidPipeline = pipeline(fragment: "solid_fragment")

        func sampler(_ filter: MTLSamplerMinMagFilter, address: MTLSamplerAddressMode = .clampToEdge) -> MTLSamplerState {
            let descriptor = MTLSamplerDescriptor()
            descriptor.minFilter = filter
            descriptor.magFilter = filter
            descriptor.sAddressMode = address
            descriptor.tAddressMode = address
            return device.makeSamplerState(descriptor: descriptor)!
        }
        nearestSampler = sampler(.nearest)
        linearSampler = sampler(.linear)
        maskSampler = sampler(.nearest, address: .clampToZero)
    }

    /// Draws the scene and presents it. `onRendered` receives the host time the GPU finished;
    /// `onPresented` receives the host time the frame reached the screen (0 if it never did).
    func render(
        _ scene: RenderScene,
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

        let canvas = scene.canvas
        let zoom = scene.viewport.zoom
        // Side by side, the "before" image sits at the image origin and the canvas to its right.
        let canvasOffset: Double = if let comparison = scene.comparison, comparison.layout == .sideBySide {
            Double(comparison.before.width + Editor.comparisonGap)
        } else {
            0
        }
        // Snap the canvas origin to device pixels so 100% zoom is exactly 1:1.
        let origin = scene.viewport.viewPoint(fromImage: Point2D(x: canvasOffset, y: 0))
        let originX = (origin.x * scale).rounded()
        let originY = (origin.y * scale).rounded()
        func deviceRect(_ rect: IntRect) -> SIMD4<Float> {
            SIMD4(
                Float(originX + Double(rect.minX) * zoom * scale),
                Float(originY + Double(rect.minY) * zoom * scale),
                Float(Double(rect.width) * zoom * scale),
                Float(Double(rect.height) * zoom * scale)
            )
        }

        var uniforms = QuadUniforms()
        uniforms.viewportSize = SIMD2(Float(metalLayer.drawableSize.width), Float(metalLayer.drawableSize.height))
        uniforms.checkerSize = Float(8 * scale)
        uniforms.pixelSize = Float(zoom * scale)
        uniforms.antsPhase = scene.antsPhase
        uniforms.rect = deviceRect(canvas.bounds)
        uniforms.imageSize = SIMD2(Float(canvas.size.width), Float(canvas.size.height))

        func draw(_ pipeline: MTLRenderPipelineState) {
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<QuadUniforms>.stride, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<QuadUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        draw(checkerPipeline)
        var liveBuffers = Set<ObjectIdentifier>()
        if let comparison = scene.comparison, comparison.layout == .sideBySide {
            let before = comparison.before
            let beforeOrigin = scene.viewport.viewPoint(fromImage: .zero)
            uniforms.rect = SIMD4(
                Float((beforeOrigin.x * scale).rounded()), Float((beforeOrigin.y * scale).rounded()),
                Float(Double(before.width) * zoom * scale), Float(Double(before.height) * zoom * scale)
            )
            draw(checkerPipeline)
            encoder.setFragmentSamplerState(zoom >= 1 ? nearestSampler : linearSampler, index: 0)
            encoder.setFragmentTexture(texture(for: before, live: &liveBuffers), index: 0)
            draw(layerPipeline)
            uniforms.rect = deviceRect(canvas.bounds)
        }

        encoder.setFragmentSamplerState(zoom >= 1 ? nearestSampler : linearSampler, index: 0)
        let floating = canvas.selection.floating
        for layer in canvas.layers where layer.isVisible && layer.opacity > 0 {
            uniforms.opacity = Float(layer.opacity)
            uniforms.rect = deviceRect(canvas.bounds)
            uniforms.keyEnabled = 0
            encoder.setFragmentTexture(texture(for: layer.buffer, live: &liveBuffers), index: 0)
            draw(layerPipeline)

            if let floating, floating.layerID == layer.id {
                uniforms.rect = deviceRect(floating.destination)
                let stretched = floating.destination.size != floating.pixels.size
                encoder.setFragmentSamplerState(stretched && scene.smoothFloating ? linearSampler : nearestSampler, index: 0)
                if let key = scene.transparentKey {
                    uniforms.keyEnabled = 1
                    uniforms.keyColor = SIMD4(Float(key.r) / 255, Float(key.g) / 255, Float(key.b) / 255, 1)
                }
                encoder.setFragmentTexture(texture(for: floating.pixels, live: &liveBuffers), index: 0)
                draw(layerPipeline)
                encoder.setFragmentSamplerState(zoom >= 1 ? nearestSampler : linearSampler, index: 0)
            }
            if let overlay = scene.overlay, layer.id == canvas.activeLayer.id {
                uniforms.rect = deviceRect(IntRect(x: overlay.origin.x, y: overlay.origin.y, width: overlay.pixels.width, height: overlay.pixels.height))
                uniforms.keyEnabled = 0
                encoder.setFragmentTexture(texture(for: overlay.pixels, live: &liveBuffers), index: 0)
                draw(layerPipeline)
            }
        }
        if let comparison = scene.comparison, comparison.layout == .split {
            // Left of the divider shows "before", drawn over the current image.
            let dividerDevice = max(0, min(Double(metalLayer.drawableSize.width), comparison.dividerX * scale))
            if dividerDevice > 0 {
                encoder.setScissorRect(MTLScissorRect(x: 0, y: 0, width: Int(dividerDevice), height: Int(metalLayer.drawableSize.height)))
                uniforms.rect = deviceRect(IntRect(size: comparison.before.size))
                uniforms.opacity = 1
                uniforms.keyEnabled = 0
                encoder.setFragmentSamplerState(zoom >= 1 ? nearestSampler : linearSampler, index: 0)
                encoder.setFragmentTexture(texture(for: comparison.before, live: &liveBuffers), index: 0)
                draw(checkerPipeline)
                draw(layerPipeline)
                encoder.setScissorRect(MTLScissorRect(x: 0, y: 0, width: Int(metalLayer.drawableSize.width), height: Int(metalLayer.drawableSize.height)))
            }
            let lineWidth = Float(2 * scale)
            uniforms.rect = SIMD4(Float(dividerDevice) - lineWidth / 2, 0, lineWidth, Float(metalLayer.drawableSize.height))
            uniforms.keyColor = SIMD4(1, 1, 1, 1)
            draw(solidPipeline)
        }
        pixelTextures = pixelTextures.filter { liveBuffers.contains($0.key) }

        if let outline = scene.outline {
            uniforms.rect = deviceRect(outline.rect)
            encoder.setFragmentSamplerState(maskSampler, index: 0)
            encoder.setFragmentTexture(texture(for: outline.mask), index: 0)
            draw(antsPipeline)
        } else {
            maskTexture = nil
        }

        if scene.showsPixelGrid, zoom >= Self.pixelGridMinimumZoom {
            uniforms.rect = deviceRect(canvas.bounds)
            draw(gridPipeline)
        }

        if !scene.handlePoints.isEmpty {
            // Fixed on-screen size: an 8 pt dark square with a 6 pt white center.
            for point in scene.handlePoints {
                let centerX = Float(originX + point.x * zoom * scale)
                let centerY = Float(originY + point.y * zoom * scale)
                for (size, shade) in [(Float(8 * scale), Float(0.15)), (Float(6 * scale), Float(1))] {
                    uniforms.rect = SIMD4(centerX - size / 2, centerY - size / 2, size, size)
                    uniforms.keyColor = SIMD4(shade, shade, shade, 1)
                    draw(solidPipeline)
                }
            }
        }
        encoder.endEncoding()

        commandBuffer.addCompletedHandler { _ in
            onRendered(CACurrentMediaTime())
        }
        drawable.addPresentedHandler { presented in
            onPresented(presented.presentedTime)
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func texture(for buffer: PixelBuffer, live: inout Set<ObjectIdentifier>) -> MTLTexture {
        let key = ObjectIdentifier(buffer)
        live.insert(key)
        if let cached = pixelTextures[key] { return cached.texture }

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
            fatalError("Couldn't wrap the pixel buffer for the GPU")
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
            fatalError("Couldn't create the pixel texture")
        }
        pixelTextures[key] = PixelTexture(buffer: buffer, metalBuffer: metalBuffer, texture: texture)
        return texture
    }

    private func texture(for mask: SelectionMask) -> MTLTexture {
        if let maskTexture, maskTexture.revision == mask.revision { return maskTexture.texture }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: mask.bounds.width,
            height: mask.bounds.height,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            fatalError("Couldn't create the selection texture")
        }
        mask.values.withUnsafeBytes { bytes in
            texture.replace(
                region: MTLRegionMake2D(0, 0, mask.bounds.width, mask.bounds.height),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: mask.bounds.width
            )
        }
        maskTexture = (mask.revision, texture)
        return texture
    }
}
