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

    @MainActor func open() { openHelp(at: rawValue) }
}

/// The help's pages, listed in the Help menu under Colorbee Help as quick links (Leah, 2026-10-22). Each opens at
/// the `page-` anchor at its top, used only once in the book.
enum HelpPage: String, CaseIterable {
    case gettingStarted = "getting-started"
    case redact = "redact-a-screenshot"
    case annotate = "annotate-an-image"
    case layers = "work-with-layers"
    case photo = "fix-up-a-photo"
    case pages = "pages-and-pdfs"
    case pixelArt = "pixel-art"
    case save = "save-export-and-share"
    case tools
    case menus
    case shortcuts = "keyboard-shortcuts"
    case panels
    case settings
    case privacy
    case troubleshooting

    var anchor: String { "page-\(rawValue)" }
    var isGuide: Bool { allGuides.contains(self) }
    private var allGuides: [HelpPage] { [.gettingStarted, .redact, .annotate, .layers, .photo, .pages, .pixelArt, .save] }

    var title: String {
        switch self {
        case .gettingStarted: "Getting Started"
        case .redact: "Redact a Screenshot"
        case .annotate: "Annotate an Image"
        case .layers: "Work with Layers"
        case .photo: "Fix Up a Photo"
        case .pages: "Pages and PDFs"
        case .pixelArt: "Pixel Art"
        case .save: "Save, Export and Share"
        case .tools: "Tools"
        case .menus: "Menus"
        case .shortcuts: "Keyboard Shortcuts"
        case .panels: "Panels"
        case .settings: "Settings"
        case .privacy: "Privacy"
        case .troubleshooting: "Troubleshooting"
        }
    }

    /// The same line the help's contents page gives it.
    var summary: String {
        switch self {
        case .gettingStarted: "A tour of the window, colors, keys and undo."
        case .redact: "Hide emails, phone numbers and keys before you share."
        case .annotate: "Arrows, shapes, numbered steps, text and highlights."
        case .layers: "Keep parts separate, and change their look with adjustment layers."
        case .photo: "Light and color, straightening, removing things, red-eye and RAW photos."
        case .pages: "Edit every page of a PDF, and make PDFs."
        case .pixelArt: "The Pencil, the pixel grid, symmetry and the Color Eraser."
        case .save: "Formats, projects, export sizes and earlier versions."
        case .tools: "Every tool, its settings, and its keys."
        case .menus: "Every menu command and what it does."
        case .shortcuts: "Every key, all in one place."
        case .panels: "Layers, Adjustments, History, Clipboard History, pages and Before/After."
        case .settings: "Appearance, PDF resolution, shortcuts and export presets."
        case .privacy: "What stays on your Mac, and what goes into the files you share."
        case .troubleshooting: "Common surprises, and how to report a problem."
        }
    }

    @MainActor func open() { openHelp(at: anchor) }
}

/// Opens Colorbee Help at `anchor`. The book is registered again first: registering it once at launch doesn't always
/// stick (after macOS's help cache is cleared, say), and then Help Viewer can't find new anchors (Leah, 2026-10-22).
@MainActor
func openHelp(at anchor: String) {
    NSHelpManager.shared.registerBooks(in: .main)
    let book = Bundle.main.object(forInfoDictionaryKey: "CFBundleHelpBookName") as? String
    NSHelpManager.shared.openHelpAnchor(anchor, inBook: book)
}

/// The standard round ? button, opening one section of the help.
struct HelpButton: View {
    let anchor: HelpAnchor

    var body: some View {
        HelpLink { anchor.open() }
            .help("Open Colorbee Help for this")
    }
}
