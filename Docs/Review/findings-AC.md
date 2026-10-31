# Review AC: the rest of the app (everything in `Sources/Colorbee/` but `Editor.swift`)
Reviewed at commit: 08094b72da6bb45f122b342dd285728849008e7b
Checked:
- Stores: `SettingsFolder`, `PhotoSettingsStore`, `FilterStore`, `CustomColors`, `ClipboardHistory`, `TextStyles` (`TextStyleStore`), `Palettes` (`PaletteStore`), `ShortcutStore`, `Settings` (`ExportPresetStore`), `AppearanceSetting`, `ImageDocument.ExportOptions`
- `Renderer.swift` (all of `encode`, blur targets, texture caches) and `Shaders.metal`, each against its twin in the core (`BlendMode`, `Compositing`, `AdjustmentCompositing`, `Effects`, `Effects+Photo`, `PhotoAdjustments`, `PhotoEffects`, `ColorLookup`, `Canvas.composite`)
- `CanvasView` (scene building, drags, keys, drops), `DocumentWindow` (commands, menu validation, copy and paste), `ImageDocument`, `SaveSnapshot`, `AppDelegate`, `MainMenu`, `LayerMenu`
- Panels and sheets: `AdjustPhotoPanel` and the `PhotoControls+…` files, `AdjustmentsPanel`, `DocumentView` (`EffectBar`, `ToolOptions`), `LayersPanel`, `HistoryPanels`, `PageSidebar`, `DevelopWindow`, `Galleries`, `Settings`
- Dead code: a script listing every function and property in these files used only once; a search for Import from iPhone leftovers (none found)

## Copies that already differ

1. **Stores that read a list: only `FilterStore` survives an entry it can't read.** `FilterStore.swift:50` decodes each
   filter on its own (`Readable`), so one unreadable filter is skipped and the rest kept. `TextStyles.swift:29`,
   `Palettes.swift:49` and `Settings.swift:65` decode the whole list with one `try?`: one entry they can't read and the
   whole list comes back empty, and the next change saves the empty list over it. These three live in
   `UserDefaults`, which every build shares (one bundle ID, `project.yml:128`); `SettingsFolder` keeps a test build
   from overwriting the everyday copy's *filters* (Leah, 2026-10-27), but not its text styles, palettes or export
   presets. Today none of those types has changed shape, so nothing is lost yet. Leah decides whether the
   everyday-copy protection should cover them (finding 1 would make it one line either way).
2. **Which stores stay out of the way of tests.** `FilterStore` and `PhotoSettingsStore` write nothing while testing
   (`SettingsFolder.current` is nil under `TestHost`). `CustomColors`, `TextStyleStore`, `PaletteStore`,
   `ExportPresetStore`, `ShortcutStore` and `ClipboardHistory` (`ClipboardHistory.swift:31`, its own path) write to the
   real settings from a test; only the CLAUDE.md rule "never save preferences from a test" keeps them safe. No test
   breaks the rule today.
3. **A picture opened as its own document keeps its camera details only through File ▸ Open.**
   `ImageDocument.swift:163` sets `cameraDetails` and `locationRemoved` on the new canvas. Paste into New Image
   (`DocumentWindow.swift:389`) and an image (not a file) dropped beside the canvas (`CanvasView.swift:1136`) build the
   same one-layer canvas from the same `ImageCodec.decode` but leave both out, so Export's "Include camera details"
   has nothing to include for them. May well be intended (a clipboard image rarely carries them); Leah decides.
4. **The effect bar and the Adjustments panel format the same setting two ways.** `DocumentView.swift:482`
   (`EffectBar.formatted`) and `AdjustmentsPanel.swift:262` both turn an `EffectKind.Parameter` value into text. For a
   step under 1 the bar shows one decimal (steps 0.1 to 0.99) and the panel always two; the bar adds "+" from the
   unrounded value, the panel from the rounded one. Every parameter in use today (steps 1 and 0.01, and Straighten's
   0.1, which is never an adjustment layer) shows the same in both, so nothing differs on screen yet.

