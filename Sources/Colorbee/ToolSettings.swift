import ColorbeeCore
import Foundation
import Observation

/// The tool settings a new window starts with: those last changed in any window, kept between launches (stage 34c;
/// FR-15.4). Not the tool (Rectangle Select to start), Symmetry, or anything about the picture.
struct ToolSettings: Equatable {
    var color1 = Pixel.black
    var color2 = Pixel.white
    var brush = Brush.round
    var usesPressure = true
    var brushDiameter = 5.0
    var eraserSize = 8
    var colorEraserTolerance = 0.0
    var colorEraserMode = false
    var fillTolerance = 0.0
    var fillSamplesAllLayers = false
    var wandTolerance = 0.1
    var wandContiguous = true
    var wandMode = Editor.WandMode.color
    var wandSamplesAllLayers = false
    var transparentSelection = false
    var smoothResize = true
    var shapeKind = ShapeKind.rectangle
    var shapeLineWidth = 3.0
    var shapeOutline: PaintStyle? = .solid
    var shapeFill: PaintStyle?
    var textStyle = TextStyle()
    var badgeStyle = BadgeStyle.numbers
    var badgeDiameter = 32.0
    var gradientMode = GradientMode.linear
    var redactTreatment = RedactionTreatment.solidFill
    var redactBrushSize = 24.0
    var retouchKind = RetouchKind.remove
    var retouchSizes: [RetouchKind: Double] = [:]
    var retouchSamplesAllLayers = false
    var retouchStrength = 0.5
    var retouchHardness = 0.5
    var toneRange = ToneRange.midtones
    var cloneAligned = true
    var cloneMatchesTone = false
    var eyedropperSampleSize = 1
}

// Kept as JSON by name, so a setting added later, or a case renamed, falls back to its default rather than losing the
// rest.
extension ToolSettings: Codable {
    private enum Key: String, CodingKey {
        case color1, color2, brush, usesPressure, brushDiameter, eraserSize, colorEraserTolerance, colorEraserMode
        case fillTolerance, fillSamplesAllLayers, wandTolerance, wandContiguous, wandMode, wandSamplesAllLayers
        case transparentSelection, smoothResize, shapeKind, shapeLineWidth, shapeOutline, shapeFill, textStyle
        case badgeStyle, badgeDiameter, gradientMode, redactTreatment, redactBrushSize, retouchKind, retouchSizes
        case retouchSamplesAllLayers, retouchStrength, retouchHardness, toneRange, cloneAligned, cloneMatchesTone
        case eyedropperSampleSize
    }

