import ColorbeeCore
import Metal
import MetalPerformanceShaders
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
    var blendMode: Float = 0
    var adjustParams: SIMD4<Float> = .zero
    var adjustKind: Float = 0
    /// Adjust Photo: how many vignettes (x) and grains (z), which are in fragment buffer 1, and Texture (y, -1...1).
    var photoParams: SIMD4<Float> = .zero
    /// 1 when layers are sampled smoothly, which the shaders do in premultiplied color.
    var smooth: Float = 0
    /// Adjust Photo's `DetailAmounts`: color noise, luminance and color detail scales, halo damping.
    var detailParams: SIMD4<Float> = .zero
    /// Fine boost, Masking's threshold, and 1 to show the Masking mask.
    var detailParams2: SIMD4<Float> = .zero
    /// Adjust Photo's clipping warnings, for the final composite: 1 shows blown highlights red, 2 crushed shadows
    /// blue, 3 both.
    var clipWarnings: Float = 0
    /// x: 1 when a layer mask is bound (texture 10, stage 27); y: 1 to blend only where the backdrop has pixels, for a
    /// pixel layer set to "Only the layer below" (stage 28b).
    var maskParams: SIMD4<Float> = .zero
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
    /// A text layer whose box is open (stage 29): its own pixels give way to the text being typed, the overlay.
    var replacedLayer: LayerID? = nil
    /// New text that will be a layer of its own, drawn at Normal 100% above the layers while it's typed.
    var aboveLayers: (pixels: PixelBuffer, origin: IntPoint)? = nil
    /// The Redact Brush's or Remove's painted area, drawn above every layer: it belongs to no one layer, and must
    /// show even when the active layer is an adjustment layer or hidden (review O, finding 10).
    var topOverlay: (pixels: PixelBuffer, origin: IntPoint)? = nil
    /// Option-click on a mask (stage 28a): that mask shown alone, in grays, instead of the picture.
    var maskAlone: PixelBuffer? = nil
    /// Handle positions in image coordinates.
    let handlePoints: [Point2D]
    /// Round handles (rotation), in image coordinates.
    let roundHandlePoints: [Point2D]
    let showsPixelGrid: Bool
    let antsPhase: Float
    /// Guide and measuring lines in image coordinates, drawn on top at a fixed on-screen width.
    let lines: [(from: Point2D, to: Point2D, color: SIMD4<Float>)]
    /// Auto-Redact matches to outline: orange when they'll be redacted, gray when kept visible.
    let highlights: [(rect: IntRect, active: Bool)]
    /// Crop: the canvas outside this rectangle is shaded.
    var dimmedOutside: IntRect? = nil
    /// Edit ▸ Feather…'s preview: a tint over what isn't selected, fading in across a soft edge.
    var tintsOutsideSelection = false
    /// Adjust Photo's clipping warnings (FR-9.7 item 6), on screen only: blown highlights red, crushed shadows blue.
    var clipsHighlights = false
    var clipsShadows = false
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
    private let shadowPipeline: MTLRenderPipelineState
    private let tintPipeline: MTLRenderPipelineState
    private let antsPipeline: MTLRenderPipelineState
    private let gridPipeline: MTLRenderPipelineState
    private let solidPipeline: MTLRenderPipelineState
    private let linePipeline: MTLRenderPipelineState
    private let discPipeline: MTLRenderPipelineState
    /// Composites one layer onto the layers below it with its blend mode, reading them in the shader.
    private let blendLayerPipeline: MTLRenderPipelineState
    private let blendIsolatedPipeline: MTLRenderPipelineState
    private let fadeBackdropPipeline: MTLRenderPipelineState
    /// Draws the composited layers over the checkerboard.
    private let compositePipeline: MTLRenderPipelineState
    private let maskAlonePipeline: MTLRenderPipelineState
    private let adjustPointPipeline: MTLRenderPipelineState
    private let adjustBlurPipeline: MTLRenderPipelineState
    /// Levels, Curves, Sepia, Posterize (and later photo adjustments) through a 3D color table.
    private let adjustLookupPipeline: MTLRenderPipelineState
    private let adjustChannelPipeline: MTLRenderPipelineState
    private let adjustPhotoPipeline: MTLRenderPipelineState
    private var lookupTextures: [Effect: MTLTexture] = [:]
    private var channelTextures: [Effect: MTLTexture] = [:]
    /// Marks where the canvas is, for keeping blurred edges opaque.
    private let coveragePipeline: MTLRenderPipelineState
    private typealias BlurTarget = (blurred: MTLTexture, coverage: MTLTexture, coverageBlurred: MTLTexture)
    /// Two sets, so Adjust Photo can use a fine and a wide blur in the same frame.
    private var blurTargets: [BlurTarget] = []
    private var blurKernels: [Float: MPSImageGaussianBlur] = [:]
    /// The layers are composited here, on a transparent background, so blend modes see only the layers
    /// below and never the checkerboard. Half floats keep a deep stack from losing precision.
    private var layerTarget: MTLTexture?
    /// One layer with its unplaced objects drawn in, before it's blended.
    /// One picture per level of groups for a layer drawn on its own (stage 25), and per level a group's own picture and
    /// a copy of its backdrop.
    private var isolatedTargets: [Int: MTLTexture] = [:]
    private var groupTargets: [Int: MTLTexture] = [:]
    private static let layerTargetFormat = MTLPixelFormat.rgba16Float
    private let nearestSampler: MTLSamplerState
    private let linearSampler: MTLSamplerState
    private let maskSampler: MTLSamplerState
    /// Bound as the layer mask when there's none, so every draw has one (texture 10).
    private let noMask: MTLTexture
    private var pixelTextures: [ObjectIdentifier: PixelTexture] = [:]
    private var maskTexture: (revision: UInt64, texture: MTLTexture)?

    private struct PixelTexture {
        let buffer: PixelBuffer
        /// History frees an old layer's memory and later writes it back into new pages, so the wrap is redone.
        let generation: Int
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

        func pipeline(fragment: String, vertex: String = "quad_vertex", blended: Bool = true, format: MTLPixelFormat = .bgra8Unorm) -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: vertex)
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            let attachment = descriptor.colorAttachments[0]!
            attachment.pixelFormat = format
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
        shadowPipeline = pipeline(fragment: "shadow_fragment")
        antsPipeline = pipeline(fragment: "ants_fragment")
        tintPipeline = pipeline(fragment: "tint_fragment")
        gridPipeline = pipeline(fragment: "grid_fragment", blended: false)
        solidPipeline = pipeline(fragment: "solid_fragment")
        linePipeline = pipeline(fragment: "solid_fragment", vertex: "line_vertex")
        discPipeline = pipeline(fragment: "disc_fragment")
        blendLayerPipeline = pipeline(fragment: "blend_layer_fragment", blended: false, format: Self.layerTargetFormat)
        blendIsolatedPipeline = pipeline(fragment: "blend_isolated_fragment", blended: false, format: Self.layerTargetFormat)
        fadeBackdropPipeline = pipeline(fragment: "fade_backdrop_fragment", blended: false, format: Self.layerTargetFormat)
        compositePipeline = pipeline(fragment: "composite_fragment")
        maskAlonePipeline = pipeline(fragment: "mask_alone_fragment", blended: false, format: Self.layerTargetFormat)
        adjustPointPipeline = pipeline(fragment: "adjust_point_fragment", blended: false, format: Self.layerTargetFormat)
        adjustBlurPipeline = pipeline(fragment: "adjust_blur_fragment", blended: false, format: Self.layerTargetFormat)
        adjustLookupPipeline = pipeline(fragment: "adjust_lookup_fragment", blended: false, format: Self.layerTargetFormat)
        adjustChannelPipeline = pipeline(fragment: "adjust_channel_fragment", blended: false, format: Self.layerTargetFormat)
        adjustPhotoPipeline = pipeline(fragment: "adjust_photo_fragment", blended: false, format: Self.layerTargetFormat)
        coveragePipeline = pipeline(fragment: "solid_fragment", blended: false, format: .r16Float)

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
        let blank = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false)
        guard let noMask = device.makeTexture(descriptor: blank) else { fatalError("Couldn't create the empty mask texture") }
        self.noMask = noMask
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
        // Paint on a layer that locks its transparency is taken back out of its clear area before it's ever shown.
        scene.canvas.keepLockedTransparency()
        guard let drawable = metalLayer.nextDrawable(),
              let commandBuffer = queue.makeCommandBuffer(),
              encode(scene, into: drawable.texture, scale: scale, surround: surround, commandBuffer: commandBuffer) else { return }
        commandBuffer.addCompletedHandler { _ in
            onRendered(CACurrentMediaTime())
        }
        drawable.addPresentedHandler { presented in
            onPresented(presented.presentedTime)
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// The scene drawn into a picture of `size` device pixels instead of a window, exactly as the screen would show
    /// it, so tests can check the screen against an export.
    func renderedPixels(_ scene: RenderScene, size: IntSize, scale: Double = 1, surround: MTLClearColor) -> PixelBuffer? {
        scene.canvas.keepLockedTransparency()
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: size.width, height: size.height, mipmapped: false)
        descriptor.usage = .renderTarget
        descriptor.storageMode = .shared
        guard let target = device.makeTexture(descriptor: descriptor),
              let commandBuffer = queue.makeCommandBuffer(),
              encode(scene, into: target, scale: scale, surround: surround, commandBuffer: commandBuffer) else { return nil }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        let pixels = PixelBuffer(width: size.width, height: size.height)
        target.getBytes(pixels.baseAddress, bytesPerRow: pixels.bytesPerRow, from: MTLRegionMake2D(0, 0, size.width, size.height), mipmapLevel: 0)
        return pixels
    }

    /// Encodes the whole frame into `output`. False if the GPU couldn't go on.
    private func encode(_ scene: RenderScene, into output: MTLTexture, scale: Double, surround: MTLClearColor, commandBuffer: MTLCommandBuffer) -> Bool {
        let drawableSize = CGSize(width: output.width, height: output.height)
        let layerPass = MTLRenderPassDescriptor()
        layerPass.colorAttachments[0].texture = layerTarget(width: output.width, height: output.height)
        layerPass.colorAttachments[0].loadAction = .clear
        layerPass.colorAttachments[0].storeAction = .store
        layerPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard var encoder = commandBuffer.makeRenderCommandEncoder(descriptor: layerPass) else { return false }

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
        uniforms.viewportSize = SIMD2(Float(drawableSize.width), Float(drawableSize.height))
        uniforms.checkerSize = Float(8 * scale)
        uniforms.pixelSize = Float(zoom * scale)
        uniforms.antsPhase = scene.antsPhase
        uniforms.rect = deviceRect(canvas.bounds)
        uniforms.imageSize = SIMD2(Float(canvas.size.width), Float(canvas.size.height))

        // The layer mask the next draws use (stage 27); nil for none. Not `maskTexture`, the selection outline's cache,
        // which it once hid, so the outline's texture was never let go (review Z, finding 6).
        var layerMaskTexture: MTLTexture?
        func draw(_ pipeline: MTLRenderPipelineState) {
            encoder.setFragmentTexture(layerMaskTexture ?? noMask, index: 10)
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<QuadUniforms>.stride, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<QuadUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        /// A soft shadow under `uniforms.rect`, falling slightly downward. Leaves the uniforms as they were.
        func drawShadow() {
            let saved = uniforms
            let reach = Float(10 * scale), drop = Float(2 * scale)
            uniforms.adjustParams = uniforms.rect + SIMD4(0, drop, 0, 0)
            uniforms.photoParams.x = reach
            uniforms.keyColor = SIMD4(0, 0, 0, 0.22)
            uniforms.rect += SIMD4(-reach, drop - reach, 2 * reach, 2 * reach)
            draw(shadowPipeline)
            uniforms = saved
        }
        /// Gives the next draws `mask` as their layer mask, or none.
        func masking(_ mask: PixelBuffer?) {
            layerMaskTexture = mask.map { texture(for: $0, live: &liveBuffers) }
            uniforms.maskParams.x = mask == nil ? 0 : 1
        }
        func sampling(_ smooth: Bool) {
            encoder.setFragmentSamplerState(smooth ? linearSampler : nearestSampler, index: 0)
            uniforms.smooth = smooth ? 1 : 0
        }

        var liveBuffers = Set<ObjectIdentifier>()
        // Layers, and pixels pasted or moved past the edge, only show on the canvas itself.
        let canvasScissor: MTLScissorRect = {
            let rect = deviceRect(canvas.bounds)
            let width = Double(layerPass.colorAttachments[0].texture!.width), height = Double(layerPass.colorAttachments[0].texture!.height)
            let minX = min(max(0, Double(rect.x).rounded(.down)), width), minY = min(max(0, Double(rect.y).rounded(.down)), height)
            let maxX = min(max(minX, Double(rect.x + rect.z).rounded(.up)), width), maxY = min(max(minY, Double(rect.y + rect.w).rounded(.up)), height)
            return MTLScissorRect(x: Int(minX), y: Int(minY), width: Int(maxX - minX), height: Int(maxY - minY))
        }()
        encoder.setScissorRect(canvasScissor)
        sampling(zoom < 1)
        let floating = canvas.selection.floating
        /// Draws an adjustment layer onto `target`, changing what's drawn there so far: the image, or (for a clipped
        /// adjustment) its layer drawn on its own. False if the GPU couldn't go on.
        func drawAdjustment(_ layer: Layer, _ adjustment: Effect, onto target: MTLTexture) -> Bool {
            uniforms.opacity = Float(layer.opacity)
            uniforms.rect = deviceRect(canvas.bounds)
            uniforms.keyEnabled = 0
            let (kind, params) = Self.adjustmentUniforms(adjustment)
            uniforms.adjustKind = kind
            uniforms.adjustParams = params
            uniforms.blendMode = Float(layer.blendMode.rawValue)
            masking(layer.activeMask)
            defer { masking(nil) }
            if case .photo(let edit) = adjustment, let lookup = lookupTexture(for: adjustment) {
                // Detail sliders need blurred copies of what's below: pause the layer pass, blur, resume.
                let amounts = DetailAmounts(edit)
                let fine = amounts.needsFine, wide = amounts.needsWide, medium = amounts.needsMedium
                // Sharpness at its own radius gets slot 3, made only when needed; otherwise it reads the fine blur.
                let sharpSlot = amounts.needsSharpenBlur ? 3 : 0
                let canvasRect = uniforms.rect
                let source = target
                if fine || medium || wide || amounts.needsSharpenBlur {
                    encoder.endEncoding()
                    if fine { blur(source, canvasRect: canvasRect, sigma: Float(PhotoAdjustments.fineRadius * zoom * scale), slot: 0, commandBuffer: commandBuffer) }
                    if wide { blur(source, canvasRect: canvasRect, sigma: Float(PhotoAdjustments.definitionRadius * zoom * scale), slot: 1, commandBuffer: commandBuffer) }
                    if medium { blur(source, canvasRect: canvasRect, sigma: Float(PhotoAdjustments.textureRadius * zoom * scale), slot: 2, commandBuffer: commandBuffer) }
                    if amounts.needsSharpenBlur {
                        blur(source, canvasRect: canvasRect, sigma: Float(amounts.radius * zoom * scale), slot: 3, commandBuffer: commandBuffer)
                    }
                    guard startPass(on: source) else { return false }
                }
                let targets = preparedBlurTargets(width: source.width, height: source.height, count: sharpSlot + 1)
                encoder.setFragmentTexture(lookup, index: 0)
                encoder.setFragmentTexture(targets[0].blurred, index: 1)
                encoder.setFragmentTexture(targets[0].coverageBlurred, index: 2)
                encoder.setFragmentTexture(targets[1].blurred, index: 3)
                encoder.setFragmentTexture(targets[1].coverageBlurred, index: 4)
                encoder.setFragmentTexture(targets[2].blurred, index: 5)
                encoder.setFragmentTexture(targets[2].coverageBlurred, index: 6)
                encoder.setFragmentTexture(targets[sharpSlot].blurred, index: 7)
                encoder.setFragmentTexture(targets[sharpSlot].coverageBlurred, index: 8)
                uniforms.rect = canvasRect
                uniforms.adjustParams = SIMD4(Float(lookup.width), Float(amounts.sharpness), Float(amounts.definition), Float(amounts.noiseReduction))
                uniforms.detailParams = SIMD4(Float(amounts.color), Float(amounts.luminanceScale), Float(amounts.colorScale), Float(amounts.haloDamping))
                uniforms.detailParams2 = SIMD4(Float(amounts.fineBoost), Float(amounts.maskThreshold), amounts.showsMask ? 1 : 0, 0)
                // The filter's vignettes, then the panel's own, then the grains, as Effects.photoAdjusted applies them.
                // A buffer can't be empty, and setFragmentBytes takes at most 4 KB.
                let vignettes = edit.vignettes.prefix(128).map { SIMD4(Float($0.amount), Float($0.midpoint), Float($0.roundness), Float($0.feather)) }
                let grains = edit.grains.prefix(128).map { SIMD4(Float($0.amount), Float($0.size), Float($0.roughness), 0) }
                var effects = vignettes + grains
                uniforms.photoParams = SIMD4(Float(vignettes.count), Float(amounts.texture), Float(grains.count), 0)
                uniforms.imageSize = SIMD2(Float(canvas.size.width), Float(canvas.size.height))
                if effects.isEmpty { effects = [.zero] }
                encoder.setFragmentBytes(effects, length: effects.count * MemoryLayout<SIMD4<Float>>.stride, index: 1)
                draw(adjustPhotoPipeline)
            } else if let table = channelTexture(for: adjustment) {
                encoder.setFragmentTexture(table, index: 0)
                draw(adjustChannelPipeline)
            } else if let lookup = lookupTexture(for: adjustment) {
                uniforms.adjustParams = SIMD4(Float(lookup.width), 0, 0, 0)
                encoder.setFragmentTexture(lookup, index: 0)
                draw(adjustLookupPipeline)
            } else if kind >= 5 {
                // Blur and Sharpen need the neighbors of each pixel: pause the layer pass, blur on the GPU, resume.
                encoder.endEncoding()
                let radius = kind == 5 ? Double(params.x) : 1
                let canvasRect = uniforms.rect
                blur(target, canvasRect: canvasRect, sigma: Float(radius * zoom * scale), slot: 0, commandBuffer: commandBuffer)
                guard startPass(on: target), let targets = blurTargets.first else { return false }
                encoder.setFragmentTexture(targets.blurred, index: 0)
                encoder.setFragmentTexture(targets.coverageBlurred, index: 1)
                uniforms.rect = canvasRect
                draw(adjustBlurPipeline)
            } else {
                draw(adjustPointPipeline)
            }
            uniforms.adjustKind = 0
            return true
        }

        /// Ends the current pass and starts one drawing on over `texture`, cleared first if asked.
        func resume(_ texture: MTLTexture, clearing: Bool = false) -> Bool {
            encoder.endEncoding()
            return startPass(on: texture, clearing: clearing)
        }
        /// Starts a pass drawing on over `texture`, cleared first if asked, once the last one has ended. Every pass
        /// keeps to the canvas and samples as the zoom asks.
        func startPass(on texture: MTLTexture, clearing: Bool = false) -> Bool {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texture
            pass.colorAttachments[0].loadAction = clearing ? .clear : .load
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            guard let resumed = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return false }
            encoder = resumed
            encoder.setScissorRect(canvasScissor)
            sampling(zoom < 1)
            return true
        }
        /// A group (stage 25): Pass Through draws its layers straight onto what's below, faded in by its opacity from a
        /// copy of the backdrop; any other draws them into a picture of their own, then blends that in, as
        /// `Canvas.composite` does. Each level of groups has its own pictures.
        func drawGroup(_ node: LayerNode, onto target: MTLTexture, depth: Int) -> Bool {
            let group = node.layer
            if group.passesThrough, group.opacity >= 1, group.activeMask == nil { return drawNodes(node.children, onto: target, depth: depth + 1) }
            let width = output.width, height = output.height
            if group.passesThrough {
                let backdrop = groupTarget(depth: depth, backdrop: true, width: width, height: height)
                encoder.endEncoding()
                guard let blit = commandBuffer.makeBlitCommandEncoder() else { return false }
                blit.copy(from: target, to: backdrop)
                blit.endEncoding()
                guard startPass(on: target), drawNodes(node.children, onto: target, depth: depth + 1) else { return false }
                uniforms.rect = deviceRect(canvas.bounds)
                uniforms.opacity = Float(group.opacity)
                encoder.setFragmentTexture(backdrop, index: 0)
                masking(group.activeMask)
                draw(fadeBackdropPipeline)
                masking(nil)
                return true
            }
            let inside = groupTarget(depth: depth, backdrop: false, width: width, height: height)
            guard resume(inside, clearing: true), drawNodes(node.children, onto: inside, depth: depth + 1) else { return false }
            return blendBack(inside, as: group, onto: target)
        }
        /// Blends `picture`, drawn on its own, onto `target` with `layer`'s blend mode, opacity and mask.
        func blendBack(_ picture: MTLTexture, as layer: Layer, onto target: MTLTexture) -> Bool {
            guard resume(target) else { return false }
            uniforms.rect = deviceRect(canvas.bounds)
            uniforms.keyEnabled = 0
            uniforms.blendMode = Float(layer.blendMode.rawValue)
            uniforms.opacity = Float(layer.opacity)
            encoder.setFragmentTexture(picture, index: 0)
            masking(layer.activeMask)
            draw(blendIsolatedPipeline)
            masking(nil)
            return true
        }
        /// Draws `nodes` onto `target`, which the encoder is drawing into. False if the GPU couldn't go on.
        func drawNodes(_ nodes: [LayerNode], onto target: MTLTexture, depth: Int) -> Bool {
            for node in nodes {
                let layer = node.layer
                // A clipped adjustment is drawn with the layer it changes, or not at all when there's none.
                if layer.clipsToLayerBelow, canvas.clipBaseIndex(forLayerAt: canvas.layers.firstIndex { $0 === layer } ?? 0) != nil { continue }
                if layer.isGroup {
                    guard drawGroup(node, onto: target, depth: depth) else { return false }
                    continue
                }
                let index = canvas.layers.firstIndex { $0 === layer } ?? 0
                uniforms.opacity = Float(layer.opacity)
                uniforms.rect = deviceRect(canvas.bounds)
                uniforms.keyEnabled = 0
                if let adjustment = layer.adjustment {
                    guard drawAdjustment(layer, adjustment, onto: target) else { return false }
                    continue
                }
                let overlay = layer.id == canvas.activeLayer.id ? scene.overlay : nil
                let hasFloating = floating?.layerID == layer.id
                // On a layer that locks its transparency it shows clipped to the layer's shape, as placing will leave it.
                let lockedPatch = hasFloating && canvas.locksTransparency(layer)
                    ? floating?.placedPatch(on: layer, resampling: scene.smoothFloating ? .smooth : .nearestNeighbor, transparentKey: scene.transparentKey)
                    : nil
                // A shape or text not yet placed likewise shows only where the lock will keep it.
                // Not for a text layer being edited: placing redraws it whole (review Y, finding 7).
                let lockedOverlay = canvas.locksTransparency(layer) && layer.id != scene.replacedLayer ? overlay.flatMap { Compositing.lockedPatch(of: layer, under: $0.pixels, at: $0.origin) } : nil
                // Objects not yet placed go into their layer before it's blended, so on a layer that isn't Normal
                // at 100% they look as they will once placed (Leah; review F, finding 1).
                // Its clipped adjustments change it alone, so it's drawn on its own first, then blended in.
                let clips = canvas.clippedLayers(onLayerAt: index).filter { $0.isVisible && $0.opacity > 0 }
                // A mask covers the layer with whatever is drawn into it, so a masked layer is drawn on its own too.
                let isolated = ((hasFloating || overlay != nil) && (layer.blendMode != .normal || layer.opacity < 1)) || !clips.isEmpty
                    || layer.activeMask != nil
                    || lockedPatch != nil || lockedOverlay != nil
                // Made only when needed: it's the size of the window.
                let isolatedTexture = isolated ? isolatedTarget(depth: depth, width: output.width, height: output.height) : nil
                if let isolatedTexture {
                    guard resume(isolatedTexture, clearing: true) else { return false }
                    uniforms.opacity = 1
                }
                uniforms.blendMode = isolated ? 0 : Float(layer.blendMode.rawValue)
                if layer.id != scene.replacedLayer {
                    encoder.setFragmentTexture(texture(for: layer.buffer, live: &liveBuffers), index: 0)
                    draw(blendLayerPipeline)
                }

                if let lockedPatch {
                    uniforms.rect = deviceRect(lockedPatch.area)
                    uniforms.blendMode = -1
                    encoder.setFragmentTexture(texture(for: lockedPatch.pixels, live: &liveBuffers), index: 0)
                    draw(blendLayerPipeline)
                    uniforms.blendMode = 0
                } else if let floating, hasFloating {
                    uniforms.rect = deviceRect(floating.destination)
                    let stretched = floating.destination.size != floating.pixels.size
                    sampling(stretched && scene.smoothFloating)
                    if let key = scene.transparentKey {
                        uniforms.keyEnabled = 1
                        uniforms.keyColor = SIMD4(Float(key.r) / 255, Float(key.g) / 255, Float(key.b) / 255, 1)
                    }
                    encoder.setFragmentTexture(texture(for: floating.pixels, live: &liveBuffers), index: 0)
                    draw(blendLayerPipeline)
                    sampling(zoom < 1)
                }
                if let lockedOverlay {
                    uniforms.rect = deviceRect(lockedOverlay.area)
                    uniforms.keyEnabled = 0
                    uniforms.blendMode = -1
                    encoder.setFragmentTexture(texture(for: lockedOverlay.pixels, live: &liveBuffers), index: 0)
                    draw(blendLayerPipeline)
                    uniforms.blendMode = 0
                } else if let overlay {
                    uniforms.rect = deviceRect(IntRect(x: overlay.origin.x, y: overlay.origin.y, width: overlay.pixels.width, height: overlay.pixels.height))
                    uniforms.keyEnabled = 0
                    uniforms.blendMode = 0
                    encoder.setFragmentTexture(texture(for: overlay.pixels, live: &liveBuffers), index: 0)
                    draw(blendLayerPipeline)
                }
                if isolated {
                    for clip in clips {
                        if let adjustment = clip.adjustment {
                            guard let isolatedTexture, drawAdjustment(clip, adjustment, onto: isolatedTexture) else { return false }
                            continue
                        }
                        // A pixel layer set to "Only the layer below" (stage 28b): onto this one only where it has pixels.
                        uniforms.rect = deviceRect(canvas.bounds)
                        uniforms.keyEnabled = 0
                        uniforms.opacity = Float(clip.opacity)
                        uniforms.blendMode = Float(clip.blendMode.rawValue)
                        uniforms.maskParams.y = 1
                        encoder.setFragmentTexture(texture(for: clip.buffer, live: &liveBuffers), index: 0)
                        masking(clip.activeMask)
                        draw(blendLayerPipeline)
                        masking(nil)
                        uniforms.maskParams.y = 0
                    }
                    guard let isolatedTexture, blendBack(isolatedTexture, as: layer, onto: target) else { return false }
                }
            }
            return true
        }

        guard drawNodes(canvas.tree(of: canvas.shownLayers), onto: layerPass.colorAttachments[0].texture!, depth: 0) else { return false }
        if let mask = scene.maskAlone {
            uniforms.rect = deviceRect(canvas.bounds)
            sampling(zoom < 1)
            encoder.setFragmentTexture(texture(for: mask, live: &liveBuffers), index: 0)
            draw(maskAlonePipeline)
        }
        uniforms.blendMode = 0
        uniforms.opacity = 1
        uniforms.keyEnabled = 0
        for top in [scene.aboveLayers, scene.topOverlay].compactMap({ $0 }) {
            uniforms.rect = deviceRect(IntRect(x: top.origin.x, y: top.origin.y, width: top.pixels.width, height: top.pixels.height))
            sampling(zoom < 1)
            encoder.setFragmentTexture(texture(for: top.pixels, live: &liveBuffers), index: 0)
            draw(blendLayerPipeline)
        }
        encoder.endEncoding()

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = surround
        guard let mainEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return false }
        encoder = mainEncoder
        uniforms.rect = deviceRect(canvas.bounds)
        drawShadow()
        draw(checkerPipeline)
        if let comparison = scene.comparison, comparison.layout == .sideBySide {
            let before = comparison.before
            let beforeOrigin = scene.viewport.viewPoint(fromImage: .zero)
            uniforms.rect = SIMD4(
                Float((beforeOrigin.x * scale).rounded()), Float((beforeOrigin.y * scale).rounded()),
                Float(Double(before.width) * zoom * scale), Float(Double(before.height) * zoom * scale)
            )
            draw(checkerPipeline)
            sampling(zoom < 1)
            encoder.setFragmentTexture(texture(for: before, live: &liveBuffers), index: 0)
            draw(layerPipeline)
            uniforms.rect = deviceRect(canvas.bounds)
        }
        uniforms.rect = SIMD4(0, 0, uniforms.viewportSize.x, uniforms.viewportSize.y)
        sampling(false)
        encoder.setFragmentTexture(layerPass.colorAttachments[0].texture, index: 0)
        uniforms.clipWarnings = (scene.clipsHighlights ? 1 : 0) + (scene.clipsShadows ? 2 : 0)
        draw(compositePipeline)
        uniforms.clipWarnings = 0
        uniforms.rect = deviceRect(canvas.bounds)

        if let comparison = scene.comparison, comparison.layout == .split {
            // Left of the divider shows "before", drawn over the current image.
            let dividerDevice = max(0, min(Double(drawableSize.width), comparison.dividerX * scale))
            if dividerDevice > 0 {
                encoder.setScissorRect(MTLScissorRect(x: 0, y: 0, width: Int(dividerDevice), height: Int(drawableSize.height)))
                uniforms.rect = deviceRect(IntRect(size: comparison.before.size))
                uniforms.opacity = 1
                uniforms.keyEnabled = 0
                sampling(zoom < 1)
                encoder.setFragmentTexture(texture(for: comparison.before, live: &liveBuffers), index: 0)
                draw(checkerPipeline)
                draw(layerPipeline)
                encoder.setScissorRect(MTLScissorRect(x: 0, y: 0, width: Int(drawableSize.width), height: Int(drawableSize.height)))
            }
            let lineWidth = Float(2 * scale)
            uniforms.rect = SIMD4(Float(dividerDevice) - lineWidth / 2, 0, lineWidth, Float(drawableSize.height))
            uniforms.keyColor = SIMD4(1, 1, 1, 1)
            draw(solidPipeline)
        }
        pixelTextures = pixelTextures.filter { liveBuffers.contains($0.key) }

        if let outline = scene.outline, scene.tintsOutsideSelection {
            uniforms.rect = deviceRect(canvas.bounds)
            uniforms.adjustParams = SIMD4(Float(outline.rect.minX), Float(outline.rect.minY), Float(outline.rect.width), Float(outline.rect.height))
            encoder.setFragmentSamplerState(maskSampler, index: 0)
            encoder.setFragmentTexture(texture(for: outline.mask), index: 0)
            draw(tintPipeline)
        }
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

        for line in scene.lines {
            uniforms.rect = SIMD4(
                Float(originX + line.from.x * zoom * scale), Float(originY + line.from.y * zoom * scale),
                Float(originX + line.to.x * zoom * scale), Float(originY + line.to.y * zoom * scale)
            )
            uniforms.pixelSize = Float(1.5 * scale)
            uniforms.keyColor = line.color
            draw(linePipeline)
        }
        uniforms.pixelSize = Float(zoom * scale)

        for highlight in scene.highlights {
            let rect = deviceRect(highlight.rect)
            let line = Float(2 * scale)
            uniforms.keyColor = highlight.active ? SIMD4(1, 0.55, 0, 1) : SIMD4(0.55, 0.55, 0.55, 1)
            for edge in [
                SIMD4(rect.x, rect.y, rect.z, line),
                SIMD4(rect.x, rect.y + rect.w - line, rect.z, line),
                SIMD4(rect.x, rect.y, line, rect.w),
                SIMD4(rect.x + rect.z - line, rect.y, line, rect.w),
            ] {
                uniforms.rect = edge
                draw(solidPipeline)
            }
        }

        for point in scene.roundHandlePoints {
            let centerX = Float(originX + point.x * zoom * scale)
            let centerY = Float(originY + point.y * zoom * scale)
            for (size, shade) in [(Float(11 * scale), Float(0.15)), (Float(8 * scale), Float(1))] {
                uniforms.rect = SIMD4(centerX - size / 2, centerY - size / 2, size, size)
                uniforms.keyColor = SIMD4(shade, shade, shade, 1)
                draw(discPipeline)
            }
        }

        if let keep = scene.dimmedOutside {
            let whole = scene.canvas.bounds
            let parts = [
                IntRect(x: whole.minX, y: whole.minY, width: whole.width, height: keep.minY - whole.minY),
                IntRect(x: whole.minX, y: keep.maxY, width: whole.width, height: whole.maxY - keep.maxY),
                IntRect(x: whole.minX, y: keep.minY, width: keep.minX - whole.minX, height: keep.height),
                IntRect(x: keep.maxX, y: keep.minY, width: whole.maxX - keep.maxX, height: keep.height),
            ]
            for part in parts where part.width > 0 && part.height > 0 {
                uniforms.rect = deviceRect(part)
                uniforms.keyColor = SIMD4(0, 0, 0, 0.5)
                draw(solidPipeline)
            }
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
        return true
    }

    /// An adjustment's kind code and settings for the shaders.
    private static func adjustmentUniforms(_ effect: Effect) -> (Float, SIMD4<Float>) {
        switch effect {
        case .invert: (1, .zero)
        case .desaturate: (2, .zero)
        case .brightnessContrast(let brightness, let contrast): (3, SIMD4(Float(brightness), Float(contrast), 0, 0))
        case .hueSaturation(let hue, let saturation, let lightness): (4, SIMD4(Float(hue), Float(saturation), Float(lightness), 0))
        case .gaussianBlur(let radius): (5, SIMD4(Float(radius), 0, 0, 0))
        case .sharpen(let amount): (6, SIMD4(Float(amount), 0, 0, 0))
        default: (0, .zero)
        }
    }

    /// The 3D table for a color adjustment layer, made once per setting. A slider drag makes a new one
    /// each step, so only the most recent few are kept.
    private func lookupTexture(for effect: Effect) -> MTLTexture? {
        if let cached = lookupTextures[effect] { return cached }
        guard let lookup = ColorLookup(effect) else { return nil }
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .rgba32Float
        descriptor.width = lookup.size
        descriptor.height = lookup.size
        descriptor.depth = lookup.size
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        lookup.values.withUnsafeBytes { bytes in
            let rowBytes = lookup.size * 4 * MemoryLayout<Float>.stride
            texture.replace(region: MTLRegionMake3D(0, 0, 0, lookup.size, lookup.size, lookup.size), mipmapLevel: 0, slice: 0,
                            withBytes: bytes.baseAddress!, bytesPerRow: rowBytes, bytesPerImage: rowBytes * lookup.size)
        }
        if lookupTextures.count >= 8 { lookupTextures.removeAll() }
        lookupTextures[effect] = texture
        return texture
    }

    /// The 256-entry table for Levels, Curves or Posterize, made once per setting; like the 3D tables, only
    /// the most recent few are kept.
    private func channelTexture(for effect: Effect) -> MTLTexture? {
        if let cached = channelTextures[effect] { return cached }
        guard let table = ChannelTable(effect) else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 256, height: 1, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        table.values.withUnsafeBytes { bytes in
            texture.replace(region: MTLRegionMake2D(0, 0, 256, 1), mipmapLevel: 0, withBytes: bytes.baseAddress!, bytesPerRow: 256 * 4)
        }
        if channelTextures.count >= 8 { channelTextures.removeAll() }
        channelTextures[effect] = texture
        return texture
    }

    /// At least `count` blur target sets at the drawable's size (three, or four for Sharpness at its own radius), made
    /// when needed.
    private func preparedBlurTargets(width: Int, height: Int, count: Int = 3) -> [BlurTarget] {
        let count = max(count, 3)
        // A new size remakes them; more slots only add to the list, so blurs already made this frame stay (review V,
        // finding 7).
        if let first = blurTargets.first, first.blurred.width != width || first.blurred.height != height { blurTargets = [] }
        guard blurTargets.count < count else { return blurTargets }
        func make(_ format: MTLPixelFormat, renderTarget: Bool) -> MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
            descriptor.usage = renderTarget ? [.renderTarget, .shaderRead] : [.shaderRead, .shaderWrite]
            descriptor.storageMode = .private
            guard let texture = device.makeTexture(descriptor: descriptor) else { fatalError("Couldn't create a blur texture") }
            return texture
        }
        blurTargets += (blurTargets.count..<count).map { _ in (make(Self.layerTargetFormat, renderTarget: false), make(.r16Float, renderTarget: true), make(.r16Float, renderTarget: false)) }
        return blurTargets
    }

    /// Blurs the layers composited so far into one blur target set, and the canvas's coverage alongside.
    private func blur(_ source: MTLTexture, canvasRect: SIMD4<Float>, sigma: Float, slot: Int, commandBuffer: MTLCommandBuffer) {
        let width = source.width, height = source.height
        let targets = preparedBlurTargets(width: width, height: height, count: slot + 1)[slot]

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = targets.coverage
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) {
            var uniforms = QuadUniforms()
            uniforms.viewportSize = SIMD2(Float(width), Float(height))
            uniforms.rect = canvasRect
            uniforms.keyColor = SIMD4(1, 1, 1, 1)
            encoder.setRenderPipelineState(coveragePipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<QuadUniforms>.stride, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<QuadUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
        }
        // Below about a third of a screen pixel the blur is invisible; skip the work.
        let sigma = max(0.35, sigma)
        let kernel = blurKernels[sigma] ?? {
            let made = MPSImageGaussianBlur(device: device, sigma: sigma)
            made.edgeMode = .zero
            if blurKernels.count > 8 { blurKernels.removeAll() }
            blurKernels[sigma] = made
            return made
        }()
        kernel.encode(commandBuffer: commandBuffer, sourceTexture: source, destinationTexture: targets.blurred)
        kernel.encode(commandBuffer: commandBuffer, sourceTexture: targets.coverage, destinationTexture: targets.coverageBlurred)
    }

    private func isolatedTarget(depth: Int, width: Int, height: Int) -> MTLTexture {
        if let target = isolatedTargets[depth], target.width == width, target.height == height { return target }
        let texture = makeLayerTarget(width: width, height: height)
        isolatedTargets[depth] = texture
        return texture
    }

    /// A group's own picture at `depth`, or the copy of what's below a Pass Through group there (`backdrop`).
    private func groupTarget(depth: Int, backdrop: Bool, width: Int, height: Int) -> MTLTexture {
        let key = depth * 2 + (backdrop ? 1 : 0)
        if let target = groupTargets[key], target.width == width, target.height == height { return target }
        let texture = makeLayerTarget(width: width, height: height)
        groupTargets[key] = texture
        return texture
    }

    private func makeLayerTarget(width: Int, height: Int) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.layerTargetFormat, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else { fatalError("Couldn't create a layer target") }
        return texture
    }

    private func layerTarget(width: Int, height: Int) -> MTLTexture {
        if let layerTarget, layerTarget.width == width, layerTarget.height == height { return layerTarget }
        let texture = makeLayerTarget(width: width, height: height)
        layerTarget = texture
        return texture
    }

    private func texture(for buffer: PixelBuffer, live: inout Set<ObjectIdentifier>) -> MTLTexture {
        let key = ObjectIdentifier(buffer)
        live.insert(key)
        if let cached = pixelTextures[key], cached.generation == buffer.generation { return cached.texture }

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
        pixelTextures[key] = PixelTexture(buffer: buffer, generation: buffer.generation, metalBuffer: metalBuffer, texture: texture)
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