## 1. One way for the stores to load and save
- **Worth:** High
- **Kind:** Copies
- **Size:** Medium
- **Risk:** Saved settings that no longer load are the failure. `FilterStoreTests`, `PhotoSettingsTests` and
  `CustomColorsTests` cover two of the eight; a new core-free test of the helper itself (round trip, one damaged entry
  kept out, nothing written while testing) would be needed first. Keep every key and file name exactly as it is.
- **Where:** `PhotoSettingsStore.swift:22-36`, `FilterStore.swift:30-47, 110-119`, `TextStyles.swift:28-59`,
  `Palettes.swift:48-54, 121-125`, `Settings.swift:64-83`, `CustomColors.swift:17-21, 79-81`,
  `ClipboardHistory.swift:30-36, 123-125`, `ShortcutStore.swift:76-78, 126-129`.
- **What:** eight singletons each hand-write the same load and save: read `Data` from `UserDefaults` or a file,
  `try? JSONDecoder().decode`, and on change `try? JSONEncoder().encode` and write it back. They differ in where they
  keep it, whether a damaged entry loses the whole list, whether tests are kept out, whether the write is in the
  background (`FilterStore` only), and whether output is pretty-printed. All errors are dropped silently. See "Copies
  that already differ" 1 and 2.
- **Suggested change:** a small `StoredList<Element: Codable>` (or `Stored<Value>`) that owns one key or file name,
  decodes element by element as `FilterStore.Readable` does, writes nothing under `TestHost`, and optionally writes in
  the background. Each store keeps its own rules (numbering names, the 28-swatch check) and calls it for loading and
  saving. `ShortcutStore` and `ClipboardHistory` can keep their own formats and just use its location and test guard.

## 2. `Renderer.encode`: one helper for "start a pass on this texture", one for "blend an isolated picture back"
- **Worth:** High
- **Kind:** Copies · Hard to change
- **Size:** Medium
- **Risk:** a pass that forgets the scissor or the sampler draws outside the canvas or with the wrong sampling.
  `ScreenMatchesExportTests` (the screen against the export, through `Renderer.renderedPixels`) catches most of it;
  check it covers a Pass Through group below 100%, a masked layer, a clipped adjustment and Adjust Photo with Sharpness
  before starting, and add those cases if not.