    init(from decoder: any Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: Key.self)
        func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        func named<T: CaseIterable>(_ key: Key, _ fallback: T) -> T {
            let name = value(key, "")
            return T.allCases.first { "\($0)" == name } ?? fallback
        }
        func color(_ key: Key, _ fallback: Pixel) -> Pixel {
            let parts = value(key, [UInt8]())
            return parts.count == 4 ? Pixel(r: parts[0], g: parts[1], b: parts[2], a: parts[3]) : fallback
        }
        func style(_ key: Key, _ fallback: PaintStyle?) -> PaintStyle? {
            let name = value(key, "")
            return name == "none" ? nil : PaintStyle.allCases.first { "\($0)" == name } ?? fallback
        }
        color1 = color(.color1, color1)
        color2 = color(.color2, color2)
        brush = named(.brush, brush)
        usesPressure = value(.usesPressure, usesPressure)
        brushDiameter = value(.brushDiameter, brushDiameter)
        eraserSize = value(.eraserSize, eraserSize)
        colorEraserTolerance = value(.colorEraserTolerance, colorEraserTolerance)
        colorEraserMode = value(.colorEraserMode, colorEraserMode)
        fillTolerance = value(.fillTolerance, fillTolerance)
        fillSamplesAllLayers = value(.fillSamplesAllLayers, fillSamplesAllLayers)
        wandTolerance = value(.wandTolerance, wandTolerance)
        wandContiguous = value(.wandContiguous, wandContiguous)
        wandMode = named(.wandMode, wandMode)
        wandSamplesAllLayers = value(.wandSamplesAllLayers, wandSamplesAllLayers)
        transparentSelection = value(.transparentSelection, transparentSelection)
        smoothResize = value(.smoothResize, smoothResize)
        shapeKind = named(.shapeKind, shapeKind)
        shapeLineWidth = value(.shapeLineWidth, shapeLineWidth)
        shapeOutline = style(.shapeOutline, shapeOutline)
        shapeFill = style(.shapeFill, shapeFill)
        textStyle = value(.textStyle, textStyle)
        badgeStyle = value(.badgeStyle, badgeStyle)
        badgeDiameter = value(.badgeDiameter, badgeDiameter)
        gradientMode = named(.gradientMode, gradientMode)
        redactTreatment = named(.redactTreatment, redactTreatment)
        redactBrushSize = value(.redactBrushSize, redactBrushSize)
        retouchKind = named(.retouchKind, retouchKind)
        let sizes = value(.retouchSizes, [String: Double]())
        retouchSizes = Dictionary(uniqueKeysWithValues: RetouchKind.allCases.compactMap { kind in sizes["\(kind)"].map { (kind, $0) } })
        retouchSamplesAllLayers = value(.retouchSamplesAllLayers, retouchSamplesAllLayers)
        retouchStrength = value(.retouchStrength, retouchStrength)
        retouchHardness = value(.retouchHardness, retouchHardness)
        toneRange = named(.toneRange, toneRange)
        cloneAligned = value(.cloneAligned, cloneAligned)
        cloneMatchesTone = value(.cloneMatchesTone, cloneMatchesTone)
        eyedropperSampleSize = value(.eyedropperSampleSize, eyedropperSampleSize)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode([color1.r, color1.g, color1.b, color1.a], forKey: .color1)
        try container.encode([color2.r, color2.g, color2.b, color2.a], forKey: .color2)
        try container.encode("\(brush)", forKey: .brush)
        try container.encode(usesPressure, forKey: .usesPressure)
        try container.encode(brushDiameter, forKey: .brushDiameter)
        try container.encode(eraserSize, forKey: .eraserSize)
        try container.encode(colorEraserTolerance, forKey: .colorEraserTolerance)
        try container.encode(colorEraserMode, forKey: .colorEraserMode)
        try container.encode(fillTolerance, forKey: .fillTolerance)
        try container.encode(fillSamplesAllLayers, forKey: .fillSamplesAllLayers)
        try container.encode(wandTolerance, forKey: .wandTolerance)
        try container.encode(wandContiguous, forKey: .wandContiguous)
        try container.encode("\(wandMode)", forKey: .wandMode)
        try container.encode(wandSamplesAllLayers, forKey: .wandSamplesAllLayers)
        try container.encode(transparentSelection, forKey: .transparentSelection)
        try container.encode(smoothResize, forKey: .smoothResize)
        try container.encode("\(shapeKind)", forKey: .shapeKind)
        try container.encode(shapeLineWidth, forKey: .shapeLineWidth)
        try container.encode(shapeOutline.map { "\($0)" } ?? "none", forKey: .shapeOutline)
        try container.encode(shapeFill.map { "\($0)" } ?? "none", forKey: .shapeFill)
        try container.encode(textStyle, forKey: .textStyle)
        try container.encode(badgeStyle, forKey: .badgeStyle)
        try container.encode(badgeDiameter, forKey: .badgeDiameter)
        try container.encode("\(gradientMode)", forKey: .gradientMode)
        try container.encode("\(redactTreatment)", forKey: .redactTreatment)
        try container.encode(redactBrushSize, forKey: .redactBrushSize)
        try container.encode("\(retouchKind)", forKey: .retouchKind)
        try container.encode(Dictionary(uniqueKeysWithValues: retouchSizes.map { ("\($0.key)", $0.value) }), forKey: .retouchSizes)
        try container.encode(retouchSamplesAllLayers, forKey: .retouchSamplesAllLayers)
        try container.encode(retouchStrength, forKey: .retouchStrength)
        try container.encode(retouchHardness, forKey: .retouchHardness)
        try container.encode("\(toneRange)", forKey: .toneRange)
        try container.encode(cloneAligned, forKey: .cloneAligned)
        try container.encode(cloneMatchesTone, forKey: .cloneMatchesTone)
        try container.encode(eyedropperSampleSize, forKey: .eyedropperSampleSize)
    }
}

/// Follows every document window's tool settings and starts new ones with the last changed. While testing there's no
/// file, so nothing is saved (CLAUDE.md), and only documents follow it: a test's `Editor` starts from the defaults.
@MainActor
final class ToolSettingsStore {
    static let shared = ToolSettingsStore(file: SettingsFolder.current?.appending(path: "Tool Settings.json"))

    /// Nil until a window changes a setting (and no file was kept), so new windows start from the defaults.
    private(set) var last: ToolSettings?
    private let file: URL?
    private var saveScheduled = false

    init(file: URL?) {
        self.file = file
        if let file, let data = try? Data(contentsOf: file) {
            last = try? JSONDecoder().decode(ToolSettings.self, from: data)
        }
    }

    /// A new or restored window: it takes the last settings, then its own changes become the last.
    func start(_ editor: Editor) {
        if let last { editor.toolSettings = last }
        follow(editor)
    }

    private func follow(_ editor: Editor) {
        withObservationTracking {
            _ = editor.toolSettings
        } onChange: { [weak self, weak editor] in
            // Called as a setting is about to change; it's read once it has.
            Task { @MainActor in
                guard let self, let editor else { return }
                self.note(editor)
                self.follow(editor)
            }
        }
    }

    func note(_ editor: Editor) {
        var settings = editor.toolSettings
        // While a mask is chosen the colors are grays; the real colors are the ones carried (§23, stage 34 details).
        if editor.canvas.editsMask {
            settings.color1 = last?.color1 ?? ToolSettings().color1
            settings.color2 = last?.color2 ?? ToolSettings().color2
        }
        guard settings != last else { return }
        last = settings
        saveSoon()
    }

    /// A slider drag changes a setting many times a second; the file is written once it settles, and on quit.
    private func saveSoon() {
        guard file != nil, !saveScheduled else { return }
        saveScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.save()
        }
    }

    func save() {
        saveScheduled = false
        guard let file, let last, let data = try? JSONEncoder().encode(last) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
