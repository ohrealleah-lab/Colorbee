# Proposal: Import from iPhone or iPad (Continuity Camera)

Status: **proposal, for Leah's decisions** (2026-10-04). Nothing is built. Once decided, the behavior moves into
the FRD (a new FR-11.7) and the decisions into §23.

## Why

Scan with the phone, finish on the Mac. Typical uses:

- **Scanning books** (open-source or public-domain ones): many pages in one go, straightened and cropped by the
  phone, arriving as pages in one Colorbee document, ready to annotate and export as one PDF.
- **Forms and letters:** scan, Auto-Redact every page, Export as PDF. Nothing leaves the Mac except the
  phone-to-Mac handoff, which is Apple's own and device-to-device.
- **A quick photo** of a whiteboard, a screen or an object, straight into the open document.

## What macOS gives us

macOS's **Continuity Camera** lets an app ask a nearby iPhone or iPad (same Apple Account, Wi-Fi and Bluetooth
on) for:

- **Take Photo:** one photo.
- **Scan Documents:** the phone finds each page's edges, straightens and crops it, and can capture many pages in
  a row, in color, grayscale or black and white. You tap Save on the phone and the pages arrive together.
- **Add Sketch:** a drawing made on the iPad or iPhone.

The system builds the menu itself: the devices, each with those three choices. Colorbee only adds the menu item
and receives the result (a photo, or the scanned pages). No camera permission is needed on the Mac, and it needs
no networking of Colorbee's own.

## Proposed behavior

1. **File ▸ Import from iPhone or iPad** (the system's submenu, as in Preview and Notes). Also on the page
   sidebar's right-click menu, since that's where pages are added.
2. **Where the result goes:** with a document open, the photo, sketch or scanned pages are added as **new pages
   just after the page being viewed**, in the order scanned, and Colorbee shows the first of them. With no
   document open, they become a new untitled document. Adding them is one undo step, like adding a page.
3. **Size and resolution:** each page keeps the phone's own pixels; no resampling. A scanned page keeps the
   paper size the phone reports, so Export as PDF gives it the right printed size. A photo counts as 144 DPI,
   like other images.
4. **Color:** each page keeps the phone's color profile (usually Display P3), as with any opened image.
5. **Everything else works as for other pages:** Auto-Redact on every page, annotation, layers, Export as PDF.

## Open questions for Leah

1. **Where scans go.** New pages after the page being viewed (recommended: a book scan builds up in one document
   over several sessions), or always a new document?
2. **Searchable text.** Colorbee's PDFs are pixels only, so a scanned book's text can't be searched or
   selected. An optional "Make text searchable" (on-device Vision text recognition, invisible text behind each
   page) would help books but must never be used on a redacted page, because the hidden text would include what
   was covered. Recommended: **not in the first version**; consider later as an opt-in that's turned off, and
   refused, on any page with a redaction.
3. **Book spreads.** Photographing two facing pages at once is faster than one at a time. A "Split Page in Half"
   command could turn each spread into two pages. Recommended: **later**; Scan Documents one page at a time works
   now.
4. **Add Sketch.** The system shows it alongside Take Photo and Scan Documents. Keep it (recommended: it costs
   nothing and arrives as a page like the rest), or try to hide it?
5. **Scan quality.** The phone decides the scan's resolution. If scans come out softer than wanted, should
   Colorbee warn, or is the phone's choice fine? Recommended: the phone's choice; check during the spike.

## Plan

- **Spike first (an hour or two):** add the menu item and receiving code, and check with Leah's iPhone what
  actually arrives: a PDF of pages or separate images, their pixel size, the paper size reported and the color
  profile. Leah does the phone side; Claude doesn't need her screen. The answers settle points 3 and 5.
- **Then build:** receiving, adding pages after the one viewed (with undo), the page sidebar's menu item,
  tests for adding received pages, and hand-test steps.
- Recommended model and effort: **Opus, high** for the spike (unknowns), **medium** for the rest.

## How Leah would test it

With an iPhone signed into the same Apple Account, near the Mac, Wi-Fi and Bluetooth on:

1. Open `TestImages/Stage 10/Three Page Test.pdf`, go to page 1, then File ▸ Import from iPhone or iPad ▸ (your
   iPhone) ▸ Scan Documents. Scan three book pages, tap Save. Expect pages 2–4 to be the scans, in order, with
   the old pages 2 and 3 now 5 and 6, and page 2 shown.
2. ⌘Z: the three scanned pages go, in one step.
3. With no window open, Take Photo: a new untitled document with the photo.
4. Export as PDF: the scans are the right paper size in Preview.
