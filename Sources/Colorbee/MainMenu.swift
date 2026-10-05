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
        main.addItem(submenu(layerMenu()))
        main.addItem(submenu(pageMenu()))
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

    /// Hover text for every command, keyed by its action.
    private static let tooltips: [String: String] = [
        "orderFrontStandardAboutPanel:": "Version and credits.",
        "showSettings:": "Keyboard shortcuts and export presets.",
        "hide:": "Hide Colorbee's windows until you switch back.",
        "hideOtherApplications:": "Hide every other app's windows.",
        "unhideAllApplications:": "Show every app's windows again.",
        "terminate:": "Quit Colorbee. Your work is saved automatically.",
        "newDocument:": "Start a new blank 1920 × 1080 image.",
        "openDocument:": "Open an image (PNG, JPEG, HEIC, TIFF, GIF, BMP or WebP) or a Colorbee project.",
        "clearRecentDocuments:": "Forget the list of recently opened images.",
        "performClose:": "Close this window.",
        "saveDocument:": "Save the image. Untitled images ask for a name and format.",
        "saveDocumentAs:": "Save a copy under a new name or in another format.",
        "duplicateDocument:": "Open a copy of this image in a new window.",
        "revertDocumentToSaved:": "Throw away changes since the last save.",
        "exportDocument:": "Save a copy in any format, with a quality setting for JPEG and HEIC.",
        "exportPDF:": "Save every page as a PDF, in order. Pixels only: no text under a redaction, and no details about who made it.",
        "exportPreset:": "Save a PNG at this exact size; the aspect ratio is kept and nothing is enlarged.",
        "undo:": "Undo the last change.",
        "redo:": "Redo the change you just undid.",
        "undoOnActiveLayer:": "Undo the active layer's last change only, leaving later changes on other layers in place.",
        "revertLayer:": "Put the active layer's pixels back as they were at the last save.",
        "cut:": "Copy the selection to the clipboard, then clear it.",
        "copy:": "Copy the selection (or the whole image) to the clipboard as a PNG.",
        "copyMerged:": "Copy the selection as all visible layers show it together.",
        "pasteIntoNewImage:": "Open the clipboard image as a new document at its own size.",
        "showCanvasProperties:": "Change the canvas size or make its background transparent.",
        "toggleHistoryPanel:": "Show or hide every step you've taken, to jump back to any of them.",
        "toggleClipboardPanel:": "Show or hide the last 10 images you copied or pasted.",
        "toggleRulers:": "Show or hide pixel rulers along the canvas.",
        "toggleStatusBar:": "Show or hide the bar along the bottom of the window.",
        "shareDocument:": "Send the image with AirDrop, Messages, Mail and more.",
        "setDesktopPicture:": "Use the image as your desktop picture.",
        "runPageLayout:": "Choose the paper size and orientation for printing.",
        "printDocument:": "Print the image, scaled to fit the page.",
        "toggleLayers:": "Show or hide the Layers panel.",
        "togglePageSidebar:": "Show or hide the pages, down the left side.",
        "newPage:": "Add a blank page after this one, the same size, filled with Color 2.",
        "duplicatePage:": "Copy this page, with its layers, just after it.",
        "deletePage:": "Remove this page from the document.",
        "movePageUp:": "Move this page one place earlier.",
        "movePageDown:": "Move this page one place later.",
        "previousPage:": "Show the page before this one.",
        "nextPage:": "Show the page after this one.",
        "toggleAdjustmentsPanel:": "Show or hide the Adjustments panel, where an adjustment layer's settings live.",
        "newAdjustmentLayer:": "Add an adjustment layer: it changes how the layers below look, without changing their pixels.",
        "applyAdjustment:": "Turn the active adjustment layer into pixels on the layer below.",
        "newLayer:": "Add a transparent layer above the active one.",
        "duplicateLayer:": "Copy the active layer, with its settings, just above it.",
        "deleteLayer:": "Delete the active layer. The only layer, or a locked one, can't be deleted.",
        "mergeDown:": "Combine the active layer into the one below, keeping how they look.",
        "mergeVisible:": "Combine every visible layer into one. Hidden layers stay.",
        "flattenImage:": "Combine all visible layers into one and drop hidden layers.",
        "toggleLayerVisibility:": "Hide or show the active layer.",
        "toggleLayerLock:": "Lock the active layer against changes, or unlock it.",
        "showLayerProperties:": "Rename the active layer and change its blend mode and opacity.",
        "paste:": "Paste an image as a selection you can move and resize.",
        "delete:": "Clear the selected pixels to Color 2 (or transparency).",
        "selectAll:": "Select the whole image.",
        "deselect:": "Remove the selection, placing any moved pixels.",
        "invertSelection:": "Select everything that isn't selected, and nothing that is.",
        "zoomIn:": "Zoom in one step.",
        "zoomOut:": "Zoom out one step.",
        "actualSize:": "Show the image at 100%, one image pixel per screen point.",
        "zoomToFit:": "Fit the whole image in the window.",
        "togglePixelGrid:": "Show a line between pixels at 400% zoom and above.",
        "toggleBeforeAfter:": "Compare the image now with how it was opened or last saved.",
        "toggleFullScreen:": "Fill the screen with this window.",
        "cropToSelection:": "Trim the image to the selection's edges.",
        "applyOrientation:": "Turn or mirror the selection, or the whole image if nothing is selected.",
        "showResizeSkew:": "Change the size of the selection (or whole image) by percent or pixels, or slant it.",
        "setSymmetry:": "Mirror pencil, brush and eraser strokes across the image's center lines.",
        "invertColors:": "Turn colors into their opposites (black becomes white).",
        "showHueSaturation:": "Shift colors around the color wheel, or make them more or less vivid.",
        "desaturate:": "Turn the selection or image to grayscale.",
        "showAdjustPhoto:": "Exposure, light, color and detail sliders, Auto, and filters, in a panel at the side.",
        "showLevels:": "Set the black point, white point and midtones, with a histogram. Auto sets them from the image.",
        "autoContrast:": "Stretch the darkest pixels to black and the lightest to white, in one step.",
        "showCurves:": "Reshape the tones with a curve, for all colors together or one at a time.",
        "showSepia:": "Give the selection or image warm brown tones.",
        "showPosterize:": "Reduce each color channel to a few levels, for a flat poster look.",
        "showMotionBlur:": "Streak the selection or image along an angle, as if it moved.",
        "showAddNoise:": "Add grain, in color or monochrome.",
        "showEmboss:": "Turn the selection or image into a gray relief.",
        "selectSubject:": "Select the main subject of a photo, found on this Mac. With several, click the one you want.",
        "removeBackground:": "Make everything but the photo's subject transparent, with soft edges. Found on this Mac; nothing is uploaded.",
        "liftSubject:": "Copy the photo's subject onto a new layer, leaving this one as it is.",
        "showCrop:": "Crop with a box you drag: free, a set shape, or an exact pixel size.",
        "showStraighten:": "Turn the image a little to level a horizon or a crooked scan.",
        "showPerspective:": "Square up a photo of a whiteboard, a document or a building.",
        "showDropShadow:": "A soft shadow behind the image or the selected object, following its shape. The canvas grows to fit.",
        "showBorder:": "An outline around the image or the selected object, following its shape. The canvas grows to fit.",
        "showSpotlight:": "Dim, blur or desaturate everything outside the selection. Select the area to keep first.",
        "showVignette:": "Darken (or lighten) toward the edges of the selection or image.",
        "showGaussianBlur:": "Blur the selection (or image). Each separate selected area is blurred on its own.",
        "showPixelate:": "Turn the selection (or image) into large square blocks.",
        "showSharpen:": "Make edges crisper.",
        "applySolidFill:": "Cover every selected area with Color 1. The most secure way to hide text.",
        "showAutoRedact:": "Find emails, phone numbers, keys and more on this Mac, then hide the ones you choose.",
        "performMiniaturize:": "Minimize this window to the Dock.",
        "performZoom:": "Make this window as large as it needs to be.",
        "arrangeInFront:": "Bring all Colorbee windows to the front.",
    ]

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
        item.toolTip = tooltips[action]
        return item
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "Colorbee")
        menu.addItem(item("About Colorbee", "orderFrontStandardAboutPanel:"))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", "showSettings:", ","))
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
        menu.addItem(item("Paste into New Image", "pasteIntoNewImage:", "v", [.command, .shift]))
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
        menu.addItem(item("Export as PDF…", "exportPDF:"))
        let presets = NSMenu(title: "Export As")
        // Filled in when it opens, from the presets in Settings.
        presets.delegate = ExportPresetMenuTitles.shared
        menu.addItem(submenu(presets))
        menu.addItem(.separator())
        menu.addItem(item("Share…", "shareDocument:"))
        menu.addItem(item("Set as Desktop Picture", "setDesktopPicture:"))
        menu.addItem(.separator())
        menu.addItem(item("Page Setup…", "runPageLayout:", "p", [.command, .shift]))
        menu.addItem(item("Print…", "printDocument:", "p"))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(item("Undo", "undo:", "z"))
        menu.addItem(item("Redo", "redo:", "z", [.command, .shift]))
        menu.addItem(item("Undo on Active Layer", "undoOnActiveLayer:", "z", [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(item("Cut", "cut:", "x"))
        menu.addItem(item("Copy", "copy:", "c"))
        menu.addItem(item("Copy Merged", "copyMerged:", "c", [.command, .shift]))
        menu.addItem(item("Paste", "paste:", "v"))
        // The canvas handles the Delete key itself, so text fields keep their own Delete.
        menu.addItem(item("Delete", "delete:"))
        menu.addItem(.separator())
        menu.addItem(item("Select All", "selectAll:", "a"))
        menu.addItem(item("Deselect", "deselect:", "d"))
        menu.addItem(item("Invert Selection", "invertSelection:", "i", [.command, .shift]))
        menu.addItem(item("Select Subject", "selectSubject:"))
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
        menu.addItem(item("Layers", "toggleLayers:", "l"))
        menu.addItem(item("Adjustments Panel", "toggleAdjustmentsPanel:"))
        menu.addItem(item("History", "toggleHistoryPanel:", "y"))
        menu.addItem(item("Clipboard History", "toggleClipboardPanel:", "v", [.command, .option]))
        menu.addItem(item("Page Sidebar", "togglePageSidebar:", "2", [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(item("Show Rulers", "toggleRulers:", "r"))
        menu.addItem(item("Hide Status Bar", "toggleStatusBar:"))
        menu.addItem(.separator())
        menu.addItem(item("Enter Full Screen", "toggleFullScreen:", "f", [.command, .control]))
        return menu
    }

    private static func imageMenu() -> NSMenu {
        let menu = NSMenu(title: "Image")
        menu.addItem(item("Crop to Selection", "cropToSelection:", "x", [.command, .shift]))
        menu.addItem(item("Crop…", "showCrop:"))
        menu.addItem(item("Resize and Skew…", "showResizeSkew:", "e"))
        menu.addItem(item("Canvas Properties…", "showCanvasProperties:", "e", [.command, .option]))
        menu.addItem(.separator())
        let rotate = NSMenu(title: "Rotate")
        let flip = NSMenu(title: "Flip")
        for (index, orientation) in Orientation.allCases.enumerated() {
            let orientationItem = item(orientation.name.replacingOccurrences(of: "Rotate ", with: "").replacingOccurrences(of: "Flip ", with: ""), "applyOrientation:")
            orientationItem.tag = index
            (orientation == .flipHorizontal || orientation == .flipVertical ? flip : rotate).addItem(orientationItem)
        }
        menu.addItem(submenu(rotate))
        menu.addItem(item("Straighten…", "showStraighten:"))
        menu.addItem(item("Perspective Correction…", "showPerspective:"))
        menu.addItem(.separator())
        menu.addItem(item("Remove Background", "removeBackground:"))
        menu.addItem(item("Lift Subject to New Layer", "liftSubject:"))
        menu.addItem(.separator())
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

    /// Pages (FR-11.6). Next and Previous Page use Preview's keys.
    private static func pageMenu() -> NSMenu {
        let menu = NSMenu(title: "Page")
        menu.addItem(item("New Page", "newPage:"))
        menu.addItem(item("Duplicate Page", "duplicatePage:"))
        menu.addItem(item("Delete Page", "deletePage:"))
        menu.addItem(.separator())
        menu.addItem(item("Move Page Up", "movePageUp:"))
        menu.addItem(item("Move Page Down", "movePageDown:"))
        menu.addItem(.separator())
        let up = String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)), down = String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))
        menu.addItem(item("Previous Page", "previousPage:", up, [.command, .option]))
        menu.addItem(item("Next Page", "nextPage:", down, [.command, .option]))
        return menu
    }

    private static func layerMenu() -> NSMenu {
        let menu = NSMenu(title: "Layer")
        menu.addItem(item("New Layer", "newLayer:", "n", [.command, .shift]))
        menu.addItem(item("Duplicate Layer", "duplicateLayer:", "j"))
        menu.addItem(item("Delete Layer", "deleteLayer:", "\u{8}"))
        menu.addItem(.separator())
        menu.addItem(item("Merge Down", "mergeDown:", "e", [.command, .shift]))
        menu.addItem(item("Merge Visible", "mergeVisible:", "e", [.command, .option, .shift]))
        menu.addItem(item("Flatten", "flattenImage:"))
        menu.addItem(.separator())
        menu.addItem(submenu(adjustmentLayerMenu()))
        menu.addItem(item("Apply Adjustment", "applyAdjustment:"))
        menu.addItem(item("Revert Layer", "revertLayer:"))
        menu.addItem(.separator())
        menu.addItem(item("Hide Layer", "toggleLayerVisibility:"))
        menu.addItem(item("Lock Layer", "toggleLayerLock:"))
        menu.addItem(item("Layer Properties…", "showLayerProperties:"))
        return menu
    }

    /// One item per kind of adjustment layer; the tag is its position in `AdjustmentChoice.allCases`.
    private static func adjustmentLayerMenu() -> NSMenu {
        let menu = NSMenu(title: "New Adjustment Layer")
        for (index, choice) in AdjustmentChoice.allCases.enumerated() {
            let choiceItem = item(choice.title, "newAdjustmentLayer:")
            choiceItem.tag = index
            menu.addItem(choiceItem)
        }
        return menu
    }

    private static func adjustmentsMenu() -> NSMenu {
        let menu = NSMenu(title: "Adjustments")
        menu.addItem(item("Invert Colors", "invertColors:", "i"))
        menu.addItem(item("Hue/Saturation…", "showHueSaturation:"))
        menu.addItem(item("Desaturate", "desaturate:", "u", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Adjust Photo…", "showAdjustPhoto:"))
        menu.addItem(item("Levels…", "showLevels:"))
        menu.addItem(item("Auto Contrast", "autoContrast:"))
        menu.addItem(item("Curves…", "showCurves:"))
        menu.addItem(item("Sepia…", "showSepia:"))
        menu.addItem(item("Posterize…", "showPosterize:"))
        menu.addItem(.separator())
        // Each adjustment also comes as a layer that stays editable (FR-9.1).
        menu.addItem(submenu(adjustmentLayerMenu()))
        return menu
    }

    private static func effectsMenu() -> NSMenu {
        let menu = NSMenu(title: "Effects")
        menu.addItem(item("Gaussian Blur…", "showGaussianBlur:"))
        menu.addItem(item("Pixelate…", "showPixelate:"))
        menu.addItem(item("Sharpen…", "showSharpen:"))
        menu.addItem(item("Motion Blur…", "showMotionBlur:"))
        menu.addItem(.separator())
        menu.addItem(item("Add Noise…", "showAddNoise:"))
        menu.addItem(item("Emboss…", "showEmboss:"))
        menu.addItem(item("Vignette…", "showVignette:"))
        menu.addItem(.separator())
        menu.addItem(item("Drop Shadow…", "showDropShadow:"))
        menu.addItem(item("Border…", "showBorder:"))
        menu.addItem(item("Spotlight…", "showSpotlight:"))
        menu.addItem(.separator())
        let batch = NSMenu(title: "Batch Redact")
        batch.addItem(item("Blur…", "batchRedactBlur:"))
        batch.addItem(item("Pixelate…", "batchRedactPixelate:"))
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
        menu.removeAllItems()
        let size = (NSDocumentController.shared.currentDocument as? ImageDocument)?.canvasSize
        for (index, preset) in ExportPresetStore.shared.presets.enumerated() {
            var title = preset.name
            if let size {
                let target = preset.targetSize(for: size)
                let dimensions = "\(target.width) × \(target.height) px"
                title = target == size && preset.targetSize(for: size, allowEnlarging: true) != size
                    ? "\(preset.name) — \(dimensions) (original size)"
                    : "\(preset.name) — \(dimensions)"
            }
            let presetItem = NSMenuItem(title: title, action: #selector(ImageDocument.exportPreset(_:)), keyEquivalent: "")
            presetItem.tag = index
            presetItem.toolTip = "Save a PNG at this exact size; the aspect ratio is kept and nothing is enlarged."
            menu.addItem(presetItem)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Edit Presets…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ""))
    }
}
