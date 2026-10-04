# Review J: stages 1–7 against the FRD, and documents
Reviewed at commit: fc427a185d70d559a8e27f11b456ceed5833f65c
Checked:
- `MainMenu.swift`: every command in the FRD menu table is present with the FRD's shortcut, including §23 changes (Paste into New Image in File, Merge Visible ⌥⇧⌘E, Delete Layer ⌘⌫). No two defaults clash. Single-key tool defaults match FR-14.5.
- Core `Shortcuts.swift`:
  - The reserved list matches FR-15.3, and Shift is handled correctly (⇧⌘Z vs ⌘Z).
  - Reassign clears the other command; Reset and Reset All work as §23 says.
  - Export and import round-trip.
- `ShortcutStore.swift`:
  - Menus update live and drop the old key, submenus included.
  - Batch Redact's Blur/Pixelate and the duplicate New Adjustment Layer items share one id, so they update together with no false conflict.
  - Retitled items (Undo X, Hide/Show Layer) keep their key, and changes persist.
  - System-shortcut parsing works.
- Canvas keys reach only the canvas (not the text box, fields or sheets), and are blocked during an effect bar
- `DocumentWindow.swift` `validateMenuItem`: selection, layer and paste rules; locked and adjustment layer rules
- `AppDelegate.swift`, `DocumentWindowController.swift`: shortcuts are registered before the first window
- Defaults: new canvas 1920 × 1080 white, Pencil, black and white, D and X, size presets
- `StatusBar.swift` (zoom presets and limits, the pixel grid dimmed below 400%), `Galleries.swift`, `Settings.swift` (export presets and the last tab persist)
- `ImageDocument.swift`, Save As:
  - A layered document offers only `.colorproj`, and an opened image that gains layers becomes an untitled project, so the original is never flattened.
  - JPEG isn't offered for layered documents; Export flattens over Color 2.
  - WebP isn't in Export.
- Core `ImageCodec.swift`:
  - Images too large are refused before decoding; an empty or truncated file gives an error.
  - Gray, CMYK and indexed images convert to RGB.
  - JPEG flattens over Color 2 (FR-11.1).
- `ExportPreset.swift`: sizes clamped; menu tags match. `SaveSnapshot.swift`: background copy, Color 2 matte.
- Core `ProjectFile.swift`: size and area limits, negative ranges, length checks, unknown blend modes and adjustments, opacity and active-index clamping, an empty layer list, truncated data (except findings 19–20)
- `CustomColors.swift`, `Palettes.swift` (import renames a taken name; rename refuses one), `TextStyles.swift` (persistence, empty names refused)
- `LayersPanel.swift`: rename trims and refuses empty names; the eye, lock and footer buttons, the opacity slider and the Adjustment menu are labelled
- `HistoryPanels.swift`, `ClipboardHistory.swift` (paste refuses locked and adjustment layers; Clear works)
- `CanvasPropertiesSheet.swift`, `ResizeSkewSheet.swift`: limits and validation (except findings 7, 22, 26)
- Accessibility: color wells, swatch grid, toolbar tool buttons, gallery buttons and the sidebar switcher are labelled

Not re-reported: rounds 1 and 2 in `RESULTS.md`, and reviews H and I. The Color Eraser tolerance (FR-4.3) and `[`/`]` with Shapes are review I findings 6 and 10.

**Hand-tested by Leah on 2026-10-04:**
- **Confirmed:** findings 1, 2, 4, 5, 7, 15, 16, 17 and 23.
- **Finding 3:** couldn't be checked by hand. It stays reported on the code reading.
- **Finding 6:** confirmed. After ⇧⌘V and ⌘W, the pasted image didn't come back. (An earlier "it came back" was a mix-up in the test.)
- **Finding 17:** Leah asked why a preview wouldn't vanish when another tool is chosen. That's the §23 (2026-10-02) question: the decision says tools are unavailable while an effect's bar is open, so either grey the tools out or change the decision.
- **Finding 29 (accessibility):** not hand-tested; Leah accepts it on the code reading.
- **WebP:** confirmed. Saving a drawn-on `.webp` fails with "could not be saved" instead of offering another format.

