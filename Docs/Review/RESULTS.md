# Review results

What happened to each finding from the cloud review sessions (see [PLAN.md](PLAN.md)). Every fix has a
regression test that failed before it.

## Session A: undo history, memory and whole-image changes ([findings](findings-A.md))

Reviewed at `d67a862`. All eight findings were real. Fixed on 2026-10-03; tests in
`Packages/ColorbeeCore/Tests/ColorbeeCoreTests/ReviewATests.swift`.

| # | Severity | Finding | Outcome |
|---|---|---|---|
| 1 | Critical | Placing a paste after a layer-settings step merged its pixels into a step that never undoes pixels | **Fixed.** Tile changes only merge into a step that holds tiles; otherwise placing is its own step. |
| 2 | High | History's byte count drifted (even below zero) when a crop, resize or straighten was undone and dropped, on every Straighten, Drop Shadow and Border preview tick | **Fixed.** The count follows the geometry step's size as undo and redo swap it. |
| 3 | Medium | The spill file grew by a full layer each time an unchanged layer was moved out of memory again | **Fixed for layers.** A layer read back keeps a hash of its pixels; moved out again unchanged, its copy on disk is reused. Tile steps still append a new copy when re-spilled after an undo or redo (their pixels have swapped, so the old copy is out of date); the file is deleted when the document closes. |
| 4 | Medium | Undoing a crop whose step was spilled filled empty and adjustment layers with real memory | **Fixed.** Empty layers are recorded as empty and come back as fresh empty buffers. |
| 5 | Medium | A preview tick that drew nothing left the last Straighten, Drop Shadow or Border preview redoable | **Fixed.** An undone preview step is forgotten at once. |
| 6 | Medium | Straighten had no size limit | **Fixed.** It refuses results over 30,000 px a side or 256 megapixels, like Resize and Perspective Correction. |
| 7 | Low | A buffer held by both a geometry step and a layer step was counted twice | **Fixed.** Buffers a geometry step holds aren't counted again as layer bytes. |
| 8 | Low | Straighten without Crop to Fit left an empty solid background's new corners transparent | **Fixed.** Such a layer is drawn so its corners get Color 2. |

Finding 2 is a likely contributor to the heavy memory use in the first 30-minute soak (history could stop
enforcing its budget); the re-run of the soak will show.
