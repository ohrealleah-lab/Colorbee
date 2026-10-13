# Review P: the app layer, tests and build (round 5)
Reviewed at commit: eccf0c1571ac06e5470b598048ab6c2e3309093b
Checked:
- Launch flags: `main.swift`, `TestHost.swift`, `AppDelegate.swift`, `HelpDump.swift`, `HelpShots.swift`, `Snapshot.swift` (new keys), `Benchmark.swift`. All are read from `UserDefaults.standard` (launch arguments) or the `COLORBEE_TESTING` environment variable. Colorbee registers no URL scheme, and a file, a Services request or a drop can't set a default or an environment variable, so a normal user can't trigger them by accident. Each writes only to the path it's given. `HelpShots` saves `SettingsTab` into the real preferences (harmless). No finding beyond 10 below.
- Tools and keys: `ShortcutStore` (new J, S, K, N defaults; a saved change that already used one of those keys takes it, and the new tool goes without, as `ShortcutBook.assign` does), `CanvasView` key handling and drags, `Editor` strokes with Shift (`AxisLock`) and Symmetry, pressure, Retouch sizes per kind, `[` `]`, the Size control's range, `ToolAppearance` and the gallery tooltips (they follow changed shortcuts).
- Panels: the sidebar switcher, `togglePanel`, `openSidebar`, `settlePanels`, "Only the layer below" (enabling, locked layers), Merge Adjustment's availability in the menu and the panel, the Feather sheet and its tint, the Step Badge "Next" field, Retouch options.
- Menus: `DocumentWindow.validateMenuItem` for Copy Text, Feather…, Remove Red-Eye, Merge Adjustment and Undo Step Badge; `ImageDocument.validateUserInterfaceItem`.
- Tests: all eight files in `Tests/ColorbeeTests`, checked against the Editor code they drive.
- Build: `project.yml` (test scheme, `COLORBEE_TESTING`, `-ApplePersistenceIgnoreState`), `Makefile` (`test`, `app-test`, `coverage`, `help`, `help-shots`), `.github/workflows/build-release.yml`, `Scripts/make-beta.sh`, `Scripts/help-shots.sh`, `Scripts/help-pages.py` (every value written into HTML goes through `html.escape`, and the fixed strings hold nothing that needs escaping: no finding).

---

## 1. Menu commands still work behind the Feather sheet, and OK then puts back a stale selection
- **Severity:** Medium
- **Confidence:** High
- **Where:** `Sources/Colorbee/DocumentWindow.swift:345` (the "only viewing commands while a sheet is open" check), `Sources/Colorbee/Editor.swift:3948` (`blocksDocumentCommands`), `Sources/Colorbee/Editor.swift:2279–2299` (`beginFeather`, `applyFeather`), `Sources/Colorbee/DocumentView.swift:100`
- **What happens:** While Edit ▸ Feather… is open, every Edit, Image, Layer and Page command still works on the image behind it, and so do Save, Export, Share, Print and Revert. When you then click OK, Colorbee replaces the selection with the feathered copy of the selection *as it was when the sheet opened*. So:
  - After Image ▸ Crop to Selection behind the sheet, the red tint and the new selection land in the wrong place (shifted by the crop).
  - After Edit ▸ Deselect behind the sheet, OK brings the selection back.
  - After Page ▸ Next Page behind the sheet, OK puts page 1's selection on page 2.
- **How to trigger it:** Test file: `TestImages/Stage 9 Practice Photo.png`.
  1. Open the photo. Draw a selection box in the middle of it, away from the edges.
  2. Choose Edit ▸ Feather…. Leave the sheet open.
  3. Press ⇧⌘X (Image ▸ Crop to Selection). **Expected:** nothing happens, or the menu item is greyed out. **Bug:** the image is cropped behind the sheet. The red tint no longer lines up with the picture.
  4. Click OK. **Bug:** the marching ants sit somewhere other than where you selected. A selection near the right or bottom edge may disappear entirely.
  5. Second version: draw a box, open Feather…, press ⌘D (Deselect), then click OK. **Bug:** the selection comes back.
