import Foundation

/// Pixels lifted off a layer (or pasted) that sit above it until they're placed.
/// The source pixels are never modified, so every move or resize is computed from the original.
public struct FloatingSelection {
    public let id: UUID
    public let layerID: LayerID
    /// Source pixels. Pixels outside `mask` are fully transparent.
    public let pixels: PixelBuffer
    /// The selected shape, in the pixels' own coordinates (bounds origin at 0,0).
    public let mask: SelectionMask
    /// Where the pixels sit on the canvas. A size different from `pixels` means they're stretched.
    public var destination: IntRect

    public init(pixels: PixelBuffer, mask: SelectionMask? = nil, destination: IntRect, layerID: LayerID, id: UUID = UUID()) {
        self.id = id
        self.layerID = layerID
        self.pixels = pixels
        self.mask = mask ?? SelectionMask(bounds: pixels.bounds, values: [UInt8](repeating: 255, count: pixels.bounds.area))
        self.destination = destination
    }

    /// Copies the pixels under `selection` off `layer`. With `holeFill`, the lifted area is filled
    /// with that color; with nil, the layer is left as it was (a duplicate).
    public static func lift(from layer: Layer, selection: SelectionMask, holeFill: Pixel?, edit: Edit) -> FloatingSelection? {
        guard let area = selection.trimmed().map({ $0.bounds.intersection(layer.buffer.bounds) }), !area.isEmpty else {
            return nil
        }
        let pixels = PixelBuffer(width: area.width, height: area.height)
        var maskValues = [UInt8](repeating: 0, count: area.area)
        if holeFill != nil {
            edit.willModify(area, in: layer)
        }
        for y in area.minY..<area.maxY {
            let source = layer.buffer.row(y)
            let destination = pixels.row(y - area.minY)
            for x in area.minX..<area.maxX where selection[x, y] > 0 {
                destination[x - area.minX] = source[x]
                maskValues[(y - area.minY) * area.width + (x - area.minX)] = 255
                if let holeFill { source[x] = holeFill }
            }
        }
        let mask = SelectionMask(bounds: IntRect(size: area.size), values: maskValues)
        return FloatingSelection(pixels: pixels, mask: mask, destination: area, layerID: layer.id)
    }

    /// The selection outline on the canvas.
    public var outline: SelectionMask? {
        mask.stretched(to: destination)
    }

    public func contains(_ point: IntPoint) -> Bool {
        guard destination.contains(point) else { return false }
        let x = (point.x - destination.minX) * mask.bounds.width / destination.width
        let y = (point.y - destination.minY) * mask.bounds.height / destination.height
        return mask[x, y] > 0
    }

    /// The pixels at their destination size, with `transparentKey` pixels made transparent.
    public func rendered(using resampling: Resampling, transparentKey: Pixel? = nil) -> PixelBuffer {
        var result = pixels.resampled(to: destination.size, using: resampling)
        if let transparentKey {
            if result === pixels { result = pixels.copy() }
            for y in 0..<result.height {
                let row = result.row(y)
                for x in 0..<result.width where row[x].matchesColor(of: transparentKey) {
                    row[x] = .clear
                }
            }
        }
        return result
    }

    /// Composites the pixels onto their layer at the current destination.
    @discardableResult
    public func stamp(onto layer: Layer, edit: Edit, resampling: Resampling, transparentKey: Pixel?) -> IntRect {
        Compositing.draw(
            rendered(using: resampling, transparentKey: transparentKey),
            at: IntPoint(x: destination.minX, y: destination.minY),
            onto: layer,
            edit: edit
        )
    }
}

extension Pixel {
    /// Same color, ignoring alpha; fully transparent pixels never match.
    func matchesColor(of other: Pixel) -> Bool {
        a > 0 && r == other.r && g == other.g && b == other.b
    }
}

/// What's selected on the canvas.
public enum SelectionState {
    case none
    case marquee(SelectionMask)
    case floating(FloatingSelection)

    public var marquee: SelectionMask? {
        if case .marquee(let mask) = self { return mask }
        return nil
    }

    public var floating: FloatingSelection? {
        if case .floating(let floating) = self { return floating }
        return nil
    }

    /// The selected area on the canvas, whether marquee or floating.
    public var outline: SelectionMask? {
        switch self {
        case .none: nil
        case .marquee(let mask): mask
        case .floating(let floating): floating.outline
        }
    }

    public var bounds: IntRect? {
        switch self {
        case .none: nil
        case .marquee(let mask): mask.bounds
        case .floating(let floating): floating.destination
        }
    }

    public var isEmpty: Bool {
        if case .none = self { return true }
        return false
    }

    public func contains(_ point: IntPoint) -> Bool {
        switch self {
        case .none: false
        case .marquee(let mask): mask.contains(point)
        case .floating(let floating): floating.contains(point)
        }
    }

    /// Whether two states are the same selection (compared by identity, not pixel content).
    func isSame(as other: SelectionState) -> Bool {
        switch (self, other) {
        case (.none, .none):
            true
        case (.marquee(let a), .marquee(let b)):
            a.revision == b.revision
        case (.floating(let a), .floating(let b)):
            a.id == b.id && a.destination == b.destination && a.pixels === b.pixels
        default:
            false
        }
    }
}
