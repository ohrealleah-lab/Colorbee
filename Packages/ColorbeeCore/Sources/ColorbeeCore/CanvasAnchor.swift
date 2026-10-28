/// Where the picture stays when Canvas Properties changes the canvas size (FR-2.2, §23 2026-10-28): one of nine
/// places. New space goes on the other sides; a smaller canvas cuts the sides away from it.
public enum CanvasAnchor: Int, CaseIterable, Sendable {
    case topLeft, top, topRight, left, center, right, bottomLeft, bottom, bottomRight

    /// How far across and down the picture sits in the spare space: 0, a half or all of it.
    var fractions: (x: Double, y: Double) {
        (Double(rawValue % 3) / 2, Double(rawValue / 3) / 2)
    }

    /// For VoiceOver and tooltips.
    public var title: String {
        switch self {
        case .topLeft: "Top left"
        case .top: "Top"
        case .topRight: "Top right"
        case .left: "Left"
        case .center: "Center"
        case .right: "Right"
        case .bottomLeft: "Bottom left"
        case .bottom: "Bottom"
        case .bottomRight: "Bottom right"
        }
    }

    /// Where the old picture's top-left corner goes on a canvas of `size`. An odd difference can't split evenly: the
    /// extra pixel goes on the right or bottom, whether the canvas grows or shrinks.
    public func offset(from old: IntSize, to size: IntSize) -> IntPoint {
        func along(_ difference: Int, _ fraction: Double) -> Int { Int((Double(difference) * fraction).rounded(.towardZero)) }
        return IntPoint(x: along(size.width - old.width, fractions.x), y: along(size.height - old.height, fractions.y))
    }
}
