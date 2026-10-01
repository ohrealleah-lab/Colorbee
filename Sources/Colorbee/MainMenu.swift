import AppKit

@MainActor
enum MainMenu {
    static func make() -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu(appMenu()))
        main.addItem(submenu(fileMenu()))
        main.addItem(submenu(editMenu()))
        main.addItem(submenu(viewMenu()))
        main.addItem(submenu(imageMenu()))
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
        menu.addItem(.separator())
        menu.addItem(item("Enter Full Screen", "toggleFullScreen:", "f", [.command, .control]))
        return menu
    }

    private static func imageMenu() -> NSMenu {
        let menu = NSMenu(title: "Image")
        menu.addItem(item("Crop to Selection", "cropToSelection:", "x", [.command, .shift]))
        return menu
    }

    private static func effectsMenu() -> NSMenu {
        let menu = NSMenu(title: "Effects")
        menu.addItem(item("Gaussian Blur…", "showGaussianBlur:"))
        menu.addItem(item("Pixelate…", "showPixelate:"))
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