- **Why:** The check that greys out commands behind sheets covers `activeEffect`, `autoRedact`, `isResizeSkewOpen` and `isCanvasPropertiesOpen` only. The Feather sheet (`featherRadius != nil`) isn't in it, and neither is it in `blocksDocumentCommands`, which greys out Save, Export, Share, Print and Revert "behind any sheet" (§23, 2026-10-05). Menu commands reach the document window through the main window's responder chain while a sheet is key (review E, finding 2). `applyFeather` then commits `marqueePreview`, worked out from `featherOriginal` when the sheet opened: `recordingChanges { SelectionActions.select(feathered, mode: .replace, …) }`. Nothing clears or redoes that preview when the selection, canvas size or page changes. (`select` clips to the canvas, so this doesn't crash.)
- **Test that would catch it:** An app test: select a box, `beginFeather()`, then `cropToSelection()` (or `deselect()`), then `applyFeather()`. The selection should be empty, or stay as the crop left it. Also check `blocksDocumentCommands` is true while `featherRadius != nil`.

## 2. The release job runs a third-party action while Leah's Developer ID key is unlocked and usable by any program
- **Severity:** Medium (a leak of the signing key, though only if that action were ever compromised)
- **Confidence:** Medium (a risk that needs no bug in Colorbee, not a bug that shows today)
- **Where:** `.github/workflows/build-release.yml:72` (`security import … -A`), `:96` (`softprops/action-gh-release@v2`), `:106` ("Remove the signing keychain" runs after it), `:25` and `:96` (actions pinned to movable tags), `:15–16` (`contents: write` for every run)
- **What happens:** On a tag push, the Developer ID certificate and its private key are imported into a keychain with `-A`. That means any program on the runner may use the private key, and export it, without asking. The keychain stays unlocked and in the search list until the last step. Before that, the job runs `softprops/action-gh-release@v2`, a third-party action fetched by a tag its owner can move to new code at any time. If that action, or its tag, were ever compromised (this happened to a widely used action, `tj-actions/changed-files`, in 2025), it could sign malware as Leah or copy her private key out. Homebrew's latest `xcodegen` also runs inside `make-beta.sh` while the keychain is open and the notary key file is on disk.
- **How to trigger it:** Not by hand. Read the workflow: the publish step at line 96 comes before the keychain is deleted at line 106.
- **Why:** `-A` is "allow all applications". Deleting the keychain is the last step. Third-party actions run in the same job as the secrets.
- **Test that would catch it:** None. The fix is in the workflow itself:
  - Import the key with `-T /usr/bin/codesign` (and, if needed, `-T /usr/bin/security`) instead of `-A`.
  - Delete the signing keychain right after `make-beta.sh`, before publishing. Or publish with the `gh` command line tool that's already installed (`gh release create`) instead of a third-party action.
  - Pin `actions/checkout` and any remaining action to a full commit hash.
  - Give `contents: write` only to the tag job's publish step.

## 3. Adding a layer with every panel switched off opens an empty sidebar
- **Severity:** Low
- **Confidence:** High
- **Where:** `Sources/Colorbee/Editor.swift:3304–3307` (`addLayer` sets `isSidebarOpen = true` directly), compared with `openSidebar()` at `:3268`
- **What happens:** If you've switched off every sidebar panel, then Layer ▸ New Layer (⇧⌘N), or the Layers panel's + button, opens the sidebar with no panel in it: just the four switcher buttons over an empty glass pane. Leah decided on 2026-10-10 that the sidebar is "never an empty shell": opening it with no panel chosen shows the Layers panel.
- **How to trigger it:** Test file: `TestImages/Help/Sample Screenshot.png`.
  1. Open the screenshot. If the sidebar is closed, click the Sidebar button in the toolbar.
  2. In the row of four buttons at the top of the sidebar, click each one that's lit (Layers, then Adjustments) so none are lit. The sidebar closes.
  3. Press ⇧⌘N (Layer ▸ New Layer). **Bug:** the sidebar opens with nothing in it but the four buttons. **Expected:** it opens showing the Layers panel.
- **Why:** `addLayer()` does `isSidebarOpen = true` without the "no panel chosen, show Layers" step in `openSidebar()`. The toolbar button, ⌘L and the switcher all go through `togglePanel` or `openSidebar`, so only this path skips it.
- **Test that would catch it:** An app test: turn off all four panel flags with `togglePanel`, call `addLayer()`, and expect `isSidebarOpen` and at least one panel (Layers) to be on.

## 4. Switching off the last panel during Adjust Photo closes its sliders, and no toolbar button brings them back
- **Severity:** Low
- **Confidence:** High
- **Where:** `Sources/Colorbee/LayersPanel.swift:61–63` (the switcher now calls `togglePanel`), `Sources/Colorbee/Editor.swift:3242–3250`, `Sources/Colorbee/DocumentToolbar.swift:368` and `:384` (Layers and Sidebar buttons disabled during Adjust Photo)
- **What happens:** While Adjust Photo is open, the sidebar shows its sliders, but the four switcher buttons are still live. Switching off the last lit one now closes the whole sidebar (new since this round), taking Adjust Photo's sliders and its Apply, Cancel and As Adjustment Layer buttons with it. The toolbar's Sidebar and Layers buttons are greyed out during Adjust Photo (review D, finding 5), so there's no visible way back. ⌘L, or Apply or Cancel in the bar under the toolbar, still work. This is the same problem review D5 fixed for the toolbar, coming back through the switcher.
- **How to trigger it:** Test file: `TestImages/Stage 9 Practice Photo.png`.
  1. Open the photo and choose Adjustments ▸ Adjust Photo…. The sliders show in the sidebar.
  2. At the top of the sidebar, click the Layers button, then the Adjustments button (whichever are lit), until none is lit.
  3. **Bug:** the sidebar closes and the sliders are gone. The toolbar's Sidebar and Layers buttons are greyed out.
- **Why:** `togglePanel` closes the sidebar when no panel flag is left on (`if !showsAnyPanel { isSidebarOpen = false }`), but during Adjust Photo the sidebar holds Adjust Photo, not the panels.
- **Test that would catch it:** An app test: `beginEffect(.adjustPhoto)`, switch off every panel with `togglePanel`, and expect `isSidebarOpen` to stay true while `activeEffect == .adjustPhoto`. (Or disable the switcher during Adjust Photo.)

## 5. The Feather preview is worked out on the main thread for every slider movement
- **Severity:** Low (performance rule: "the main thread never blocks for more than a frame")
- **Confidence:** Medium
- **Where:** `Sources/Colorbee/Editor.swift:2287–2292` (`setFeatherRadius`), `Packages/ColorbeeCore/Sources/ColorbeeCore/SelectionMask.swift:180–206` (`feathered`, `trimmed`)
- **What happens:** Each tick of the Feather slider feathers the whole selection again on the main thread. That means copying the mask pixel by pixel through a subscript, three vImage box blurs, then scanning every value again in `trimmed()`. On a large photo with a large selection (Select All on a 4000 × 3000 photo is 12 million mask pixels; on the 8000 × 8000 soak size, 64 million), dragging the slider will stutter: by estimate tens of milliseconds per tick at 12 MP, and a few hundred at 64 MP.
- **How to trigger it:** Test file: `TestImages/Stage 9 Practice Photo.png`, enlarged first so the effect is easy to see.
  1. Open the photo. Choose Image ▸ Resize/Skew (⌘E) and enlarge it to about 6000 px wide.
  2. Select All (⌘A), then choose Edit ▸ Feather….
  3. Drag the slider back and forth quickly. **Bug:** the slider and tint lag behind the pointer. Compare with a small selection box, which stays smooth.
- **Why:** `setFeatherRadius` calls `original.feathered(...)` synchronously. Nothing is thrown away between ticks, and nothing runs off the main thread.
- **Test that would catch it:** A Release-only time limit in `PerformanceTests`: `feathered(radius: 50)` on a 4000 × 3000 mask within one frame (16 ms). Or move the preview into the background with a generation check, as the effect previews do.

## 6. Batch Redact ▸ Solid Fill is greyed out on a locked or adjustment layer, though it redacts every layer
- **Severity:** Low
- **Confidence:** High
- **Where:** `Sources/Colorbee/DocumentWindow.swift:485–486` (`applySolidFill(_:)` is in `pixelCommands`), `Sources/Colorbee/Editor.swift:3049` (`applySolidFill` redacts every layer)
- **What happens:** When the active layer is locked or is an adjustment layer, Effects ▸ Batch Redact ▸ Solid Fill is greyed out. Blur… and Pixelate… in the same submenu stay available, and so does the new Redact Brush. All of them redact every layer under the selection (§23, 2026-10-04; FR-9.6). So the safest treatment (FRD: "the most secure way to hide text") is the one that's missing, nudging someone towards Blur. This predates round 5 but wasn't reported. The Redact Brush working on any layer now makes the gap stand out.
- **How to trigger it:** Test file: `TestImages/Help/Sample Screenshot.png`.
  1. Open the screenshot. Choose Layer ▸ New Adjustment Layer ▸ Invert. It becomes the active layer.
  2. Draw a selection box over the made-up email address.
  3. Open Effects ▸ Batch Redact. **Bug:** Solid Fill is greyed out, while Blur… and Pixelate… are available.
  4. (Same with a locked layer: Layer ▸ Lock Layer on the background, then repeat step 3.)
- **Why:** `pixelCommands` greys out "commands that change the active layer's pixels", but `applySolidFill` calls `redactEveryLayer`, which works on every layer with pixels under the selection and refuses with a message only when a *locked layer with pixels there* is in the way.
- **Test that would catch it:** Hard to test without menus. Checking by hand is enough. The fix is to take `applySolidFill(_:)` out of `pixelCommands`.

## 7. Remove and Spot Heal ignore pressure, though FR-4.6 says retouch size follows it
- **Severity:** Low
- **Confidence:** High (in the code); needs a Force Touch trackpad or pen to see
- **Where:** `Sources/Colorbee/CanvasView.swift:588–590` and `:648` (no pressure passed), `Sources/Colorbee/Editor.swift:1742–1758` (`beginRetouchStroke`, `continueRetouchStroke` take none; the `RedactBrushArea` has one fixed diameter)
- **What happens:** FR-4.6: "A Force Touch trackpad or pen changes the size with pressure, as for the brushes", for the whole Retouch gallery. The local brushes, Smudge and the Clone Stamp do vary with pressure. Remove and Spot Heal always paint at the Size setting, however hard you press. No §23 entry carves them out.
- **How to trigger it:** Test file: `TestImages/Stage 13/Remove Sand.png`. You need a Force Touch trackpad.
  1. Open it, press J, and pick Remove in the Retouch gallery.
  2. Paint a stroke, pressing lightly, then firmly. **Bug:** the see-through red is the same width all the way. Do the same with Lighten: its width changes.
- **Why:** The drag cases for `.retouch` pass no `pressure(event)`, and the painted area is a `RedactBrushArea(diameter: retouchSize…)`.
- **Test that would catch it:** Once Leah decides what's wanted (pressure for Remove, or a §23 note that it's fixed width): an app test that strokes with pressure 0.3 and 1 and compares the painted area's width.

