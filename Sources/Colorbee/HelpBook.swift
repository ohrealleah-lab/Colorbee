import AppKit
import SwiftUI

/// Places in Colorbee Help that the contextual ? buttons open (FR-14.6). Each is an `<a name>` anchor used only once
/// in the whole book: Help Viewer shows a list of pages instead of jumping when an anchor appears on several.
enum HelpAnchor: String, CaseIterable {
    case autoRedact = "auto-redact"
    case shortcutSettings = "settings-shortcuts"
    case exportPresets = "export-presets"
    case resizeSkew = "resize-and-skew"
    case canvasProperties = "canvas-properties"
    case rawDevelop = "raw-develop"
    case retouchTools = "retouch-tools"
    case cloneStamp = "clone-stamp"

    @MainActor func open() {
        let book = Bundle.main.object(forInfoDictionaryKey: "CFBundleHelpBookName") as? String
        NSHelpManager.shared.openHelpAnchor(rawValue, inBook: book)
    }
}

/// The standard round ? button, opening one section of the help.
struct HelpButton: View {
    let anchor: HelpAnchor

    var body: some View {
        HelpLink { anchor.open() }
            .help("Open Colorbee Help for this")
    }
}
