import AppKit
import ColorbeeCore

@MainActor
enum MainMenu {
    static func make() -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu(appMenu()))
        main.addItem(submenu(fileMenu()))
        main.addItem(submenu(editMenu()))
        main.addItem(submenu(viewMenu()))
        main.addItem(submenu(imageMenu()))
        main.addItem(submenu(adjustmentsMenu()))
        main.addItem(submenu(effectsMenu()))

        let window = windowMenu()
        main.addItem(submenu(window))
        NSApp.windowsMenu = window

        let help = NSMenu(title: "Help")
        main.addItem(submenu(help))
        NSApp.helpMenu = help
        return main
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func item(
        _ title: String,
        _ action: String,
        _ key: String = "",
        _ modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: Selector(action), keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        return item
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "Colorbee")
        menu.addItem(item("About Colorbee", "orderFrontStandardAboutPanel:"))
        menu.addItem(.separator())
        let services = NSMenu(title: "Services")
        menu.addItem(submenu(services))
        NSApp.servicesMenu = services
        menu.addItem(.separator())
        menu.addItem(item("Hide Colorbee", "hide:", "h"))
        menu.addItem(item("Hide Others", "hideOtherApplications:", "h", [.command, .option]))
        menu.addItem(item("Show All", "unhideAllApplications:"))
        menu.addItem(.separator())
        menu.addItem(item("Quit Colorbee", "terminate:", "q"))
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(item("New", "newDocument:", "n"))
        menu.addItem(item("Open…", "openDocument:", "o"))
        let recent = NSMenu(title: "Open Recent")
        recent.addItem(item("Clear Menu", "clearRecentDocuments:"))
        menu.addItem(submenu(recent))
        menu.addItem(.separator())
        menu.addItem(item("Close", "performClose:", "w"))
        menu.addItem(item("Save", "saveDocument:", "s"))
        menu.addItem(item("Save As…", "saveDocumentAs:", "s", [.command, .shift]))
        menu.addItem(item("Duplicate", "duplicateDocument:"))
        menu.addItem(item("Revert To Saved", "revertDocumentToSaved:"))
        menu.addItem(.separator())
        menu.addItem(item("Export…", "exportDocument:", "s", [.command, .option]))
        let presets = NSMenu(title: "Export As")
        presets.delegate = ExportPresetMenuTitles.shared
        for (index, preset) in ExportPreset.defaults.enumerated() {
            let presetItem = item(preset.name, "exportPreset:")
            presetItem.tag = index
            presets.addItem(presetItem)
        }
        menu.addItem(submenu(presets))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(item("Undo", "undo:", "z"))
        menu.addItem(item("Redo", "redo:", "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Cut", "cut:", "x"))
        menu.addItem(item("Copy", "copy:", "c"))
        menu.addItem(item("Paste", "paste:", "v"))
        // The canvas handles the Delete key itself, so text fields keep their own Delete.
        menu.addItem(item("Delete", "delete:"))
        menu.addItem(.separator())
        menu.addItem(item("Select All", "selectAll:", "a"))
        menu.addItem(item("Deselect", "deselect:", "d"))
        menu.addItem(item("Invert Selection", "invertSelection:", "i", [.command, .shift]))
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        menu.addItem(item("Zoom In", "zoomIn:", "="))
        menu.addItem(item("Zoom Out", "zoomOut:", "-"))
        menu.addItem(item("Actual Size", "actualSize:", "0"))
        menu.addItem(item("Zoom to Fit", "zoomToFit:", "9"))
        menu.addItem(.separator())
        menu.addItem(item("Pixel Grid", "togglePixelGrid:", "'"))
        menu.addItem(item("Before/After", "toggleBeforeAfter:", "b", [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(item("Enter Full Screen", "toggleFullScreen:", "f", [.command, .control]))
        return menu
    }

    private static func imageMenu() -> NSMenu {
        let menu = NSMenu(title: "Image")
        menu.addItem(item("Crop to Selection", "cropToSelection:", "x", [.command, .shift]))
        menu.addItem(.separator())
        let rotate = NSMenu(title: "Rotate")
        let flip = NSMenu(title: "Flip")
        for (index, orientation) in Orientation.allCases.enumerated() {
            let orientationItem = item(orientation.name.replacingOccurrences(of: "Rotate ", with: "").replacingOccurrences(of: "Flip ", with: ""), "applyOrientation:")
            orientationItem.tag = index
            (orientation == .flipHorizontal || orientation == .flipVertical ? flip : rotate).addItem(orientationItem)
        }
        menu.addItem(submenu(rotate))
        menu.addItem(submenu(flip))
        menu.addItem(.separator())
        let symmetry = NSMenu(title: "Symmetry")
        for (index, mode) in ["Off", "Vertical", "Horizontal", "Both"].enumerated() {
            let modeItem = item(mode, "setSymmetry:")
            modeItem.tag = index
            symmetry.addItem(modeItem)
        }
        menu.addItem(submenu(symmetry))
        return menu
    }

    private static func adjustmentsMenu() -> NSMenu {
        let menu = NSMenu(title: "Adjustments")
        menu.addItem(item("Invert Colors", "invertColors:", "i"))
        menu.addItem(item("Brightness/Contrast…", "showBrightnessContrast:"))
        menu.addItem(item("Hue/Saturation…", "showHueSaturation:"))
        menu.addItem(item("Desaturate", "desaturate:", "u", [.command, .shift]))
        return menu
    }

    private static func effectsMenu() -> NSMenu {
        let menu = NSMenu(title: "Effects")
        menu.addItem(item("Gaussian Blur…", "showGaussianBlur:"))
        menu.addItem(item("Pixelate…", "showPixelate:"))
        menu.addItem(item("Sharpen…", "showSharpen:"))
        menu.addItem(.separator())
        let batch = NSMenu(title: "Batch Redact")
        batch.addItem(item("Blur…", "showGaussianBlur:"))
        batch.addItem(item("Pixelate…", "showPixelate:"))
        batch.addItem(item("Solid Fill with Color 1", "applySolidFill:"))
        menu.addItem(submenu(batch))
        menu.addItem(item("Auto-Redact…", "showAutoRedact:"))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Minimize", "performMiniaturize:", "m"))
        menu.addItem(item("Zoom", "performZoom:"))
        menu.addItem(.separator())
        menu.addItem(item("Bring All to Front", "arrangeInFront:"))
        return menu
    }
}

/// Shows each export preset's exact output size for the current document when the menu opens.
@MainActor
final class ExportPresetMenuTitles: NSObject, NSMenuDelegate {
    static let shared = ExportPresetMenuTitles()

    func menuNeedsUpdate(_ menu: NSMenu) {
        let size = (NSDocumentController.shared.currentDocument as? ImageDocument)?.canvasSize
        for item in menu.items where ExportPreset.defaults.indices.contains(item.tag) {
            let preset = ExportPreset.defaults[item.tag]
            guard let size else {
                item.title = preset.name
                continue
            }
            let target = preset.targetSize(for: size)
            let dimensions = "\(target.width) × \(target.height) px"
            item.title = target == size && preset.targetSize(for: size, allowEnlarging: true) != size
                ? "\(preset.name) — \(dimensions) (original size)"
                : "\(preset.name) — \(dimensions)"
        }
    }
}
