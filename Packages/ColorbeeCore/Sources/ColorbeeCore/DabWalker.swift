/// Places dabs at even spacing along a stroke's path, interpolating pressure between pointer events.
struct DabWalker {
    struct Dab {
        let center: Point2D
        let pressure: Double
        /// Unit direction of travel; rightward until the pointer first moves.
        let direction: Point2D
        /// Distance along the stroke from its start.
        let distance: Double
    }

    private var lastPoint: Point2D?
    private var lastPressure = 1.0
    private var untilNextDab = 0.0
    private(set) var length = 0.0
    private(set) var direction = Point2D(x: 1, y: 0)

    /// The dabs between the previous point and `point`. `spacing` gives the gap after a dab of a given pressure.
    mutating func walk(to point: Point2D, pressure: Double, spacing: (Double) -> Double) -> [Dab] {
        let pressure = min(1, max(0, pressure))
        guard let last = lastPoint else {
            lastPoint = point
            lastPressure = pressure
            untilNextDab = spacing(pressure)
            return [Dab(center: point, pressure: pressure, direction: direction, distance: 0)]
        }
        let dx = point.x - last.x, dy = point.y - last.y
        let distance = (dx * dx + dy * dy).squareRoot()
        guard distance > 0 else {
            lastPressure = pressure
            return []
        }
        direction = Point2D(x: dx / distance, y: dy / distance)
        var dabs: [Dab] = []
        var travelled = untilNextDab
        while travelled <= distance {
            let t = travelled / distance
            let dabPressure = lastPressure + (pressure - lastPressure) * t
            dabs.append(Dab(
                center: Point2D(x: last.x + dx * t, y: last.y + dy * t),
                pressure: dabPressure,
                direction: direction,
                distance: length + travelled
            ))
            travelled += spacing(dabPressure)
        }
        untilNextDab = travelled - distance
        length += distance
        lastPoint = point
        lastPressure = pressure
        return dabs
    }

    /// Where the pointer is now, and its pressure; nil before the first point.
    var current: (point: Point2D, pressure: Double)? {
        lastPoint.map { ($0, lastPressure) }
    }
}