- **Where:** `Renderer.swift:423-435` (`resume(_:clearing:)`, the helper), and the hand-built copies of it at
  `:357-364` (Adjust Photo's blurs), `:403-414` (Blur and Sharpen), `:449-456` (Pass Through backdrop copy) and
  `:516-526` (a layer drawn on its own, which is `resume(isolatedTexture, clearing: true)` plus `opacity = 1`).
  The blend-back copies: `:466-476` (a group) and `:584-593` (an isolated layer).
- **What:** `resume` was added for groups (stage 25), but the four older copies of the same five steps (end the
  encoder, new pass descriptor with load or clear, new encoder, `setScissorRect(canvasScissor)`, `sampling(zoom < 1)`)
  were never moved onto it. The Blur and Sharpen copy already sets its sampler after drawing rather than before (harmless
  today: `adjust_blur_fragment` reads with `read()`, not a sampler). The two blend-backs both do `resume(target)`, reset
  `rect` and `keyEnabled`, set `blendMode` and `opacity` from the layer, bind the picture, `masking(layer.activeMask)`,
  draw `blendIsolatedPipeline`, `masking(nil)`. More generally, `uniforms` is one struct that every step changes and
  resets by hand (`keyEnabled = 0` is written nine times, `blendMode = -1` then `0` twice, `maskParams.y` set and
  cleared), so a new step that forgets a reset leaks a setting into the next draw.
- **Suggested change:** replace the four copies with `resume(...)`; add `blendBack(_ picture: MTLTexture, as layer:
  Layer, onto target:)` for the two blend-backs; and give `draw` a fresh-per-draw shape (a `drawLayer(texture:rect:
  mode:opacity:)` that starts from a base `uniforms` value each time) so resets stop being something to remember. This
  also makes a later split of `encode` (330 lines of nested functions) into a small `FrameEncoder` type possible.

## 3. Each menu command's rules live in five or six places
- **Worth:** High
- **Kind:** Hard to change · Copies
- **Size:** Large
- **Risk:** a command left enabled while an effect is open, or greyed out when it shouldn't be. `MenuCheckmarkTests`,
  `KeyForwardingTests`, `LayerMenuTests` and `EditorCommandTests` cover parts. A new test that walks every item of
  `MainMenu.make()` and checks that some responder (`DocumentWindow`, `ImageDocument`, `AppDelegate`) implements its
  action, and that it has a tooltip, should come first; none exists today.
- **Where:** `MainMenu.swift:193-203` (items made from action *strings*: `Selector(action)`), `MainMenu.swift:40-185`
  (tooltips keyed by the same strings), `DocumentWindow.swift:87-398` (the actions), `:405-590` (`validateMenuItem`),
  `:594-611` (`isOn`), `:613-630` (`viewingCommands`, `pixelCommands`), `LayerMenu.swift:12-43` (the same layer
  commands' titles and enabling, written again), `ShortcutStore.swift:38` (`taggedActions`).
- **What:** adding or renaming a command means touching every one of those lists, and nothing checks them against
  each other: a typo in a `MainMenu` string or a renamed `@objc func` makes the item silently grey (no responder), and
  the tooltip silently goes missing. `validateMenuItem` is 185 lines, with about 20 separate cases that only `return
  true`. "Delete Layers"/"Delete Layer", "Duplicate Layers", "Hide Layers"/"Show Layer" and "Lock Layers" are worked out
  in both `validateMenuItem` (`:534-584`) and `LayerMenu` (`:26-34`); they agree today.
- **Suggested change:** in steps. (a) `#selector(DocumentWindow.newLayer(_:))` instead of strings in `MainMenu`, so
  the compiler checks them (small, safe; key the tooltips by `Selector` too). (b) Fold the `return true` cases into one
  list. (c) Move the per-command titles both menus share into the Editor (`layerCommandTitles`), so `LayerMenu` and
  `validateMenuItem` read one place. (d) Optionally, one `[Selector: CommandRule]` table (viewing or pixel command,
  enabled-when, title-when, checkmark-when) that `validateMenuItem` and `isOn` read.

## 4. The shader's twins: fix two stale pointers, add the missing ones, and name the adjustment kinds
- **Worth:** Medium
- **Kind:** Copies
- **Size:** Small
- **Risk:** comments and named constants only; no picture changes. `ScreenMatchesExportTests` stays the guard.
- **Where:** the rules both sides must follow, and how each is marked today:

  | Rule | Core | Shader | Pointers |
  |---|---|---|---|
  | Blend modes | `BlendMode.swift:4` | `Shaders.metal:165-225` | both ways ✓ |
  | Mask reveal | `BlendMode.swift:152` | `:27`, and again inline at `:285` | both ways ✓ (see 6) |
  | "Only the layer below" | `BlendMode.swift:161` | `:246-251` | core says "`blendMode` −2"; the shader uses `maskParams.y`, and −1 means a locked-transparency patch (`:238`). **Stale** |
  | Adjustment fade-in | `AdjustmentCompositing.swift:5` | `:347` | both ways ✓ |
  | Invert, Desaturate, Brightness/Contrast | `Effects.swift:101-122` (`pointwise`) | `:336-344` | shader → core only |
  | Hue/Saturation (HSL) | `Effects.swift:390-440` (`HSL`) | `:308-334` | none either way |
  | Adjust Photo detail | `PhotoAdjustments.swift:87`, `Effects+Photo.swift:6` | `:465` | core names `photo_fragment`; it is `adjust_photo_fragment`. **Stale** |
  | Vignette, grain | `PhotoEffects.swift:80, 110` | `:400-456` | both ways ✓ |
  | Groups, clipping, what's drawn on its own | `Canvas.swift:392-431` (`composite`, `clipped`) | `Renderer.swift:439-596` | Renderer → core only |
  | `QuadUniforms` layout | `Renderer.swift:7` | `Shaders.metal:5` | shader → Swift only |

  And the adjustment kind codes: `Renderer.swift:757-767` hands out 1 to 6, `:397` tests `kind >= 5`, `:400` `kind
  == 5`; `Shaders.metal:17` lists them in a comment and `:556` tests `== 5`.
- **What:** two pointers name things that no longer exist, five rules are marked on one side only, and the kind codes
  are bare numbers in four places.
- **Suggested change:** correct the two stale comments; add "`Shaders.metal` `<function>` does the same" on the core
  side of each one-way rule and on Swift's `QuadUniforms`; make the kinds a Swift `enum ShaderAdjustment: Int` used in
  `adjustmentUniforms` and the `>= 5` test, with matching named `constant int` values in the shader beside a "must
  match" comment.

## 5. The canvas keys are listed twice
- **Worth:** Medium
- **Kind:** Copies
- **Size:** Small
- **Risk:** a key that stops doing anything. `KeyForwardingTests` covers keys; add one that every
  `ShortcutStore.canvasCommands` id has an action (fails today only if they drift).
- **Where:** `ShortcutStore.swift:19-30` (ids, titles, default keys) and `CanvasView.swift:1008-1022` (`canvasActions`,
  the same ids again, with what each does).
- **What:** a new tool key needs an entry in both, spelled the same; one missed and the key silently does nothing, or
  shows in Settings but can't be pressed.
- **Suggested change:** one table, `[(id, title, key, action: @MainActor (Editor) -> Void)]`, kept by `ShortcutStore`
  (or a small `CanvasKeys` enum); `canvasCommands` and the key handler both read it.

## 6. The shader repeats three of its own steps
- **Worth:** Medium
- **Kind:** Copies
- **Size:** Small
- **Risk:** `ScreenMatchesExportTests`; the mask-alone view is checked by `LayerMaskAppTests` only through the Editor,
  so look at it by hand (Option-click a mask) after.
- **Where:** the mask reveal formula in `mask_reveal` (`Shaders.metal:32`) and again in `mask_alone_fragment`
  (`:285`); the coverage divide in `unblurred` (`:458-463`) and again in `adjust_blur_fragment` (`:553-555`); the
  Transparent Selection key test in `layer_fragment` (`:90`) and `blend_layer_fragment` (`:239`).
- **What:** a change to how a mask reveals (it has a core twin too, `Compositing.reveal`) has to be made in two shader
  places, or the mask shown alone stops matching what the mask does.
- **Suggested change:** a `static float reveal(float4 m)` used by both mask functions, a `static float4
  uncovered(blurred, coverage, pixel)` used by both blur readers, and a `static bool isKeyColor(color, u)`.

## 7. Settings read and written by key strings in several places
- **Worth:** Medium
- **Kind:** Copies
- **Size:** Small
- **Risk:** a renamed key forgets Leah's saved choice. No test covers these; a quick by-hand check that PDF resolution,
  the export options and Smoothing survive a relaunch would do.
- **Where:** `"PDFResolution"` at `Settings.swift:134` and `ImageDocument.swift:177`, with its allowed values
  `[150, 200, 300]` (`ImageDocument.swift:178`) repeated as the picker's tags (`Settings.swift:150-152`);
  `ExportOptions` (`ImageDocument.swift:526-570`), eight properties each written as a get-and-`didSet` pair, mixing
  `Self.defaults` and `UserDefaults.standard` (`:548-549`); `Editor.smoothingKey` and `editableTextKey` written from
  `DocumentView.swift:159, 263` but read in `Editor.swift:592-597`.
- **What:** the same setting's name and rules are spelled in two files, so changing one (say, adding 600 DPI) needs
  the other remembered.
- **Suggested change:** one `enum PreferenceKey` with every key, and the PDF resolutions as one `static let` the
  picker and the reader share. For `ExportOptions`, a tiny `@Preference("ExportQuality", default: 0.9)` property
  wrapper or `@AppStorage`-style helper so each setting is one line.

## 8. "Flatten the snapshot" and "the pages in order" written several times
- **Worth:** Medium
- **Kind:** Copies
- **Size:** Small
- **Risk:** what's saved and what Colorbee thinks it saved could drift apart (the unsaved-redaction check compares
  with `lastSavedImage`). `ScreenMatchesExportTests`, `ExportColorAppTests` and the page tests in
  `CanvasToolAndPageTests` cover it.
- **Where:** `canvas.flattened(transparentKey:resampling:)` with the snapshot's own settings at `SaveSnapshot.swift:29,
  85, 94`, `DocumentWindow.swift:118`, `Editor.swift:618, 5498`; the page order (sort the parked pages, insert the shown
  one at `currentIndex`) at `SaveSnapshot.swift:49-51` and `:58-59`.
- **What:** the rule "a saved image is the canvas flattened with this key and this resampling" is spelled out six
  times; adding anything to it (a matte, say) means finding them all. Same for page order, twice.
- **Suggested change:** `SaveSnapshot.flattened: PixelBuffer` and `SaveSnapshot.pagesInOrder<T>(shown:)`, used by all of
  them.

## 9. A one-layer document from a decoded picture, built five times
- **Worth:** Medium
- **Kind:** Copies
- **Size:** Small
- **Risk:** opening a file or a paste that loses a setting. `DamagedFileAppTests`, `PasteInPlaceTests` and the open
  paths in `ExportColorAppTests` cover parts.
- **Where:** `ImageDocument.swift:156, 164-171`, `DocumentWindow.swift:389`, `CanvasView.swift:1136`,
  `RawDeveloper.swift:141`; the core does it twice more, `PDFPages.swift:56, 72`.
- **What:** `Canvas(colorSpace:layers: [Layer(name: "Background", buffer:)], hasTransparentBackground:
  buffer.hasTransparency)`, each time by hand; only one copy also carries the camera details ("Copies that already
  differ" 3).
- **Suggested change:** a core `Canvas(decoded: DecodedImage)` that makes the Background layer and carries everything
  a decode reports; whether Paste into New Image keeps camera details is then a one-line choice for Leah.

## 10. Slider rows and eyedropper buttons repeated across panels
- **Worth:** Low
- **Kind:** Copies
- **Size:** Medium
- **Risk:** looks only; check the panels by eye after. `SlideAreaTests` and `PanelTests` cover the scrubbing.
- **Where:** the row (name, value chip, scrub area, small slider): `AdjustPhotoPanel.swift:301-361` (`row`) and
  `AdjustmentsPanel.swift:239-260` (`slider`); value text: `DocumentView.swift:482` and `AdjustmentsPanel.swift:262`
  ("Copies that already differ" 4). The picture-pick toggle button: `AdjustPhotoPanel.swift:150` (`handButton`),
  `:279` (`whiteBalanceDropper`), `PhotoControls+PointColor.swift:88` (`pointColorDropper`). The "set of titles kept as
  lines in `@AppStorage`" toggle: `AdjustPhotoPanel.swift:172` and `:242`.
- **What:** the two rows already differ in small ways (the panel's has Control-click Reset and no accessibility value;
  the Adjustments one the opposite), so a fix to one, such as a VoiceOver value, doesn't reach the other.
- **Suggested change:** one `SettingRow` view (title, value, range, step, unit, onEnd, optional reset) used by both
  panels, one `EffectKind.Parameter.text(for:)` for the value, one `PickToggleButton(symbol:isOn:help:)` for the three
  droppers, and one `LineSet` helper for the folded and open sets. The Develop window's sliders are a different style on
  purpose and can stay.

## 11. Thumbnails made from a `Thumbnail` twice, and the thumbnail sampling written twice
- **Worth:** Low
- **Kind:** Copies · Already there
- **Size:** Small
- **Risk:** small images only; look at the History, Pages and Layers panels after.
- **Where:** `HistoryPanels.swift:103-108` and `PageSidebar.swift:145-151` (identical: `Thumbnail` → `PixelBuffer` →
  `ImageCodec.makeCGImage` → `NSImage`); `LayersPanel.swift:515-540` (`LayerThumbnail`) repeats the size and
  centre-sampling math of `Canvas.thumbnail(maxSide:)` (`Canvas.swift:246-265`).
- **What:** two copies of one conversion, and one sampling rule written in the app and the core.
- **Suggested change:** `extension Thumbnail { func nsImage(in: CGColorSpace) -> NSImage? }` in the app, and a core
  `PixelBuffer.sampledThumbnail(maxSide:)` that both `LayerThumbnail` and `Canvas.thumbnail` size from. (Not
  `resampled(.nearestNeighbor)`: it samples pixel corners, not centres, so the pictures would change.)

## 12. Small repeated helpers in the stores
- **Worth:** Low
- **Kind:** Copies
- **Size:** Small
- **Risk:** `CustomColorsTests`, `FilterStoreTests`; the packed format must stay byte for byte.
- **Where:** RGBA packing: `CustomColors.swift:35-39, 62` (as `Int`) and `TextStyles.swift:15-16` (as `UInt32`).
  "Number the name if taken": `FilterStore.swift:65-70`, `Palettes.swift:71-77, 112-116`. Two copies of "the clipboard
  unchanged since": `ClipboardHistory.swift:75` and inline at `:85`.
- **What:** the same few lines, written two or three times.
- **Suggested change:** `Pixel.packedRGBA` / `Pixel(packedRGBA:)` (app extension, beside `Pixel+AppKit`), a
  `uniqueName(_:among:)` function, and `remove` calling `clipboardUnchanged`.

## 13. Several one-off `@unchecked Sendable` boxes where one generic exists
- **Worth:** Low
- **Kind:** Already there
- **Size:** Small
- **Risk:** none at run time; the compiler checks the change.
- **Where:** `DocumentWindow.swift:638` (`UnsafePixels`), `DevelopWindow.swift:132, 137` (`UncheckedImage`,
  `UncheckedCanvas`), `ClipboardImage.swift:72` (`UnsafeColorSpace`), against the generic `UnsafeTransfer<Value>`
  already in `Editor.swift:5610` (private there).
- **What:** four box types that each do what the generic one does.
- **Suggested change:** move `UnsafeTransfer` to its own file (beside `CancelFlag.swift`), make it internal, and use it
  for all four, so there's one place that says why handing these across threads is safe.

## 14. Leftovers
- **Worth:** Low
- **Kind:** Dead code
- **Size:** Small
- **Risk:** none; the build catches a removal that's still used.
- **Where and what:**
  - `DocumentView.swift:593` `wholeNumber(_:)`: never called.
  - `Theme.swift:17` `tertiaryInk`: never used.
  - `DocumentWindow.swift:632` `imageDataOnPasteboard()`: only calls `PasteboardImages.imageData()`.
  - `ClipboardHistory.swift:72-74`: the doc comment for `remove(_:clearingClipboard:)` sits on `clipboardUnchanged`.
  - `DocumentWindow.swift:592`: "Commands that only change the view." sits on `isOn`; it belongs to
    `viewingCommands`.
  - The export preset tooltip is written twice, `MainMenu.swift:59` and `:515`.
  - `ClipboardHistory.swift:31` and `ImageDocument.swift:420` build `Application Support/Colorbee/…` by hand rather
    than from `SettingsFolder.everyday`, which says it owns that folder.
- **Suggested change:** delete or move each; point the two folders at `SettingsFolder.everyday`.
