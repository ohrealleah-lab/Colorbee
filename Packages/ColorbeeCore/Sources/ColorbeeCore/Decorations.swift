import Foundation

/// Drop Shadow settings (FR-9.5). Offsets and blur are in image pixels.
public struct DropShadow: Sendable, Hashable {
    public var offsetX: Double
    public var offsetY: Double
    /// The shadow's softness (Gaussian standard deviation), 0...100.
    public var blur: Double
    public var color: Pixel
    /// 0...100 percent.
    public var opacity: Double

    public init(offsetX: Double = 12, offsetY: Double = 12, blur: Double = 10, color: Pixel = .black, opacity: Double = 50) {
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.blur = blur
        self.color = color
        self.opacity = opacity
    }
}

/// Border settings (FR-9.5): a solid outline around the outside of the object's shape.
public struct Border: Sendable, Hashable {
    /// 1...200 image pixels.
    public var width: Double
    public var color: Pixel

    public init(width: Double = 8, color: Pixel = .black) {
        self.width = width
        self.color = color
    }
}

/// Drop Shadow and Border (FR-9.5). Both follow the object's shape: the active layer's opaque pixels, or
/// the selected ones, so partly transparent edges cast a lighter shadow. Both are drawn behind the object,
/// and the canvas grows to fit them, as one undo step.
public enum Decorations {
    @discardableResult
    public static func dropShadow(_ shadow: DropShadow, canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        decorate("Drop Shadow", canvas: canvas, history: history, context: context) { shape in
            let sigma = min(max(shadow.blur, 0), 100)
            // Three standard deviations hold all but a trace of the blur.
            let pad = Int((3 * sigma).rounded(.up))
            let dx = Int(shadow.offsetX.rounded()), dy = Int(shadow.offsetY.rounded())
            let extent = shape.bounds.offsetBy(dx: dx, dy: dy).insetBy(-pad)
            let alpha = shape.blurred(sigma: sigma, pad: pad)
            let opacity = Float(min(max(shadow.opacity, 0), 100) / 100)
            return (extent, { x, y in alpha.value(x - dx, y - dy) * opacity }, shadow.color)
        }
    }

    @discardableResult
    public static func border(_ border: Border, canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        decorate("Border", canvas: canvas, history: history, context: context) { shape in
            let width = min(max(border.width, 1), 200)
            let pad = Int(width.rounded(.up))
            let extent = shape.bounds.insetBy(-pad)
            // A solid rectangle (an ordinary screenshot) gets square corners; any other shape a rounded outline.
            let distance = shape.isSolidRectangle ? shape.boxDistanceField(pad: pad) : shape.distanceField(pad: pad)
            // Solid out to `width`, anti-aliased over the last pixel; inside the shape too, so soft edges sit on it.
            // Distances run between pixel centers, and the shape's edge is half a pixel out from its last
            // center, so a pixel `width` away is still fully inside the border.
            let edge = Float(width + 1)
            return (extent, { x, y in min(max(edge - distance.value(x, y), 0), 1) }, border.color)
        }
    }

