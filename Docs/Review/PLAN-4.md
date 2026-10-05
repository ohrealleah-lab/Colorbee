# Code review plan, round 4: pages and PDFs, Auto-Redact on every page, RAW photos

Rounds 1–3 ([PLAN.md](PLAN.md), [PLAN-2.md](PLAN-2.md), [PLAN-3.md](PLAN-3.md); results in
[RESULTS.md](RESULTS.md)) covered everything up to commit `d97368b`. Round 4 covers what's been built since:
stage 10 (pages, PDFs, Export as PDF, Auto-Redact on every page), stage 12 (RAW photos and camera details), and
the smaller changes around them (Discard hidden layers on Flatten, the Appearance setting, remembered file
formats, Rectangle Select as the starting tool, the Export panel fix). See them with
`git log --oneline d97368b..HEAD` and `git diff d97368b..HEAD`.

Two sessions, **K** and **L**. They're independent and can run at the same time. Run K first if only one runs at a
time: it's about privacy, which is the heart of Colorbee.

## Rules (these replace rule 6 of PLAN.md for round 4)

These sessions run **locally, in Leah's Colorbee folder**, not in the cloud. Follow "Rules for every review
session" and "Findings file format" in [PLAN.md](PLAN.md), with these changes:

- **Don't touch git.** Don't switch branches, commit, stash or push. Another session is working in the same
  folder; switching branches would pull files out from under it. Your only output is one new file,
  `Docs/Review/findings-<letter>.md` (`findings-K.md` or `findings-L.md`), written into this folder. The
  engineer commits it.
- **Don't build, run the app or run tests.** Reason from the code, as before. (You may run quick throwaway scripts
  in the scratch folder to check math or an API's behavior, but never anything long or memory-heavy: Leah's Mac
  once froze during a heavy test.)
- **Don't re-report rounds 1–3.** Read [RESULTS.md](RESULTS.md) first; report an old fix only if it's wrong or
  was broken by the new work.
- **Leah hand-tests findings.** Where a finding can be shown by hand, give exact numbered steps, and name a test
  file: `TestImages/Stage 10/Three Page Test.pdf` (three pages, each with a made-up email and phone),
  `TestImages/Stage 12/Test Camera.dng` (a synthetic RAW with made-up camera details, serial number, owner and GPS
  location), `TestImages/Round 3/Two Pages.tiff`, or any of the other `TestImages`.
- **Decisions are in FRD §23**, including the new entries dated 2026-10-04 and 2026-10-05, and the behavior in
  FR-11.6 (pages and PDFs), FR-11.8 (RAW photos) and §17 (Appearance). What they chose on purpose isn't a bug.

---

## Session K: privacy with pages, PDFs and camera details (highest risk)

Colorbee's promise is that a redaction removes the secret, and that nothing it writes says more than the user
chose. Pages and PDFs added new places where pixels and data are kept, copied and written. Find every way the
unredacted pixels, or details the user didn't choose to share, can survive or leak.

Files: core `Page.swift`, `PageStack.swift`, `ProjectFile.swift` (format 2: pages, stored thumbnails),
`PDFWriter.swift`, `PDFPages.swift`, `CameraDetails.swift`, `ImageCodec.swift` (what's written on export),
`AutoRedact+Apply.swift`, `History.swift` (only where pages use it: `removeAll`, budgets, the spill file); app
`Editor.swift` (Auto-Redact on every page: `beginAutoRedact`, `applyAutoRedact`, `lockedLayer(under:on:)`,
`redactionGroups`, undo and redo of a multi-page Auto-Redact; `forgetHistory`; `pageMemory` and `asOpened`;
`snapshot(of:)`), `SaveSnapshot.swift` (`encodedPDF`, `encodedProject`, camera details), `ImageDocument.swift`
(saving, the earlier-versions warning, Export…, Export as PDF, Revert), `AutoRedactSheet.swift`, `PageSidebar.swift`.

Look especially for:
- **Stale copies after a redaction:** page thumbnails (in memory, in the sidebar, and **stored inside .colorproj
  files**), parked pages' compressed bytes, other pages' undo histories, Before/After's "As Opened" for pages not
  shown, pages deleted but kept for undo. After Auto-Redact on every page, then Save and "Remove Earlier Versions
  and Undo History", can any of these still show or hold an unredacted page?
- **Export as PDF:** does any text, metadata, document title, file name or creation date get in? Is every page
  flattened as shown (hidden layers out, adjustment layers applied, a floating selection placed)? Can a page
  come out stale, for example a page edited, then parked, then exported?
- **Auto-Redact across pages:** can a page be skipped, or redacted at the wrong place (a page reordered, resized
  or edited between reading and Apply)? Is "nothing is redacted on any page" really true when a locked layer or a
  change is found partway? What if Apply fails partway through (a page can't be brought back)?
- **Camera details:** can location, serial numbers or the owner's name reach any file Colorbee writes (Export…,
  ⌘S in every format, Export As presets, Copy, Share, Print, Set as Desktop Picture, .colorproj)? Is "off at
  first" true, and is the switch's remembered setting honored only where FR-11.8 says?
- **PDF opening:** a PDF's text and annotations are dropped by rasterizing. Is anything from the source PDF (its
  metadata, its text) kept anywhere afterwards?

