# Review E: stale results, and Auto-Redact first
Reviewed at commit: 918ce67adbeae9458a9a91f5bbdd5c54a65da984
Checked:
- `Editor.swift` Auto-Redact: `beginAutoRedact`, the scan `Task`, `refreshAutoRedactMatches`, `setRedactionMatch`, `applyAutoRedact`, `cancelAutoRedact`, `AutoRedactSession`
- `AutoRedactSheet.swift`: what the review shows (list, counts, treatment) against what Apply does
- `AutoRedact.swift`: `TextScan.read` (Vision settings), `matches`, `rect(for:in:)` (padding, word-space trimming, outward rounding through `IntRect(enclosingMinX:…)`), `wordSpace`, `grayscale`, `AutoRedact.mask`, the Luhn check and look-alike folding
- `CanvasView.swift`: the redaction highlights, the drag paths, the `frameFinished` tasks and timers
- `DocumentWindow.swift`: `validateMenuItem`, and which commands can run while the Auto-Redact sheet is up
- Every `Task`, `Task.detached` and `DispatchQueue` in `Editor.swift`: `renderSoon`, the gradient render, the textured shape render (`RenderedShape`; generation and spec checks hold, and placing always re-renders if the cache doesn't match), the subject search (round-1 fix holds: checks `history.revision`), the effect previews (generation checks hold)
- `ImageDocument.swift` (save completion → `markSaved`, background export), `ClipboardImage.swift` (round-1 fix holds), `ClipboardHistory.swift`, `HistoryPanels.swift`
- Main-thread whole-image work: every `flattened(`, `composited(through:` and `flattenedPNG` call in the app target
- Core `TextRenderer.swift`, `Shapes.swift`, `PaintStyle.swift`: only as far as the background shape render reads them (pure functions of the spec; nothing shared is written)

Not re-reported: round-1 findings in `RESULTS.md`, including the deferred Levels-histogram pause (D2).

**Hand-tested by Leah on 2026-10-04**, with four test images made for this review: a fake account-settings screenshot (1440 × 900), ten small emails plus one large one, a 1200 × 10,000 scrolling capture and dark text on a transparent background. Findings 1–5 are confirmed. Finding 7 is new from that testing, so it comes after finding 6 even though it's more severe. Finding 6 wasn't hand-tested.

## 1. Auto-Redact reads every visible layer but redacts only the active layer, so text on another layer stays readable
- **Severity:** Critical (privacy: matched text is still readable after Apply, while the user believes it's redacted)
- **Confidence:** High. Confirmed by hand: the screenshot, then Layer ▸ New Layer, then Auto-Redact with Blur: the email stayed readable.
- **Where:** `Sources/Colorbee/Editor.swift:2583` (`let image = canvas.flattened()`) against `:2649` (`Effects.apply(effect, to: canvas.activeLayer, …)`)
- **What happens:** The scan finds text in the combined image, but Apply changes only the active layer.
  - If the text is on another layer, Blur and Pixelate change nothing visible.
  - Solid Fill covers the text only when the active layer is above the text's layer.
  - In the commonest layered case (a screenshot, plus a new layer for arrows or notes, which becomes active), Blur or Pixelate blurs empty transparent pixels. Nothing changes (no step is even recorded), the sheet closes, and the email or key is still there.
  - With Solid Fill and the active layer below the text's layer, the boxes are painted under the text.
  - Related: text on a hidden layer, or text hidden by an adjustment layer above it (a Gaussian Blur layer, say), isn't scanned. It stays readable in the saved `.colorproj` and as soon as the layer is shown or the adjustment removed.
- **How to trigger it:** Open a screenshot containing an email address. Layer ▸ New Layer (the new, empty layer becomes active). Effects ▸ Auto-Redact…: the email is found and boxed. Choose Blur, then Apply. The email is unchanged. Or make Background active with the screenshot on Layer 1 above it, choose Solid Fill and Apply: the email is still readable.
- **Why:** The match rectangles come from the flattened image, and the effect is applied to one layer. Nothing checks that the active layer is the one holding the text, or redacts the flattened result.
- **Test that would catch it:** Core-level, with the Editor logic moved behind a testable function. A canvas whose Background holds black text pixels in a known rect, and an empty Layer 1 active. Run the apply path with a match covering that rect and Blur, then expect `canvas.flattened()` inside the rect to differ from the original (or the text pixels to be gone). Fix options: redact every visible pixel layer under each box; or merge the result into a new top layer, as a Solid Fill covering box would do; or refuse with a message when the active layer isn't the only visible pixel layer.

## 2. The image can change between the scan and Apply, so the redaction lands where the text used to be
- **Severity:** Critical (privacy: the boxes no longer cover the text)
- **Confidence:** High. Confirmed by hand: with the review list open, Image ▸ Flip was clickable in the menu bar. Choosing it turned the picture over at once, and Apply then put the black boxes on empty space, leaving the text readable.
- **Where:** `Sources/Colorbee/DocumentWindow.swift:218` onward (`validateMenuItem` has no case for `editor.autoRedact != nil`); `Sources/Colorbee/Editor.swift:2590-2599` (the scan result is stored without checking which session or image it was for), `:2629-2652` (Apply uses the stored rects without checking `history.revision`, the canvas size or the active layer)
- **What happens:** The review sheet is window-modal. AppKit still sends menu commands and their shortcuts to the main window's responder chain (the document window behind the sheet; the sheet is only the key window). `validateMenuItem` disables commands only while `activeEffect != nil`, so while "Reading text…" or the list is showing, these all still work:
  - Image ▸ Flip and Rotate, Crop to Selection, Resize and Skew… and Canvas Properties…
  - Edit ▸ Undo (⌘Z when no text field in the sheet is being edited), Paste
  - Layer ▸ New Layer and Delete, which change the active layer
  Afterwards, Apply redacts the old rectangles on the changed image. Flip Horizontal mirrors the text to the other side, so the boxes cover other content and the secrets are left untouched. After ⌘Z of a crop, the coordinates are off by the crop's offset. After New Layer, Apply redacts the empty new layer (finding 1).
  - **Separately, a new run can receive an old scan:** start Auto-Redact, Cancel, flip, start it again. If the first scan finishes after the second run starts, its rects are stored in the new session (`guard … self.autoRedact != nil`), and Apply can use them before the second scan replaces them.
  - **Effects can open behind the sheet:** Effects ▸ Gaussian Blur… also stays enabled behind the sheet. If Apply in the sheet redacts while that effect's preview is open, the next slider tick redraws the preview from the copy taken when the effect opened (before the redaction). Cancelling the effect restores its original tiles. Either way the text comes back, while history still lists "Auto-Redact".
- **How to trigger it:** Open a screenshot with an email near the left edge. Effects ▸ Auto-Redact…, wait for the list, then choose Image ▸ Flip ▸ Horizontal from the menu bar while the sheet is open. Click Apply: the box is redacted at the old (now mirrored) position, and the email on the other side stays readable. To confirm the routing, check whether Image ▸ Flip is enabled in the menu bar while the sheet is showing.
- **Why:** Unlike the subject search after round 1, Auto-Redact never records or compares `history.revision` (or the canvas size and the active layer's ID), and the menus aren't greyed out during the review.
- **Test that would catch it:** Store `history.revision`, the canvas size and the active layer's ID (plus a session ID) in `AutoRedactSession` when the scan starts. In `applyAutoRedact` and when the scan result arrives, refuse (with a "the image changed, run Auto-Redact again" message) if any differ. Grey out document-changing commands in `validateMenuItem` while `editor.autoRedact != nil`. A core-level test of the guard: begin a session, commit a flip, and expect apply to change no pixels.

## 3. Blur and Pixelate use one strength for every match, so large text among small text stays readable
- **Severity:** High (text left readable after Apply)
- **Confidence:** High. Confirmed by hand: with ten small emails and one large one, the large one was still easy to read after Apply.
- **Where:** `Sources/Colorbee/Editor.swift:2640-2647`
- **What happens:** The strength is the median box height ÷ 3 across all checked matches, applied to all of them, although the comment says "Each match is treated on its own, scaled to its text size", and §23 (stage 4) says Blur and Pixelate are scaled "to the size of the text found". With several small items and one large one, the large one gets the small text's strength. For example, ten 14-px emails (boxes about 24 px tall) give σ = 8 and Pixelate cells of 8 px. A URL in a 72-px heading (box about 95 px) then needs about σ = 32, but gets 8: its 60-px letters remain easily readable through a σ = 8 blur, and are about 7 cells tall when pixelated.
- **How to trigger it:** A screenshot with several small email addresses and one large URL or key (a heading, a slide title, a zoomed-in screenshot pasted in). Auto-Redact, Blur (or Pixelate), Apply. The large item is still legible.
- **Why:**
  ```swift
  let heights = selected.map(\.rect.height).sorted()
  let textHeight = Double(heights[heights.count / 2])
  let strength = max(6, textHeight / 3)
  ```
  One `effect` is then applied to the combined mask.
- **Test that would catch it:** Apply per match, or per group of matches with similar heights, each with `max(6, rect.height / 3)`. A core test: two matches of heights 20 and 120 on a test image with high-contrast stripes. After Blur, the variance inside the 120-px box should be below a threshold that the median-strength version fails.

## 4. With a selection, a found item is redacted only inside the selection, though the canvas shows the whole box
- **Severity:** High (part of a secret stays readable while the box on the canvas and the list show it as covered)
- **Confidence:** High. Confirmed by hand: a lasso cutting through the email line; after Solid Fill the email's ends still showed around the filled shape.
- **Where:** `Sources/Colorbee/Editor.swift:2608-2612` (an item is kept if its box's center is inside the selection), `:2637-2639` (the redaction is then clipped to the selection); `Sources/Colorbee/CanvasView.swift:303-306` (the highlight draws the full `match.rect`)
- **What happens:** Two problems with selections:
  - **Clipped item:** An item whose center is inside the selection is listed with its full text and drawn as a full orange box, but Apply intersects the mask with the selection. Any part outside a rough marquee or lasso stays readable: the last characters of an email, or the first digits of a card number.
  - **Dropped item:** An item whose center falls just outside the selection is dropped altogether, even when most of it is inside. The sheet can then say "No sensitive text found in the selection."
- **How to trigger it:** Draw a lasso that covers most of a line with an email, cutting through its last few letters. Auto-Redact, Solid Fill, Apply. The letters outside the lasso are still visible, although the orange box covered them.
- **Why:** The center test and the intersect were each sensible alone, but together the user approves one area and a smaller one is changed.
- **Test that would catch it:** Don't clip a listed item to the selection (redact its whole box), or show the clipped box on the canvas and list the item as partial. Keep any item that overlaps the selection rather than requiring its center to be inside. A core test of the filter-and-mask step: a selection covering 80% of a match rect should give a mask covering 100% of it.

## 5. Auto-Redact can miss text on tall images or on transparent backgrounds and report "No sensitive text found"
- **Severity:** High (a missed item is never shown, so the user believes the image is clean)
- **Confidence:** High. Confirmed by hand: the 1200 × 10,000 image (ten 16-px emails) gave 3 items, and the transparent image (five items) gave none. Which Vision setting is responsible is still to be checked.
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/AutoRedact.swift:120-134` (`VNRecognizeTextRequest` with default `minimumTextHeight`); `Sources/Colorbee/Editor.swift:2583-2589` (a straight-alpha image is passed in)
- **What happens:** Two possible causes:
  - **Tall images:** Vision documents `minimumTextHeight` as relative to the image height, with a default of 1/32, and says text smaller than that may be ignored. A tall scrolling screenshot (say 1200 × 10,000 px) has a threshold of about 312 px, so ordinary 14–20 px text may not be read at all.
  - **Transparent backgrounds:** The image handed to Vision keeps its transparency. Where the background is transparent (a document with Transparent Background and dark text, or a window capture with transparent corners), Vision may see dark text on black and read nothing.
- **How to confirm:** Two test images: 1200 × 10,000 white with a 16-px email every 1,000 px; and 1200 × 800 transparent with black 16-px text. Run Auto-Redact on each (or `TextScan.read` in a test) and count the matches.
- **Why:** Neither `minimumTextHeight` nor the background is set. The `grayscale` helper draws over white, but Vision gets the original `CGImage`.
- **Test that would catch it:** A core test of `TextScan.read` on both images expecting every email to be found. Likely fixes: set `minimumTextHeight` low (or 0), split very tall images into overlapping tiles, and flatten over an opaque background (white, or the matte) before reading.

## 6. Several commands flatten or encode the whole image on the main thread
- **Severity:** Medium (NFR-6: the main thread blocks for much longer than a frame on large images)
- **Confidence:** High
- **Where:**
  - Auto-Redact start: `Sources/Colorbee/Editor.swift:2583-2589` (flatten, copy the area, then `makeCGImage` copies again)
  - Share, Set as Desktop Picture and Print: `Sources/Colorbee/ImageDocument.swift:166`, `:182`, `:193`, through `Editor.flattenedPNG()`, which flattens and PNG-encodes
  - Before/After "Last Saved": `Sources/Colorbee/Editor.swift:444-449`, flattened lazily the first time it's drawn, again after every explicit save (`markSaved` sets `lastSavedImage = nil`)
  - Adding an Auto Contrast adjustment layer: `Sources/Colorbee/Editor.swift:2103`
  - An Adjust Photo layer's Auto: `Sources/Colorbee/AdjustmentsPanel.swift:166`
- **What happens:** Each composites every layer (and for Share, Desktop Picture and Print also encodes a full-size PNG) synchronously on the main thread. At 8000 × 8000 with a few layers, the composite alone is hundreds of milliseconds, and a 64-megapixel PNG encode takes seconds, so the window freezes. Saving and Copy were moved to the background in stage 8; these weren't.
- **How to trigger it:** An 8000 × 8000 image with 3–4 layers. File ▸ Share…, or Set as Desktop Picture, or Print…, or Effects ▸ Auto-Redact…: a long beachball before anything appears. Or ⌘S, then View ▸ Before/After with Last Saved: a pause each time after a save.
- **Why:** These call `canvas.flattened()` / `composited(through:)` / `flattenedPNG()` directly, instead of taking a `SaveSnapshot` (`canvas.copy()`, about 40 ms) and doing the rest in a `Task.detached`, as Copy and Export do.
- **Test that would catch it:** `make bench`-style timing of each command's longest main-thread pause at 8000 × 8000. Or a code check that no `flattened(` or `composited(through:` call in the app target runs on the main actor outside a snapshot-taking path.

## 7. An API key in the usual `sk_test_…` form wasn't found at all
- **Severity:** High (privacy: the key is never listed, so it's never redacted and nothing warns the user)
- **Confidence:** High that it's missed (confirmed by hand); Low on the cause
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/AutoRedact.swift:48-63` (the API key pattern), `:120-134` (`TextScan.read`)
- **What happens:** In the test screenshot, the line `API key:  sk_test_FAKE0000EXAMPLE1234abcd` (17-px DejaVu Sans Mono, black on white) wasn't in the review list. Every other item on that screenshot was found and redacted: two emails in sentences, the phone, the card, the IP address and the URL. So the key stays readable after Apply, and the user has no reason to look for it.
- **How to trigger it:** Open the test screenshot (or any image with a Stripe-style key such as `sk_test_` followed by 23 letters and digits) and run Effects ▸ Auto-Redact…. The key isn't listed.
- **Why (unconfirmed):** The likeliest cause is that Vision doesn't return the underscores exactly. It may read them as spaces or drop them, which is common for monospaced text with underscores close to the baseline. Then neither part of the pattern can match:
  - The Stripe alternative needs literal underscores: `\b[spr]k_(?:live|test)_[A-Z0-9]{8,}`.
  - The fallback for long tokens needs a single run of at least 32 letters, digits, `_` or `-`. This key is 31 characters even with its underscores, and shorter pieces once spaces split it.

  Real Stripe test and live keys have the same shape, so this isn't specific to the test image. Other causes to rule out: Vision splitting the line differently, or the look-alike folding.
- **How to confirm the cause:** Log `scan.text` (the recognized lines) for the test screenshot and look at how the key line was read.
- **Test that would catch it:** A core test of `AutoRedact.matches(in:patterns:)` with the variants Vision might produce: `sk_test_FAKE0000EXAMPLE1234abcd`, `sk test FAKE0000EXAMPLE1234abcd`, `sktestFAKE0000EXAMPLE1234abcd` and `sk_test FAKE0000EXAMPLE1234abcd`. Each should match the API key pattern. Likely fix: allow a space, an underscore or nothing where the key's underscores are (`[spr]k[_ ]?(?:live|test)[_ ]?[A-Z0-9]{8,}`, and the same for the other prefixes), and add a `TextScan.read` test on a rendered image of the key.