    /// The shared steps: find the shape, grow the canvas if the decoration needs room, draw it behind the object.
    private static func decorate(_ name: String, canvas: Canvas, history: History, context: SelectionContext,
                                 make: (Shape) -> (extent: IntRect, coverage: (Int, Int) -> Float, color: Pixel)) -> Bool {
        SelectionActions.placeFloating(canvas: canvas, history: history, context: context)
        let layer = canvas.activeLayer
        guard layer.adjustment == nil, !layer.isLocked else { return false }
        let selection = canvas.selection.marquee
        guard let shape = Shape(layer.buffer, selection: selection) else { return false }
        let (extent, coverage, color) = make(shape)

        let left = max(0, -extent.minX), top = max(0, -extent.minY)
        let right = max(0, extent.maxX - canvas.size.width), bottom = max(0, extent.maxY - canvas.size.height)
        let size = IntSize(width: canvas.size.width + left + right, height: canvas.size.height + top + bottom)
        guard size.width <= ResizeSkew.maxSide, size.height <= ResizeSkew.maxSide, size.width * size.height <= ResizeSkew.maxArea else { return false }
        let fill = canvas.vacatedFill(for: layer, color2: context.color2)

        /// The active layer's new pixel at `(x, y)` in the new canvas: the unselected part, then the decoration,
        /// then the object on top.
        func composed(_ x: Int, _ y: Int) -> Pixel {
            let ox = x - left, oy = y - top
            let inside = ox >= 0 && oy >= 0 && ox < canvas.size.width && oy < canvas.size.height
            let original = inside ? layer.buffer[ox, oy] : fill
            let selected: Float = inside ? (selection.map { Float($0[ox, oy]) / 255 } ?? 1) : 0
            var below = Compositing.over(.clear, original, coverage: 1 - selected)
            let amount = coverage(ox, oy)
            if amount > 0 { below = Compositing.over(below, color, coverage: amount) }
            return Compositing.over(below, original, coverage: selected)
        }

        let edit = history.beginEdit(name, on: canvas)
        if size == canvas.size {
            let region = extent.intersection(canvas.bounds)
            guard !region.isEmpty else { return false }
            let result = PixelBuffer(width: region.width, height: region.height)
            ParallelRows.forEach(region.minY..<region.maxY) { rows in
                for y in rows {
                    let target = result.row(y - region.minY)
                    for x in region.minX..<region.maxX { target[x - region.minX] = composed(x, y) }
                }
            }
            edit.willModify(region, in: layer)
            for y in region.minY..<region.maxY {
                (layer.buffer.row(y) + region.minX).update(from: result.row(y - region.minY), count: region.width)
            }
        } else {
            edit.willChangeGeometry()
            var buffers: [LayerID: PixelBuffer] = [:]
            for other in canvas.layers where other !== layer {
                let otherFill = other.adjustment == nil ? canvas.vacatedFill(for: other, color2: context.color2) : .clear
                let buffer = PixelBuffer(width: size.width, height: size.height, fill: otherFill)
                if !(other.holdsNoPixels && otherFill == .clear) {
                    buffer.setPixels(other.buffer.pixels(in: canvas.bounds), in: canvas.bounds.offsetBy(dx: left, dy: top))
                }
                buffers[other.id] = buffer
            }
            let active = PixelBuffer(width: size.width, height: size.height)
            ParallelRows.forEach(0..<size.height) { rows in
                for y in rows {
                    let target = active.row(y)
                    for x in 0..<size.width { target[x] = composed(x, y) }
                }
            }
            buffers[layer.id] = active
            let moved = selection?.translatedBy(dx: left, dy: top)
            canvas.replaceContents(size: size, buffers: buffers)
            canvas.selection = moved.map(SelectionState.marquee) ?? .none
        }
        return history.commit(edit)
    }
}

/// How much of each pixel belongs to the object (0...1): its alpha, times the selection where there is one.
struct Shape {
    let values: [Float]
    /// The smallest rectangle holding every pixel of the shape, in canvas coordinates.
    let bounds: IntRect