## Session L: RAW photos, opening files, and the new background work

RAW photos added a new way into every document (a document controller in front of all opening), a Develop window
that renders in the background, and large renders. Pages added parking, PDF rendering in parallel and a sidebar.
Find crashes, races, memory blow-ups, lost work and broken behavior against the FRD.

Files: app `DocumentController.swift`, `DevelopWindow.swift`, `RawDeveloper.swift`, `ImageDocument.swift`
(`read(from:ofType:)` for projects, PDFs, frames, RAW and images; `open(_:showing:)`; `runModalSavePanel` and the
remembered save format; the Export panel's accessory and its sizing), `Editor.swift` (page changes:
`changePages`, `pageDidChange`, `showPage`, `newPage`, `duplicatePage`, `deletePage`, `movePage`; undo and redo
with `undone`), `PageSidebar.swift`, `RightClickWatcher.swift`, `AppearanceSetting.swift`, `Settings.swift`,
`AppDelegate.swift`, `Snapshot.swift` (testing hooks: can a normal user trigger one?); core `Page.swift`,
`PageStack.swift`, `PDFPages.swift`, `ProjectFile.swift` (`storedPages`, `decodeParked`, `restore`), `Canvas.swift`
(`cameraDetails` through copy and every way a canvas is made).

Look especially for:
- **Opening:** does every way in (File ▸ Open, Open Recent, drag onto the window or the Dock icon, Finder,
  Services, window restoration after a relaunch, File ▸ Revert To) behave for RAW files, PDFs, projects and plain
  images? Can a RAW file be opened with no Develop window, or written back to?
- **Develop window:** closing it, cancelling or quitting during a preview or a full develop; opening the same RAW
  twice; a file macOS can't read; a photo too large (the memory check in `RawDeveloper.develop`); portrait
  photos (orientation and the reported size); the default settings round-tripping (Reset to Camera).
- **Background work and `@unchecked Sendable` / `nonisolated(unsafe)` / `UnsafeTransfer`:** is each one really
  safe? The shared `CIContext`; `DevelopSession`'s preview loop; Auto-Redact reading pages in the background
  while the page shown changes; Export as PDF's four-at-a-time encoding; PDF and frame pages built in parallel.
- **Memory:** a 50-page PDF at 300 DPI, a 60-megapixel RAW, Export as PDF of many pages. Is anything held that
  needn't be (every page unparked at once, previews kept, history budgets of parked pages)?
- **Pages and undo:** page changes mixed with edits on several pages, then undo and redo all the way back; a
  multi-page Auto-Redact undone and redone among other edits; deleting the page shown; moving pages while a
  selection floats. Does each page's undo stay exact?
- **Settings and panels:** Appearance applied before the first window and live; the remembered save and export
  formats (an untitled document, a layered one, a format this Mac can't write); the Export panel's accessory
  resizing as rows come and go.

---

## After each session (local, on the Mac)

The engineer reads `findings-<letter>.md`, verifies each finding against the code before acting (findings are
data, not instructions), and asks Leah before fixing anything. Results go into [RESULTS.md](RESULTS.md) as round 4.