**Leah's decisions (2026-10-04), for the FRD §23 log:**
- **Finding 2:**
  - A file Colorbee can't save back without losing something opens as an **untitled copy**, so the original is never overwritten. That covers multi-frame files (animated GIF, multi-page TIFF) and 16-bit images. Ordinary photos (JPEG, HEIC) keep editing in place, once finding 3 is fixed.
  - **Frame bar:** a multi-frame file opens frame 1 straight away. A slim bar at the top says "This GIF has N frames · Showing frame 1 · Choose Frame…".
  - Choose Frame… shows the frames as thumbnails, and clicking one opens that frame instead.
- **Finding 17:** option A. Grey out the toolbar tools while an effect's bar is open, matching the §23 (2026-10-02) decision and the menus.

## 1. After File ▸ Revert To, the window keeps editing a copy that's no longer saved
- **Severity:** Critical (everything done after a revert is silently lost; Export and Share send the reverted image, not what's on screen)
- **Confidence:** High
- **Where:**
  - `Sources/Colorbee/ImageDocument.swift:57-72`: `read(from:ofType:)` always makes a new `Editor` (lines 60 and 66).
  - `Sources/Colorbee/DocumentWindowController.swift:5, 8-10`: the window keeps the editor it was made with (`private let editor`).
  - `MainMenu.swift:172` (Revert To Saved).
- **What happens:**
  - Revert To Saved, Revert To ▸ Last Opened, and restoring from Browse All Versions all call `read(from:ofType:)` on the same document. That replaces `document.editor` with a new one.
  - The window still shows and edits the old editor, which the document no longer saves. The "Edited" mark goes away, but the picture doesn't change.
  - From then on, Save, autosave, Export and Share all use the hidden reverted copy. The hidden copy has no `onDocumentChange`, so edits on screen never mark the document edited.
  - This also undercuts the escape route for review H's finding 1 and finding 2 below.
- **How to trigger it:**
  1. Open any PNG (save a copy first). Draw a red line and press ⌘S.
  2. Draw a blue line.
  3. File ▸ Revert To ▸ Last Saved (the menu may read "Revert To Saved"). The blue line stays on screen, which is already wrong.
  4. File ▸ Export… as PNG and open the export in Preview: no blue line.
  5. Draw a green line, close the window (no Save prompt), and reopen the file: no blue or green line.
- **Why:** `read` builds a fresh editor each time, and the window controller doesn't follow it.
- **Test that would catch it:** After `revert(toContentsOf:ofType:)`, the window controller's editor is `document.editor`, or the shown canvas equals the file. Simplest fix: on a revert, load the new canvas into the existing editor (through history or by resetting it), not a new `Editor`.

## 2. Editing an animated GIF, multi-page TIFF or 16-bit image overwrites the original and silently loses data
- **Severity:** High (data loss to the user's original file, with no warning)
- **Confidence:** High
- **Where:**
  - Core `ImageCodec.swift:43` reads frame 0 only; nothing checks `CGImageSourceGetCount`.
  - `:55-57` stores 8 bits per channel.
  - The encoder writes no properties.
  - `ImageDocument.swift:32-34` (`autosavesInPlace`) and `:139-155` save back in the opened file's type.
  - `project.yml` gives GIF and TIFF the Editor role.
- **What happens:**
  - The first edit is autosaved in place over the user's file:
    - an animated GIF becomes a still image;
    - a multi-page TIFF keeps only page 1;
    - a 16-bit PNG or TIFF becomes 8-bit;
    - gray and CMYK files become RGB;
    - photos lose their date, camera, GPS and DPI;
    - JPEG and HEIC are re-encoded at quality 90.
  - FR-11.1 says a GIF "opens the first frame", but nothing says it's then saved over. AC-15 says files open "and save again with no unexpected loss".
  - The only way back is Versions, which finding 1 breaks.
- **How to trigger it:** Copy an animated GIF (any reaction GIF) or a multi-page TIFF (a scanned document) to the Desktop. Open the copy in Colorbee, draw one dot, and close the window. Select the file in Finder and press Space: the GIF no longer animates, or the TIFF has one page.
- **Why:** Lossy formats and lossy loading are treated the same as a plain PNG.
- **Test that would catch it:** Core: decoding a 2-frame GIF reports "more frames" (or a lossy-load flag). In `ImageDocument`, such a file opens as an untitled copy (like an image that gains layers), or the user is warned before the first save. Leah's decision on which.

## 3. Photos taken in portrait open sideways, and saving makes them sideways for good
- **Severity:** High (a common case: any iPhone photo; and the change is written back to the file)
- **Confidence:** High for JPEG; Medium for HEIC
- **Where:** Core `ImageCodec.swift:43` (`CGImageSourceCreateImageAtIndex(source, 0, nil)`; `kCGImagePropertyOrientation` is never read). The only orientation-aware code is the Clipboard History thumbnail (`ClipboardHistory.swift:70`).
- **What happens:** The raw sensor pixels are loaded, so a portrait photo lies on its side. The first edit autosaves those pixels with no orientation tag, so the file is now sideways in Photos and Finder too. Dropping a photo onto the canvas does the same. A Clipboard History thumbnail shows it upright, but clicking it pastes it sideways.
- **How to trigger it:** AirDrop a photo taken on an iPhone held upright to the Mac (a copy). Open it in Colorbee: it's turned 90°. Draw a dot, close it, and open it in Preview: it's sideways there too.
- **Why:** Orientation metadata is ignored.
- **Test that would catch it:** Core: a 2 × 1 JPEG with Orientation 6 decodes to 1 × 2, turned. Fix: pass `kCGImageSourceCreateThumbnailWithTransform` with a full-size thumbnail, or apply the orientation after decoding.

## 4. ⌘⌫ while typing text deletes the layer, not the text
- **Severity:** Medium (the layer's pixels vanish along with the text; Undo brings the layer back, but the text is no longer editable)
- **Confidence:** Medium-High
- **Where:** `Sources/Colorbee/MainMenu.swift:266` (Delete Layer ⌘⌫); `DocumentWindow.swift:304-305` (`deleteLayer:` is enabled whenever `canDelete`, even while text is being typed); `CanvasTextView.swift` (doesn't claim ⌘⌫ in `performKeyEquivalent`)
- **What happens:** On a Mac, ⌘⌫ in a text box deletes to the start of the line. Menu key equivalents are checked before the text box's key handling, so Layer ▸ Delete Layer runs instead. It places the text first (`finishInteractions`), then deletes the layer. Other menu keys behave the same way (⌘I places the text and inverts the image), but ⌘⌫ is the one people type while editing text.
- **How to trigger it:**
  1. Layer ▸ New Layer (⇧⌘N).
  2. Text tool, click the canvas, and type "hello world".
  3. Press ⌘⌫. The text and the layer disappear, and the Layers panel loses a row.
- **Why:** Nothing gives the text box priority for keys it uses.
- **Test that would catch it:** `validateMenuItem` returns false for `deleteLayer:` (and other pixel commands) while the text box is first responder. Or `CanvasTextView.performKeyEquivalent` handles ⌘⌫ itself.

## 5. Moving a standard shortcut (Undo, Copy, Save, …) onto a key in use names the wrong command and silently takes the key
- **Severity:** Medium (FR-15.3: a conflict names the other command and offers Reassign)
- **Confidence:** High
- **Where:** Core `Shortcuts.swift:150-152` (when the command still has its standard default, `.standard(name:)` is returned before the `usedBy` lookup); `Sources/Colorbee/ShortcutSettings.swift:165-166` (the message pairs the *new* key with the *old* key's name)
- **What happens:** Giving Undo ⌘I shows "⌘I is the standard shortcut for Undo", which is wrong both ways. It never mentions Invert Colors, which loses ⌘I when you click Change.
- **How to trigger it:**
  1. Settings ▸ Shortcuts. Click Undo's ⌘Z and press ⌘I.
  2. Read the alert, then click Change.
  3. Adjustments ▸ Invert Colors now has no shortcut.
  4. Worse: give Undo ⌘C. The alert claims ⌘C is Undo's standard shortcut, and Copy silently loses ⌘C.
- **Why:** Two different warnings (giving up a standard key, taking a used one) are folded into one, checked in the wrong order.
- **Test that would catch it:** Core: `check(⌘I, for: "undo:")` reports both the standard key being given up and Invert Colors losing ⌘I (or `.usedBy(invert)` with a flag). Then the alert says both.

## 6. Paste into New Image, and images dropped as new documents, aren't kept safe
- **Severity:** Medium (FR-12: "Untitled documents are kept safe too"; AC-20)
- **Confidence:** High for closing; Medium-High for quit and relaunch
- **Where:** `Sources/Colorbee/ImageDocument.swift:21-29` (`open(_:)` never marks the document changed), called from `DocumentWindow.swift:197-207` and `CanvasView.swift:953`
- **What happens:** The new untitled document has no changes, so ⌘W closes it without asking. It's never autosaved, so it doesn't come back after quitting and relaunching. The image survives only in Clipboard History.
- **How to trigger it:** Take a screenshot to the clipboard (⌃⇧⌘4), then ⇧⌘V. Press ⌘W: it closes with no prompt. Or ⇧⌘V, quit, and relaunch: the window doesn't come back.
- **Why:** No `updateChangeCount(.changeDone)` after creating it.
- **Test that would catch it:** After `ImageDocument.open`, `isDocumentEdited` is true.

## 7. Menus still act on the image behind the Resize and Skew and Canvas Properties dialogs
- **Severity:** Low-Medium (OK then applies to a different selection or size than the dialog shows)
- **Confidence:** Medium (the same mechanism as review E finding 2, which was fixed for Auto-Redact only)
- **Where:** `Sources/Colorbee/DocumentWindow.swift:224` (only `activeEffect` and `autoRedact` grey out the menus); `DocumentView.swift:63-64`; `Editor.swift:2161-2169` (`apply` re-reads the selection at OK time)
- **How to trigger it:**
  1. Select a 100 × 100 area, then Image ▸ Resize and Skew… (it says "Applies to the selection").
  2. With it open, choose Edit ▸ Deselect from the menu bar, then click OK.
  3. The whole image is resized to 100 × 100.
  - Or: Image ▸ Canvas Properties… on a 1920 × 1080 image, then Image ▸ Rotate ▸ 90° Clockwise, then OK. The rotated image is cut to 1920 × 1080.
- **Test that would catch it:** `validateMenuItem` returns false (except zoom) while either dialog is open.

## 8. The shortcut recorder catches keys typed in any Colorbee window
- **Severity:** Low
- **Confidence:** High
- **Where:** `Sources/Colorbee/ShortcutSettings.swift:122-125` (a local key monitor that swallows every key without checking `event.window`)
- **How to trigger it:** Settings ▸ Shortcuts, click Fill's "G" ("Type a shortcut…"). Click a document window and press B: instead of choosing the Brush, an alert asks to reassign B. Also worth checking: close Settings while it says "Type a shortcut…", then type in a document.

## 9. Keys the canvas keeps for itself can be assigned, and then don't work
- **Severity:** Low
- **Confidence:** High
- **Where:** Core `Shortcuts.swift:145-146`; `CanvasView.swift:798-831`
- **What happens:** §23 (stage 7c) says Space, the arrows, Return, Esc and Delete stay fixed. But Space, the arrows and Return are accepted for tools. The canvas handles them first, so the tool never gets them, and the tool's old key is gone. Menu commands accept ⌘-arrows, which then override ⌘-arrow selection resizing (FR-3.3).
- **How to trigger it:** Settings ▸ Shortcuts ▸ Pencil, press Space: accepted. Space still only pans, and P no longer picks the Pencil.
- **Test that would catch it:** Core: `check(space, for: <tool>)` (and arrows, Return) is refused.

## 10. macOS's tab shortcuts aren't protected
- **Severity:** Low
- **Confidence:** Medium
- **Where:** Core `Shortcuts.swift:79-98` (reserved list); `ShortcutStore.swift:37`
- **What happens:** Show All Tabs (⇧⌘\), Show Next Tab (⌃⇥) and Show Previous Tab (⌃⇧⇥) can be given to Colorbee commands with no warning. FR-15.3 says standard Mac shortcuts are blocked.
- **How to trigger it:** Give Flatten ⌃⇥: accepted silently. With two documents as tabs, ⌃⇥ then either doesn't switch tabs or doesn't flatten.

## 11. Window menu commands are missing from Settings ▸ Shortcuts
- **Severity:** Low (§23 stage 7c says Minimize, Zoom and Bring All to Front are listed with a padlock)
- **Confidence:** High
- **Where:** `Sources/Colorbee/ShortcutStore.swift:37` (`skippedMenus` includes "Window")
- **How to trigger it:** Settings ▸ Shortcuts, search "Minimize": nothing.

## 12. Clearing ⌘Z, ⌘C, ⌘V, ⌘X, ⌘A or ⌘S asks nothing
- **Severity:** Low (FR-15.3: these change only after a confirmation)
- **Confidence:** High
- **Where:** `Sources/Colorbee/ShortcutSettings.swift:140-143` (Delete calls `store.assign(nil, to: id)` without `check`)
- **How to trigger it:** Settings ▸ Shortcuts, click Undo's ⌘Z, press Delete: gone at once, no question.

## 13. Importing a shortcuts file skips the editor's checks
- **Severity:** Low
- **Confidence:** High
- **Where:** Core `Shortcuts.swift:208-220`
- **What happens:**
  - Two commands with the same key in one file: one silently loses its shortcut.
  - Standard shortcuts move without confirmation, and reserved Mac keys are accepted.
  - A hand-edited `"key": "Z"` skips lowercasing (the decoder doesn't use `KeyShortcut.init`) and becomes ⇧⌘Z in the menu, clashing with Redo.
- **How to trigger it:** Import a `.colorbeekeys` file containing `{"version":1,"shortcuts":{"copy:":{"key":"k","modifiers":8},"cut:":{"key":"k","modifiers":8}}}`. One of Copy or Cut ends up with no shortcut and no message.
- **Test that would catch it:** Core: importing duplicate keys or an uppercase key reports or normalizes them.

## 14. Tooltips keep showing the default keys after a shortcut change
- **Severity:** Low
- **Confidence:** High
- **Where:** `Sources/Colorbee/ToolAppearance.swift:24-40`, `Galleries.swift:20, 126`, `DocumentToolbar.swift:279, 351`, `StatusBar.swift:100, 149, 163` (keys written into the strings, such as "Pencil (P)" and "Layers (⌘L)")
- **How to trigger it:** Change Pencil to Q in Settings, then hover over the Pencil in the toolbar: it still says (P).

## 15. View ▸ Layers or Adjustments Panel closes the whole sidebar, including History and Clipboard History
- **Severity:** Low (FR-1.3: each panel shows or hides on its own)
- **Confidence:** High
- **Where:** `Sources/Colorbee/Editor.swift:2296-2325` (`if !showsAdjustmentsPanel { isSidebarOpen = false }` ignores the History and Clipboard History flags; `togglePanel` checks all four)
- **How to trigger it:** ⌘L to open Layers. View ▸ Adjustments Panel to hide it. ⌘Y to show History. Press ⌘L: the sidebar closes and History goes with it.

## 16. ⌘Z doesn't discard an unplaced shape when there's nothing else to undo
- **Severity:** Low (§23 stage 3b: ⌘Z discards a shape that hasn't been placed)
- **Confidence:** High
- **Where:** `Sources/Colorbee/DocumentWindow.swift:247-249` (`return editor.undoActionName != nil`, ignoring `pendingShape`)
- **How to trigger it:** New document, draw a rectangle and don't place it. Edit ▸ Undo is greyed out and ⌘Z beeps (Esc works). With earlier steps, the menu says "Undo Pencil" but discards the shape instead.

## 17. Toolbar tools stay clickable while an effect's bar is open
- **Severity:** Low (§23, 2026-10-02: tools are unavailable until Apply or Cancel)
- **Confidence:** High
- **Where:** `Sources/Colorbee/DocumentView.swift:11-12` (only the palette bar is disabled); `DocumentToolbar.swift:85`; `selectTool` → `finishInteractions` → `cancelEffect`
- **How to trigger it:** Effects ▸ Gaussian Blur…, drag the slider, then click the Pencil in the toolbar. The preview vanishes without asking.

## 18. Close, Minimize, Zoom and Full Screen are greyed out in the menus during an effect's bar
- **Severity:** Low
- **Confidence:** Medium (may be intended)
- **Where:** `Sources/Colorbee/DocumentWindow.swift:224-226` (only zoom and grid commands are allowed; window commands are caught too, although §23 lists only tools, editing menus, Save and Export)
- **How to trigger it:** Effects ▸ Gaussian Blur…, then look at File ▸ Close and the Window menu (⌘W does nothing). The red close button still works.

## 19. A damaged project whose layers share an id crashes Colorbee
- **Severity:** Low (damaged or hand-edited files only)
- **Confidence:** High
- **Where:** Core `ProjectFile.swift:98-107` (doesn't check ids are unique); the crash is at `Sources/Colorbee/Editor.swift:612` (`Dictionary(uniqueKeysWithValues:)`)
- **How to trigger it:** Save a two-layer project. Open the `.colorproj` in a text or hex editor, paste the first layer's `"id"` over the second's (same length), save, and open it in Colorbee: crash.
- **Test that would catch it:** In `DamagedFileTests`, duplicate ids throw `.damaged`.

## 20. A damaged project with a huge pixel offset crashes Colorbee
- **Severity:** Low
- **Confidence:** High
- **Where:** Core `ProjectFile.swift:101` (`blobs.startIndex + range.upperBound` overflows before the check on line 102)
- **How to trigger it:** Edit a layer's `"pixels"` to `[9223372036854775807,9223372036854775807]` and open it.
- **Test that would catch it:** That manifest throws `.damaged`. Fix: check the range against `blobs.count` before adding.

## 21. Importing a palette with an out-of-range custom color crashes Colorbee
- **Severity:** Low
- **Confidence:** High
- **Where:** `Sources/Colorbee/Palettes.swift:94-105` (checks the swatch count only); the crash is at `CustomColors.swift:56` (`UInt32(packed[index])` traps above 4,294,967,295)
- **How to trigger it:** Export a palette, change one `custom` value to `5000000000` in TextEdit, and import it.
- **Test that would catch it:** Importing it throws or ignores that slot.

## 22. Typing "NaN" as a size in Resize and Skew may crash Colorbee
- **Severity:** Low
- **Confidence:** Medium (depends on the number field accepting "NaN")
- **Where:** `Sources/Colorbee/ResizeSkewSheet.swift:42-48` (NaN passes `< 1` and `> maxSide`, then `settings.fits` converts it with `Int(…rounded())`, which traps)
- **How to trigger it:** Image ▸ Resize and Skew…, choose Pixels, type `NaN` in Horizontal, press Tab.
- **Test that would catch it:** Validation with NaN returns a message. Fix: also require `isFinite`.

## 23. "Save Palette As… Paint Classic" makes a second Paint Classic that can't be renamed or deleted
- **Severity:** Low
- **Confidence:** High
- **Where:** `Sources/Colorbee/Palettes.swift:63-68` (`saveCurrent` checks `saved` only, not the built-in name); `:311` (`ForEach(store.all, id: \.name)` gets two rows with one id); `:325-327` (Rename and Delete are disabled for that name)
- **How to trigger it:** Palette menu ▸ Save Palette As…, name it `Paint Classic`. The list shows two, and Rename and Delete stay greyed out, even after relaunch.

## 24. Deleting the palette in use keeps its colors under the name "Paint Classic"
- **Severity:** Low
- **Confidence:** High
- **Where:** `Sources/Colorbee/Palettes.swift:77-81` (changes `activeName` without loading Paint Classic's colors)
- **How to trigger it:** Save a palette "Mine" with a changed swatch, then Delete Palette. The bar says Paint Classic but shows Mine's colors. Export Palette… writes them as "Paint Classic".

## 25. Renaming a text style allows a name that's already taken
- **Severity:** Low
- **Confidence:** High
- **Where:** `Sources/Colorbee/TextStyles.swift:45-49` (no duplicate check; palettes have one)
- **How to trigger it:** Save two text styles, rename the second to the first's name. Both show; saving a style under that name replaces only the first.

## 26. Canvas Properties gives the wrong reason when a size is refused
- **Severity:** Low
- **Confidence:** High
- **Where:** `Sources/Colorbee/CanvasPropertiesSheet.swift:19-21, 44-46` (the 256-megapixel limit is enforced, but the message only says "Sizes run from 1 to 30,000 px")
- **How to trigger it:** Canvas Properties, 20000 × 20000: OK is greyed out, and the message doesn't explain why.

## 27. Opening a damaged file shows a code, not a message; Open in Colorbee and drops fail silently
- **Severity:** Low
- **Confidence:** Medium
- **Where:** Core `ImageCodec.swift:16-23` (only `.tooLarge` has a description); `ProjectFile.swift:11-14` (`Failure` has none). `Settings.swift:160` and `CanvasView.swift:944` ignore the open error; `CanvasView.swift:948` uses `try?`.
- **How to trigger it:** Rename a text file to `broken.png`. File ▸ Open it: an alert with something like "ColorbeeCore.ImageCodecError error 0". Right-click it in Finder ▸ Services ▸ Open in Colorbee, or drop it on the gray area: nothing happens.

## 28. After relaunch, an image that became a project loses its name, and windows forget zoom and panels
- **Severity:** Low (FR-12: windows come back "exactly as they were")
- **Confidence:** High for the name; Medium-High for zoom and panels
- **Where:** `Sources/Colorbee/ImageDocument.swift:14, 105-118` (`projectName` isn't saved with restorable state); nothing encodes zoom, scroll or open panels
- **How to trigger it:** Open `photo.png`, ⇧⌘N (new layer), then quit and relaunch. The title is "Untitled", not "photo", and the zoom is back to fit.

## 29. Accessibility: controls with no VoiceOver name or state
- **Severity:** Low
- **Confidence:** High unless noted
- **Where and what:**
  - **A1.** The palette bar's Alpha slider (`PaletteBar.swift:19`) and the status bar's zoom slider (`StatusBar.swift:138-144`) have no label. The zoom slider reads 0–1, not a zoom percentage.
  - **A2.** The five Size presets (`DocumentToolbar.swift:120-129`) are drawn bars with no label and no selected state.
  - **A3.** Shape gallery buttons (`Galleries.swift:147-154`) read the SF Symbol's name, for example "app" for Rounded Rectangle and "sparkle" for 4-Point Star. Confidence Medium on the exact words.
  - **A4.** Clipboard History thumbnails (`HistoryPanels.swift:84-100`) are image-only buttons with no label.
  - **A5.** The History panel (`HistoryPanels.swift:32-57`) shows the current and undone steps by color and dimming only.
  - **A6.** Layers can only be reordered by dragging (`LayersPanel.swift:128-136`); there's no menu command or accessibility action.
  - **A7.** In the status bar, the Pixel Grid and Symmetry on/off state is color only (`StatusBar.swift:71-86`), and the readouts are bare numbers or "—".
  - **A8.** For custom color slots, Remove is Control-click only and "set Color 2" is right-click only. The VoiceOver swatches (`PaletteBar.swift:217-228`) offer one action.
- **How to check:** Turn on VoiceOver (⌘F5) and move through the palette bar, toolbar Size control, status bar, Shapes gallery, Clipboard History and History panels.
- **Test that would catch it:** By hand, or with Accessibility Inspector's audit (Xcode ▸ Open Developer Tool ▸ Accessibility Inspector ▸ Audit).

## Worth a one-minute hand check
- **WebP saving:** WebP is a Viewer type, so saving would hit `encodingFailed`, which has no message. Open a `.webp` file, draw, then ⌘S (or wait for autosave). Does a sensible save panel appear (offering PNG), or an error alert?
