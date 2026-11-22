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
// rest. Every number is kept within what its control allows, so a damaged or hand-edited file can't start a window
// with a size that crashes or freezes it (review AI, finding 6).
extension ToolSettings: Codable {
    private enum Key: String, CodingKey {
        case color1, color2, brush, usesPressure, brushDiameter, eraserSize, colorEraserTolerance, colorEraserMode
        case fillTolerance, fillSamplesAllLayers, wandTolerance, wandContiguous, wandMode, wandSamplesAllLayers
        case transparentSelection, smoothResize, shapeKind, shapeLineWidth, shapeOutline, shapeFill, textStyle
        case badgeStyle, badgeDiameter, gradientMode, redactTreatment, redactBrushSize, retouchKind, retouchSizes
        case retouchSamplesAllLayers, retouchStrength, retouchHardness, toneRange, cloneAligned, cloneMatchesTone
        case eyedropperSampleSize
    }

    private enum TextKey: String, CodingKey {
        case fontFamily, fontSize, bold, italic, underline, strikethrough, alignment, opaqueBackground, curve
    }

    init(from decoder: any Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: Key.self)
        func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        func number(_ key: Key, _ fallback: Double, in range: ClosedRange<Double>) -> Double {
            Self.kept(value(key, fallback), in: range, or: fallback)
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
        brushDiameter = number(.brushDiameter, brushDiameter, in: Self.range(for: .brush))
        let eraser = value(.eraserSize, eraserSize)
        eraserSize = Editor.sizeRange(for: .eraser).contains(eraser) ? eraser : eraserSize
        colorEraserTolerance = number(.colorEraserTolerance, colorEraserTolerance, in: 0...1)
        colorEraserMode = value(.colorEraserMode, colorEraserMode)
        fillTolerance = number(.fillTolerance, fillTolerance, in: 0...1)
        fillSamplesAllLayers = value(.fillSamplesAllLayers, fillSamplesAllLayers)
        wandTolerance = number(.wandTolerance, wandTolerance, in: 0...1)
        wandContiguous = value(.wandContiguous, wandContiguous)
        wandMode = named(.wandMode, wandMode)
        wandSamplesAllLayers = value(.wandSamplesAllLayers, wandSamplesAllLayers)
        transparentSelection = value(.transparentSelection, transparentSelection)
        smoothResize = value(.smoothResize, smoothResize)
        shapeKind = named(.shapeKind, shapeKind)
        shapeLineWidth = number(.shapeLineWidth, shapeLineWidth, in: Self.range(for: .shape))
        shapeOutline = style(.shapeOutline, shapeOutline)
        shapeFill = style(.shapeFill, shapeFill)
        if let text = try? container.nestedContainer(keyedBy: TextKey.self, forKey: .textStyle) {
            textStyle = Self.textStyle(from: text, fallback: textStyle)
        }
        badgeStyle = value(.badgeStyle, badgeStyle)
        badgeDiameter = number(.badgeDiameter, badgeDiameter, in: Self.range(for: .stepBadge))
        gradientMode = named(.gradientMode, gradientMode)
        redactTreatment = named(.redactTreatment, redactTreatment)
        redactBrushSize = number(.redactBrushSize, redactBrushSize, in: Self.range(for: .redactBrush))
        retouchKind = named(.retouchKind, retouchKind)
        let sizes = value(.retouchSizes, [String: Double]())
        let retouchRange = Self.range(for: .retouch)
        retouchSizes = Dictionary(uniqueKeysWithValues: RetouchKind.allCases.compactMap { kind in
            sizes["\(kind)"].flatMap { retouchRange.contains($0) ? (kind, $0) : nil }
        })
        retouchSamplesAllLayers = value(.retouchSamplesAllLayers, retouchSamplesAllLayers)
        retouchStrength = number(.retouchStrength, retouchStrength, in: 0.01...1)
        retouchHardness = number(.retouchHardness, retouchHardness, in: 0...1)
        toneRange = named(.toneRange, toneRange)
        cloneAligned = value(.cloneAligned, cloneAligned)
        cloneMatchesTone = value(.cloneMatchesTone, cloneMatchesTone)
        let sample = value(.eyedropperSampleSize, eyedropperSampleSize)
        eyedropperSampleSize = [1, 3, 5].contains(sample) ? sample : eyedropperSampleSize
    }

    /// A tool's size range from the Size control, as a Double.
    private static func range(for tool: Tool) -> ClosedRange<Double> {
        let range = Editor.sizeRange(for: tool)
        return Double(range.lowerBound)...Double(range.upperBound)
    }

    /// A number outside what its control allows is clamped to it; one that isn't a number keeps the default.
    private static func kept(_ number: Double, in range: ClosedRange<Double>, or fallback: Double) -> Double {
        number.isFinite ? min(max(number, range.lowerBound), range.upperBound) : fallback
    }

    /// Field by field, so a text option added later keeps the rest of the style (review AI, finding 10).
    private static func textStyle(from text: KeyedDecodingContainer<TextKey>, fallback: TextStyle) -> TextStyle {
        func value<T: Decodable>(_ key: TextKey, _ fallback: T) -> T {
            (try? text.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        var style = fallback
        let family = value(.fontFamily, fallback.fontFamily)
        style.fontFamily = family.trimmingCharacters(in: .whitespaces).isEmpty ? fallback.fontFamily : family
        style.fontSize = kept(value(.fontSize, fallback.fontSize), in: 6...500, or: fallback.fontSize)
        style.bold = value(.bold, fallback.bold)
        style.italic = value(.italic, fallback.italic)
        style.underline = value(.underline, fallback.underline)
        style.strikethrough = value(.strikethrough, fallback.strikethrough)
        style.alignment = value(.alignment, fallback.alignment)
        style.opaqueBackground = value(.opaqueBackground, fallback.opaqueBackground)
        style.curve = kept(value(.curve, fallback.curve), in: -100...100, or: fallback.curve)
        return style
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

    /// `make bench`, help screenshots and the menu dump keep the default settings, so their windows are the same on
    /// every run (§23 stage 34c, choice 6; review AI, finding 9).
    static var isEnabled: Bool { !Benchmark.isEnabled && HelpShots.scene == 0 && HelpDump.path == nil }

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
        // While a mask is chosen, and after it until a real color is picked, the colors are grays; the real colors are
        // the ones carried (§23, stage 34 details; Leah, 2026-11-21).
        if let real = editor.colorsBeforeMask {
            settings.color1 = real.color1
            settings.color2 = real.color2
        } else if editor.editsMask {
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
