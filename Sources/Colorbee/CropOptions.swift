import ColorbeeCore
import SwiftUI

/// The crop box's shape (FR-9.5).
enum CropShape: Hashable {
    case free
    case original
    case square
    /// Width to height, such as 16:9. Also what a custom shape or a swapped one becomes.
    case ratio(Int, Int)

    static let presets: [CropShape] = [.free, .original, .square, .ratio(4, 3), .ratio(3, 2), .ratio(16, 9), .ratio(9, 16)]

    var title: String {
        switch self {
        case .free: "Free"
        case .original: "Original"
        case .square: "Square"
        case .ratio(let w, let h): "\(w):\(h)"
        }
    }

    /// Width ÷ height, or nil for Free.
    func aspect(original: IntSize) -> Double? {
        switch self {
        case .free: nil
        case .original: Double(original.width) / Double(original.height)
        case .square: 1
        case .ratio(let w, let h): w > 0 && h > 0 ? Double(w) / Double(h) : nil
        }
    }

    /// Portrait for landscape and the other way round.
    func swapped(original: IntSize) -> CropShape {
        switch self {
        case .free, .square: self
        case .original: .ratio(original.height, original.width)
        case .ratio(let w, let h): .ratio(h, w)
        }
    }
}

/// Exact output sizes for common places to post (FR-9.5).
struct CropSizePreset: Hashable {
    let title: String
    let size: IntSize

    static let all = [
        CropSizePreset(title: "Link preview", size: IntSize(width: 1200, height: 630)),
        CropSizePreset(title: "Square post", size: IntSize(width: 1080, height: 1080)),
        CropSizePreset(title: "Portrait post", size: IntSize(width: 1080, height: 1350)),
        CropSizePreset(title: "Story", size: IntSize(width: 1080, height: 1920)),
        CropSizePreset(title: "HD", size: IntSize(width: 1920, height: 1080)),
        CropSizePreset(title: "Banner", size: IntSize(width: 1500, height: 500)),
    ]
}

/// The crop bar's controls: shape, a custom ratio, orientation, pixel size and the box's size.
struct CropOptions: View {
    @Bindable var editor: Editor
    @State private var customWidth = 5
    @State private var customHeight = 4

    var body: some View {
        Picker("Shape", selection: shapeBinding) {
            ForEach(CropShape.presets, id: \.self) { Text($0.title).tag(Optional($0)) }
            Text("Custom").tag(Optional(CropShape.ratio(customWidth, customHeight)))
        }
        .fixedSize()
        .disabled(editor.cropPixelSize != nil)
        .help("The crop box's shape")
        if case .ratio(let w, let h) = editor.cropShape, !CropShape.presets.contains(editor.cropShape), editor.cropPixelSize == nil {
            HStack(spacing: 3) {
                TextField("Width", value: Binding(get: { w }, set: { set(.ratio(max(1, $0), h)) }), format: .number)
                    .frame(width: 36)
                Text(":")
                TextField("Height", value: Binding(get: { h }, set: { set(.ratio(w, max(1, $0))) }), format: .number)
                    .frame(width: 36)
            }
            .multilineTextAlignment(.center)
        }
        Button("Swap", systemImage: "rectangle.portrait.rotate") {
            if let size = editor.cropPixelSize {
                editor.setCrop(shape: editor.cropShape, pixelSize: IntSize(width: size.height, height: size.width))
            } else {
                set(editor.cropShape.swapped(original: editor.canvas.size))
            }
        }
        .labelStyle(.iconOnly)
        .disabled(editor.cropShape == .free && editor.cropPixelSize == nil)
        .help("Swap portrait and landscape")
        Picker("Size", selection: Binding(get: { editor.cropPixelSize }, set: { editor.setCrop(shape: editor.cropShape, pixelSize: $0) })) {
            Text("Any size").tag(IntSize?.none)
            ForEach(CropSizePreset.all, id: \.self) { preset in
                Text("\(preset.size.width) × \(preset.size.height) · \(preset.title)").tag(Optional(preset.size))
            }
            if let size = editor.cropPixelSize, !CropSizePreset.all.contains(where: { $0.size == size }) {
                Text("\(size.width) × \(size.height)").tag(Optional(size))
            }
        }
        .fixedSize()
        .help("Resize the cropped image to exactly this many pixels")
        Text(sizeText)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .fixedSize()
    }

    private var shapeBinding: Binding<CropShape?> {
        Binding(get: { editor.cropShape }, set: { if let shape = $0 { set(shape) } })
    }

    private func set(_ shape: CropShape) {
        if case .ratio(let w, let h) = shape, !CropShape.presets.contains(shape) {
            customWidth = w
            customHeight = h
        }
        editor.setCrop(shape: shape, pixelSize: nil)
    }

    private var sizeText: String {
        let box = "\(editor.cropRect.width) × \(editor.cropRect.height) px"
        guard let size = editor.cropPixelSize else { return box }
        return "\(box) → \(size.width) × \(size.height)"
    }
}
