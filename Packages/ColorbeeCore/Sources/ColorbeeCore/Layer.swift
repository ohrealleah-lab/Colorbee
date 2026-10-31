import Foundation

public struct LayerID: Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public final class Layer {
    public let id: LayerID
    public var name: String
    public var isVisible: Bool
    public var opacity: Double
    public var blendMode: BlendMode = .normal
    /// A locked layer refuses every pixel change, move, merge and delete (FR-8.2).
    public var isLocked = false
    /// Lock Transparent Pixels (FR-8.2, stage 23): its pixels can be recolored, but where it's clear stays clear and
    /// every pixel keeps its opacity, so a cutout or shape keeps its outline. See `Edit.keepLockedTransparency`.
    public var locksTransparency = false
    /// Set for an adjustment layer (FR-8.4): it changes how the layers below look and holds no pixels.
    public var adjustment: Effect?
    /// For an adjustment layer: it changes only the pixel layer it sits on, not everything below (a clipping mask;
    /// Leah, 2026-10-10). See `Canvas.clipBaseIndex(forLayerAt:)`.
    public var clipsToLayerBelow = false
    /// A group (FR-8.7, stage 25): a row holding no pixels. The layers in it sit just below it in `Canvas.layers` and
    /// name it as their `groupID`, so the list stays flat.
    public let isGroup: Bool
    /// The group this layer is in; nil at the top.
    public var groupID: LayerID?
    /// For a group: its layers blend with everything below as if they weren't grouped (Pass Through, the default,
    /// Q25.2). Off, they're put together on their own first and the group is blended in with its blend mode, so an
    /// adjustment inside changes only the group.
    public var passesThrough = true

    /// A layer mask (FR-8.8, stages 27 to 28b): black ink on white paper, held as a layer of its own so every tool paints
    /// on it, and history, saving and snapshots treat it as pixels. Where it's clear or white the layer shows, where
    /// it's black it's hidden, grays partly (`Compositing.reveal`). An untouched mask shows everything and takes no
    /// memory. Nil without one.
    public var mask: Layer?
    /// Shift-click on the mask turns it off without deleting it (stage 28a).
    public var maskEnabled = true
    /// The mask in force: nil when there's none or it's turned off.
    public var activeMask: PixelBuffer? { maskEnabled ? mask?.buffer : nil }

    /// A text layer (FR-6.3, stage 29): its pixels are always exactly `text` drawn, so the words can be edited again.
    /// Any pixel change turns it into plain pixels first (`Edit.willModify`), so redaction always wins.
    public var text: TextLayer?

    /// A layer with pixels of its own: not an adjustment layer or a group.
    public var isPixelLayer: Bool { adjustment == nil && !isGroup }

    /// The adjustments an adjustment layer can be.
    public static func isAdjustable(_ effect: Effect) -> Bool {
        switch effect {
        case .invert, .desaturate, .brightnessContrast, .hueSaturation, .gaussianBlur, .sharpen,
             .levels, .curves, .sepia, .posterize, .photo: true
        // A look is a layer as an Adjust Photo layer with that look as its filter.
        case .pixelate, .solidFill, .addNoise, .motionBlur, .emboss, .vignette, .look: false
        }
    }
    /// An adjustment layer, or a layer never painted on: its buffer is all clear and takes no memory,
    /// so whole-image changes give it a new empty buffer rather than touching (and filling) every page.
    var holdsNoPixels: Bool { !isPixelLayer || buffer.isUntouched }

    /// Replaced (never resized in place) when the canvas size changes.
    public internal(set) var buffer: PixelBuffer

    public init(name: String, buffer: PixelBuffer, id: LayerID = LayerID(), isGroup: Bool = false) {
        self.id = id
        self.name = name
        self.buffer = buffer
        self.isGroup = isGroup
        isVisible = true
        opacity = 1
    }

    /// A new, empty group of `size` (its buffer stays clear and takes no memory).
    public static func group(named name: String, size: IntSize, id: LayerID = LayerID()) -> Layer {
        Layer(name: name, buffer: PixelBuffer(size: size), id: id, isGroup: true)
    }

    /// A layer of the same kind, with every setting of this one, holding `buffer`. It shares this one's mask: a copy
    /// that outlives this moment gives it a mask of its own (`withOwnMask`).
    public func copy(buffer: PixelBuffer, id: LayerID? = nil, name: String? = nil) -> Layer {
        let copy = Layer(name: name ?? self.name, buffer: buffer, id: id ?? self.id, isGroup: isGroup)
        copy.takeSettings(from: self)
        copy.mask = mask
        copy.text = text
        return copy
    }

    /// Gives this layer a copy of its mask, with the same id (`newID` off) or a new one.
    @discardableResult
    func withOwnMask(newID: Bool = false) -> Layer {
        mask = mask.map { $0.copy(buffer: $0.buffer.copy(), id: newID ? LayerID() : $0.id) }
        return self
    }

    /// Every setting of `other` but its name, id, kind and pixels.
    public func takeSettings(from other: Layer) {
        isVisible = other.isVisible
        opacity = other.opacity
        blendMode = other.blendMode
        isLocked = other.isLocked
        locksTransparency = other.locksTransparency
        adjustment = other.adjustment
        clipsToLayerBelow = other.clipsToLayerBelow
        groupID = other.groupID
        passesThrough = other.passesThrough
        maskEnabled = other.maskEnabled
    }
}
