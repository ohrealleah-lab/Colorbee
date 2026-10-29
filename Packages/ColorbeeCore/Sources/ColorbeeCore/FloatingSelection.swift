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
                // A half-selected pixel is lifted halfway: half comes along, half stays (FR-3.4).
                let amount = selection[x, y]
                destination[x - area.minX] = source[x].taking(amount)
                maskValues[(y - area.minY) * area.width + (x - area.minX)] = amount
                if let holeFill { source[x] = source[x].vacated(by: amount, fill: holeFill) }
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

    /// Composites the pixels onto their layer at the current destination. On a layer that locks its transparency,
    /// each pixel is placed by `placedOnLocked`, as the screen and saves show it while it floats.
    @discardableResult
    public func stamp(onto layer: Layer, edit: Edit, resampling: Resampling, transparentKey: Pixel?) -> IntRect {
        let pixels = rendered(using: resampling, transparentKey: transparentKey)
        let origin = IntPoint(x: destination.minX, y: destination.minY)
        guard layer.locksTransparency else { return Compositing.draw(pixels, at: origin, onto: layer, edit: edit) }
        let area = IntRect(x: origin.x, y: origin.y, width: pixels.width, height: pixels.height).intersection(layer.buffer.bounds)
        guard !area.isEmpty else { return .zero }
        edit.willModify(area, in: layer)
        place(pixels, at: origin, onto: layer.buffer, in: area)
        return area
    }

    /// The layer's buffer, copied, with these pixels placed on it as `stamp` would: for the screen and saves while a
    /// selection floats over a layer that locks its transparency (review U, finding 3).
    public func placedCopy(of layer: Layer, resampling: Resampling, transparentKey: Pixel?) -> PixelBuffer {
        let buffer = layer.buffer.copy()
        let pixels = rendered(using: resampling, transparentKey: transparentKey)
        let origin = IntPoint(x: destination.minX, y: destination.minY)
        let area = IntRect(x: origin.x, y: origin.y, width: pixels.width, height: pixels.height).intersection(buffer.bounds)
        if layer.locksTransparency {
            place(pixels, at: origin, onto: buffer, in: area)
        } else {
            for y in area.minY..<area.maxY {
                let source = pixels.row(y - origin.y), target = buffer.row(y)
                for x in area.minX..<area.maxX { target[x] = Compositing.over(target[x], source[x - origin.x]) }
            }
        }
        return buffer
    }

    /// For the screen while the selection floats over a layer that locks its transparency: that layer's pixels under
    /// the selection, with the selection placed on them as `stamp` would, and where they go. Nil when nothing overlaps.
    public func placedPatch(on layer: Layer, resampling: Resampling, transparentKey: Pixel?) -> (pixels: PixelBuffer, area: IntRect)? {
        let pixels = rendered(using: resampling, transparentKey: transparentKey)
        let origin = IntPoint(x: destination.minX, y: destination.minY)
        let area = IntRect(x: origin.x, y: origin.y, width: pixels.width, height: pixels.height).intersection(layer.buffer.bounds)
        guard !area.isEmpty else { return nil }
        let patch = PixelBuffer(width: area.width, height: area.height)
        ParallelRows.forEach(area.minY..<area.maxY) { rows in
            for y in rows {
                let source = pixels.row(y - origin.y), base = layer.buffer.row(y), target = patch.row(y - area.minY)
                for x in area.minX..<area.maxX { target[x - area.minX] = .placedOnLocked(base[x], source[x - origin.x]) }
            }
        }
        return (patch, area)
    }

    private func place(_ pixels: PixelBuffer, at origin: IntPoint, onto buffer: PixelBuffer, in area: IntRect) {
        ParallelRows.forEach(area.minY..<area.maxY) { rows in
            for y in rows {
                let source = pixels.row(y - origin.y), target = buffer.row(y)
                for x in area.minX..<area.maxX { target[x] = .placedOnLocked(target[x], source[x - origin.x]) }
            }
        }
    }
}

extension Pixel {
    /// `top` placed on `base`, a pixel of a layer that locks its transparency: a clear pixel stays exactly as it is,
    /// and otherwise `top` covers `base` in proportion to how much of `base`'s opacity it fills, which stays. So a
    /// soft edge lifted and put back where it was comes back exactly (review U, finding 3).
    static func placedOnLocked(_ base: Pixel, _ top: Pixel) -> Pixel {
        guard base.a > 0, top.a > 0 else { return base }
        let weight = min(1, Double(top.a) / Double(base.a))
        func mix(_ b: UInt8, _ t: UInt8) -> UInt8 { UInt8((Double(b) + (Double(t) - Double(b)) * weight).rounded()) }
        return Pixel(r: mix(base.r, top.r), g: mix(base.g, top.g), b: mix(base.b, top.b), a: base.a)
    }

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

extension Pixel {
    /// The part of this pixel that's `amount` (0...255) selected, for copying or lifting: its alpha scaled.
    func taking(_ amount: UInt8) -> Pixel {
        amount == 255 ? self : Pixel(r: r, g: g, b: b, a: UInt8((Int(a) * Int(amount) + 127) / 255))
    }

    /// What's left when the `amount`-selected part is removed: `fill` where fully selected; partly selected, mixed
    /// towards it, or (for a transparent fill) its alpha reduced so its color stays.
    func vacated(by amount: UInt8, fill: Pixel) -> Pixel {
        if amount == 255 { return fill }
        if fill.a == 0 { return Pixel(r: r, g: g, b: b, a: UInt8((Int(a) * (255 - Int(amount)) + 127) / 255)) }
        return Compositing.lerp(self, fill, Float(amount) / 255)
    }
}
