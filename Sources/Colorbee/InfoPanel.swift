import AppKit
import ColorbeeCore
import SwiftUI

/// The Info panel (FR-1.3): read-only facts about the file, the image and how the photo was taken.
struct InfoPanel: View {
    @Bindable var editor: Editor

    var body: some View {
        var info = editor.documentInfo
        info.profileName = NSColorSpace(cgColorSpace: editor.canvas.colorSpace)?.localizedName
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(info.sections, id: \.title) { section in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(section.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.secondaryInk)
                        ForEach(section.rows, id: \.label) { row in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(row.label)
                                    .foregroundStyle(Theme.secondaryInk)
                                    .frame(width: 84, alignment: .leading)
                                Text(row.value)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .font(.system(size: 12))
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .frame(minHeight: 100, maxHeight: .infinity)
    }
}