    init?(_ buffer: PixelBuffer, selection: SelectionMask?) {
        let area = (selection?.bounds ?? buffer.bounds).intersection(buffer.bounds)
        guard !area.isEmpty else { return nil }
        var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
        for y in area.minY..<area.maxY {
            let row = buffer.row(y)
            for x in area.minX..<area.maxX where row[x].a > 0 && (selection.map { $0[x, y] > 0 } ?? true) {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard minX <= maxX else { return nil }
        let bounds = IntRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        var values = [Float](repeating: 0, count: bounds.area)
        for y in bounds.minY..<bounds.maxY {
            let row = buffer.row(y)
            for x in bounds.minX..<bounds.maxX {
                let selected = selection.map { Float($0[x, y]) / 255 } ?? 1
                values[(y - bounds.minY) * bounds.width + (x - bounds.minX)] = Float(row[x].a) / 255 * selected
            }
        }
        self.values = values
        self.bounds = bounds
    }

    /// Every pixel of the bounds fully opaque and selected.
    var isSolidRectangle: Bool { values.allSatisfy { $0 >= 1 } }

    /// For a solid rectangle: how far outside it each pixel is along the farther axis, so the border is square.
    func boxDistanceField(pad: Int) -> Field {
        let area = bounds.insetBy(-pad)
        var values = [Float](repeating: 0, count: area.area)
        for y in area.minY..<area.maxY {
            let dy = max(bounds.minY - y, y - (bounds.maxY - 1), 0)
            for x in area.minX..<area.maxX {
                let dx = max(bounds.minX - x, x - (bounds.maxX - 1), 0)
                values[(y - area.minY) * area.width + (x - area.minX)] = Float(max(dx, dy))
            }
        }
        return Field(values: values, bounds: area, outside: .greatestFiniteMagnitude)
    }

    /// The shape blurred, over its bounds grown by `pad`.
    func blurred(sigma: Double, pad: Int) -> Field {
        let area = bounds.insetBy(-pad)
        let scratch = PixelBuffer(width: area.width, height: area.height)
        for y in 0..<bounds.height {
            let row = scratch.row(y + pad)
            for x in 0..<bounds.width {
                row[x + pad] = Pixel(r: 255, g: 255, b: 255, a: UInt8((values[y * bounds.width + x] * 255).rounded()))
            }
        }
        let soft = sigma > 0 ? Effects.blurred(scratch, region: scratch.bounds, sigma: sigma, selection: nil).0 : scratch
        var field = [Float](repeating: 0, count: area.area)
        for y in 0..<area.height {
            let row = soft.row(y)
            for x in 0..<area.width { field[y * area.width + x] = Float(row[x].a) / 255 }
        }
        return Field(values: field, bounds: area, outside: 0)
    }

    /// Distance in pixels from each pixel to the nearest pixel that's mostly inside the shape (alpha at least
    /// half), over its bounds grown by `pad`. Exact Euclidean distances (Felzenszwalb and Huttenlocher).
    func distanceField(pad: Int) -> Field {
        let area = bounds.insetBy(-pad)
        let width = area.width, height = area.height
        let infinity = Float(width * width + height * height)
        var squared = [Float](repeating: infinity, count: width * height)
        for y in 0..<bounds.height {
            for x in 0..<bounds.width where values[y * bounds.width + x] >= 0.5 {
                squared[(y + pad) * width + (x + pad)] = 0
            }
        }
        squared.withUnsafeMutableBufferPointer { grid in
            let grid = UnsafeSendableGrid(grid)
            ParallelRows.forEach(0..<width, minimumRows: 8) { columns in
                var line = [Float](repeating: 0, count: height)
                for x in columns {
                    for y in 0..<height { line[y] = grid.base[y * width + x] }
                    let result = Self.transform(line)
                    for y in 0..<height { grid.base[y * width + x] = result[y] }
                }
            }
            ParallelRows.forEach(0..<height, minimumRows: 8) { rows in
                for y in rows {
                    let line = Array(UnsafeBufferPointer(start: grid.base + y * width, count: width))
                    let result = Self.transform(line)
                    for x in 0..<width { grid.base[y * width + x] = result[x].squareRoot() }
                }
            }
        }
        return Field(values: squared, bounds: area, outside: .greatestFiniteMagnitude)
    }

    /// One pass of the squared-distance transform over a line of costs (0 inside, large outside).
    private static func transform(_ f: [Float]) -> [Float] {
        let n = f.count
        var result = [Float](repeating: 0, count: n)
        var v = [Int](repeating: 0, count: n)
        var z = [Float](repeating: 0, count: n + 1)
        var k = 0
        z[0] = -.greatestFiniteMagnitude
        z[1] = .greatestFiniteMagnitude
        for q in 1..<max(n, 1) {
            var s: Float
            repeat {
                let p = v[k]
                s = ((f[q] + Float(q * q)) - (f[p] + Float(p * p))) / Float(2 * q - 2 * p)
                if s <= z[k] { k -= 1 } else { break }
            } while k >= 0
            k += 1
            v[k] = q
            z[k] = s
            z[k + 1] = .greatestFiniteMagnitude
        }
        k = 0
        for q in 0..<n {
            while z[k + 1] < Float(q) { k += 1 }
            let p = v[k]
            result[q] = Float((q - p) * (q - p)) + f[p]
        }
        return result
    }
}

/// Values over a rectangle of the canvas, with a fixed value outside it.
struct Field {
    let values: [Float]
    let bounds: IntRect
    let outside: Float

    func value(_ x: Int, _ y: Int) -> Float {
        guard x >= bounds.minX, x < bounds.maxX, y >= bounds.minY, y < bounds.maxY else { return outside }
        return values[(y - bounds.minY) * bounds.width + (x - bounds.minX)]
    }
}

/// Lets the distance transform's column and row passes share the grid; each band touches only its own lines.
private struct UnsafeSendableGrid: @unchecked Sendable {
    let base: UnsafeMutablePointer<Float>
    init(_ buffer: UnsafeMutableBufferPointer<Float>) { base = buffer.baseAddress! }
}