## 8. The generated Menus help page leaves out File ▸ Open Recent
- **Severity:** Low (help accuracy)
- **Confidence:** High
- **Where:** `Sources/Colorbee/MainMenu.swift:186`, `Sources/Colorbee/AppDelegate.swift:14–17`, `Help/Colorbee.help/Contents/Resources/en.lproj/menus.html`
- **What happens:** Open Recent is no longer built by Colorbee: macOS adds it once the app has launched. The menu dump runs before that and quits, so neither `menus.html` nor any other help page mentions Open Recent, though FR-14.5 lists it and every user sees it in the File menu. (The Window menu's macOS-added items are missing in the same way, which matters less.)
- **How to trigger it:** Open Help ▸ Colorbee Help ▸ Menus ▸ File. **Bug:** no Open Recent row between Open… and Close. Searching the help for "recent" finds nothing.
- **Why:** `HelpDump.write` walks only the menu `MainMenu.make()` built. Its `filledByMacOS` list adds rows for Services, Export As and Import from iPhone or iPad, but Open Recent isn't in the built menu at all.
- **Test that would catch it:** A check in `help-pages.py` (or an app test on `HelpDump`'s output) that File lists Open…, Open Recent and Close. Or add a fixed "Open Recent" row in the generator, as it does for Services.

## 9. The help screenshot script moves any new PNG from the Desktop into the help book
- **Severity:** Low (a personal picture could end up in the repo and the beta)
- **Confidence:** Medium
- **Where:** `Scripts/help-shots.sh:64–66`
- **What happens:** For each scene, the script takes the first PNG in the screenshots folder (the Desktop unless changed) that's newer than when the scene started, and *moves* it into `Help/…/images`, which is committed and shipped in the app. It doesn't check that the PNG is a screenshot, or that it was taken of Colorbee. On Leah's Mac, screenshots go to the clipboard, so a file only lands on the Desktop by something else: a browser or another app saving a PNG there, or a ⇧⌘4 taken out of habit of something personal. That file is then taken off the Desktop and filed as, say, `layers.png`, then committed with the help book.
- **How to trigger it:** By reading the script. To see it, run `make help-shots SCENES="1"`. While it waits, save any PNG to the Desktop, then press Return. **Bug:** that PNG is moved into `Help/Colorbee.help/Contents/Resources/en.lproj/images/window.png`. (Please use a throwaway PNG, such as a copy of `TestImages/Help/Sample Screenshot.png`.)
- **Why:** `find "$shots" -maxdepth 1 -name '*.png' -newer "$marker" | head -1` then `mv`.
- **Test that would catch it:** None needed. Limit the match to macOS screenshot names (`Screenshot *.png`), copy rather than move, and print the file's name so Leah can see what was taken.

## 10. Opening a Colorbee file while `make test` runs sends it to the hidden test copy
- **Severity:** Low
- **Confidence:** Low (depends on how Launch Services picks among running copies with the same bundle ID)
- **Where:** `Sources/Colorbee/TestHost.swift` (no handling for open requests), `project.yml` (the test host is Colorbee itself, `com.leah.Colorbee`), `Tests/ColorbeeTests/TestHostTests.swift:14`
- **What happens:** The app tests run inside a Debug Colorbee with the same bundle ID as the everyday one. macOS usually hands a double-clicked document to a copy of the app that's already running. If Leah double-clicks a `.colorproj` (Colorbee owns that type) while the tests run, it probably goes to the hidden test copy. That copy can't show windows or come to the front, so nothing seems to happen, and the document closes when the tests end. The test `startsHiddenWithNoWindows` also expects `NSDocumentController.shared.documents.isEmpty`, so it can fail for a reason that has nothing to do with the code.
- **How to trigger it:** Test file: `TestImages/Stage 6b Practice.colorproj`. Quit Colorbee first.
  1. In Terminal, run `make test`.
  2. As soon as "core" tests finish and the app tests start, double-click `Stage 6b Practice.colorproj` in Finder.
  3. **Bug, if it happens:** no window appears. Colorbee doesn't open it until you double-click again after the tests finish. The test run may report `startsHiddenWithNoWindows` failing.
- **Why:** `TestHost` doesn't implement `application(_:open:)`, so AppKit's default opens the file through `NSDocumentController` in a process whose activation policy is `.prohibited`.
- **Test that would catch it:** Hard to automate. Have `TestHost` implement `application(_:open:)` and refuse (`NSApp.reply(toOpenOrPrint: .failure)`), so the file isn't silently swallowed. Or note it in CLAUDE.md as "don't open Colorbee files during `make test`".

## 11. Two Straighten tests can pass without testing the race their names describe
- **Severity:** Low (test quality)
- **Confidence:** Medium
- **Where:** `Tests/ColorbeeTests/StraightenPreviewTests.swift:64–73` (`cancelWhileTurningLeavesTheImageAsItWas`), `:50–62` (`applyWhileStillTurningKeepsTheNewestAngle`)
- **What happens:**
  - `cancelWhileTurning…` sleeps 1 ms after moving the slider, then cancels. The test image is 80 × 50, so the background turn often finishes and is swapped in during that sleep. Then the test checks "Cancel after the preview showed", not "Cancel while turning". It passes either way, so a broken "turn still running" path would go unnoticed.
  - `applyWhileStillTurning…` checks that a late result doesn't change anything by waiting a fixed 200 ms. If the stale turn lands later than that, the check passes without having seen it.
- **How to trigger it:** Not by hand. Comment out the `stopStraightenPreview()` call in `cancelEffect`. The cancel test will usually still pass.
- **Why:** Both tests depend on timing rather than on knowing a turn is still running.
- **Test that would catch it:** Make the turn controllable in tests. For example, a test-only hook on `StraightenPlan` that waits on a semaphore before returning, so the test can cancel or apply while it's definitely running, release it, and then wait until `straightenRunning` is false before checking.

## 12. Cheap Editor tests that are missing
- **Severity:** Low (test coverage)
- **Confidence:** High
- **Where:** `Tests/ColorbeeTests/*`
- **What happens:** Several stage 13 behaviors that matter, and that would have caught findings 1, 3 and 4, have no app test, though each is a few lines with the existing helpers:
  - **Redact Brush, after-redaction offers (FR-9.6):** that a stroke sets `redactedSinceSave` and fills `clipboardCleanup` like Batch Redact. A locked layer with pixels under the stroke should refuse with `redactionMessage` naming it, and a locked layer *without* pixels there shouldn't block it. Today only the pixels and the one undo step are tested.
  - **Feather:** Edit ▸ Feather… (`beginFeather`, `setFeatherRadius`, `applyFeather`, `cancelFeather`) adds no undo step and Cancel leaves the selection as it was. The palette bar's Feather value (`selectionFeather`) softens a new selection's edge. Plus finding 1's case.
  - **Sidebar (§23, 2026-10-10):** `togglePanel` closes the sidebar with its last panel, `toggleSidebar`/`openSidebar` show Layers when none is chosen, and `settlePanels`. Plus findings 3 and 4.
  - **Esc during a fill:** `cancelFill()` while Remove runs leaves no step and no change, even when the fill finishes afterwards.
  - **Clone Stamp with Aligned off:** each stroke starts again from the source.
- **How to trigger it:** Not applicable.
- **Why:** The suites cover strokes, badges, pending objects, selections and Straighten well, but the newer state machines (Feather, the sidebar, the redaction offers) are untested.
- **Test that would catch it:** The tests listed above, in `RedactAndRetouchTests` and a new `PanelTests`/`FeatherTests`.

## 13. Typing a Feather radius and pressing Return may apply the old radius
- **Severity:** Low
- **Confidence:** Low (depends on when SwiftUI commits a number field. A quick look settles it)
- **Where:** `Sources/Colorbee/DocumentView.swift` (`FeatherSheet`: `TextField("Radius", value:…, format: .number)` next to `Button("OK").keyboardShortcut(.defaultAction)`)
- **What happens:** A SwiftUI number field passes its value on only when editing ends. Return is also the OK button's shortcut, and a window's default button usually takes Return before the field sees it. If so, typing "60" and pressing Return applies whatever radius the slider last showed (10 by default), not 60.
- **How to trigger it:** Test file: `TestImages/Stage 9 Practice Photo.png`.
  1. Open the photo and draw a selection box in the middle.
  2. Edit ▸ Feather…. Click in the number box, select the 10, type 60. Watch the red tint: if it doesn't change as you type, go on.
  3. Press Return (don't click elsewhere first).
  4. Press Delete. **Bug, if it happens:** the hole's edge fades over only about 10 px, not 60.
- **Why:** `FeatherSheet` updates `setFeatherRadius` from the field's binding, which a `value:`/`format:` field sets on commit. `applyFeather` uses whatever `marqueePreview` holds at that moment.
- **Test that would catch it:** By hand only. If it reproduces, add `.onSubmit { editor.applyFeather() }` to the field, or apply from the field's current text.
