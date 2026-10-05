import CoreGraphics
import Foundation
import Testing
@testable import ColorbeeCore

/// Stage 10a: pages (FR-11.6).
struct PageTests {
    private let context = SelectionContext(color2: .white)

    private func page(_ value: UInt8) -> Page {
        let canvas = Canvas(size: IntSize(width: 64, height: 48), colorSpace: Canvas.defaultColorSpace, background: .white)
        canvas.layers[0].buffer.fill(Pixel(r: value, g: 40, b: 200), in: IntRect(x: 4, y: 4, width: 20, height: 20))
        return Page(canvas: canvas, history: History(byteBudget: 64 << 20))
    }

    private func paint(_ page: Page, _ value: UInt8) {
        let edit = page.history.beginEdit("Paint", on: page.canvas)
        let rect = IntRect(x: 30, y: 10, width: 10, height: 10)
        edit.willModify(rect, in: page.canvas.activeLayer)
        page.canvas.activeLayer.buffer.fill(Pixel(r: value, g: value, b: 0), in: rect)
        page.history.commit(edit)
    }

    @Test func parkingFreesMemoryAndUnparkingBringsTheSameBuffersBack() throws {
        let page = page(10)
        LayerActions.add(canvas: page.canvas, history: page.history, context: context)
        let buffers = page.canvas.layers.map(\.buffer)
        let before = page.canvas.flattened().contentHash()
        try page.park()
        #expect(page.isParked && page.parkedThumbnail != nil)
        #expect(page.canvas.layers[0].buffer.isDiscarded)
        try page.unpark()
        #expect(zip(buffers, page.canvas.layers.map(\.buffer)).allSatisfy { $0 === $1 })
        #expect(page.canvas.flattened().contentHash() == before)
    }

    @Test func aPageUndoesItsOwnEditsAfterBeingParked() throws {
        let page = page(10)
        let original = page.canvas.flattened().contentHash()
        paint(page, 200)
        LayerActions.add(canvas: page.canvas, history: page.history, context: context)
        paint(page, 90)
        let edited = page.canvas.flattened().contentHash()
        try page.park()
        try page.unpark()
        #expect(page.canvas.flattened().contentHash() == edited)
        while page.history.canUndo { page.history.undo(on: page.canvas) }
        #expect(page.canvas.flattened().contentHash() == original)
    }

    @Test func aFloatingPasteIsntStampedIntoAParkedLayer() throws {
        let page = page(10)
        SelectionActions.paste(PixelBuffer(width: 4, height: 4, fill: .black), at: IntPoint(x: 40, y: 30), canvas: page.canvas,
                               history: page.history, context: context)
        try page.park()
        try page.unpark()
        let layer = page.canvas.layers[0].buffer
        #expect(layer.row(31)[41] == .white)
    }

    /// Stage 10b: an Auto-Redact on several pages undoes as one by matching each page's newest step.
    @Test func aStepKeepsItsIDThroughUndoAndRedo() {
        let page = page(10)
        #expect(page.history.undoStepID == nil)
        paint(page, 200)
        let id = page.history.undoStepID
        #expect(id != nil)
        page.history.undo(on: page.canvas)
        #expect(page.history.redoStepID == id && page.history.undoStepID == nil)
        page.history.redo(on: page.canvas)
        #expect(page.history.undoStepID == id)
        paint(page, 90)
        #expect(page.history.undoStepID != id)
    }

    @Test func pageChangesUndoUntilAPageIsEdited() throws {
        let stack = PageStack(pages: [page(1)])
        try stack.insert(page(2), at: 1)
        try stack.insert(page(3), at: 2)
        #expect(stack.pages.count == 3 && stack.currentIndex == 2)
        #expect(stack.pages[0].isParked && stack.pages[1].isParked && !stack.current.isParked)
        stack.move(from: 2, to: 0)
        #expect(stack.currentIndex == 0)
        try stack.remove(at: 1)
        #expect(stack.pages.count == 2 && stack.undoName == "Delete Page")
        try stack.undo()
        #expect(stack.pages.count == 3)
        try stack.undo()
        #expect(stack.pages[2].resolution == Page.defaultResolution && stack.undoName == "Add Page")
        stack.noteEdit()
        #expect(stack.undoName == nil && stack.redoName == nil)
    }

    /// Remove Earlier Versions and Undo History: no page's edits, and no deleted page, can be brought back.
    @Test func forgettingHistoryForgetsEveryPageAndPageChange() throws {
        let stack = PageStack(pages: [page(1)])
        paint(stack.pages[0], 200)
        try stack.insert(page(2), at: 1)
        paint(stack.pages[1], 90)
        try stack.insert(page(3), at: 2)
        try stack.remove(at: 2)
        #expect(stack.undoName == "Delete Page")
        stack.forgetHistory()
        #expect(stack.undoName == nil && stack.redoName == nil)
        #expect(stack.pages.allSatisfy { !$0.history.canUndo && !$0.history.canRedo })
        #expect(stack.pages.count == 2)
    }

    /// A page whose stored pixels are damaged: its manifest reads, so it opens parked, but it can't be brought back.
    private func damagedPage() throws -> Page {
        var project = try ProjectFile.encode(page(7).canvas)
        let tail = project.count - 64
        project.replaceSubrange(tail..<project.count, with: Data(repeating: 0xFF, count: 64))
        return try Page(stored: ProjectFile.StoredPage(project: project, resolution: 144, thumbnail: nil), history: History(byteBudget: 64 << 20))
    }

    /// Review K, finding 5: a page that can't be brought back leaves everything as it was.
    @Test func showingADamagedPageChangesNothing() throws {
        let stack = PageStack(pages: [page(1), try damagedPage()])
        let shown = stack.current
        let before = shown.canvas.flattened().contentHash()
        #expect(throws: (any Error).self) { try stack.show(1) }
        #expect(stack.currentIndex == 0 && stack.current === shown && !shown.isParked)
        #expect(shown.canvas.flattened().contentHash() == before)
        #expect(stack.pages[1].isParked)
    }

    /// A page change that fails stays on the undo list.
    @Test func aFailedUndoKeepsItsStep() throws {
        let stack = PageStack(pages: [page(1), try damagedPage()])
        try stack.remove(at: 1)
        #expect(stack.undoName == "Delete Page")
        #expect(throws: (any Error).self) { try stack.undo() }
        #expect(stack.undoName == "Delete Page" && stack.pages.count == 1 && !stack.current.isParked)
    }

    /// Review L, finding 5: once a page change can't be undone, a deleted page is let go.
    @Test func aDeletedPageIsFreedOnceItCantComeBack() throws {
        let stack = PageStack(pages: [page(1)])
        try stack.insert(page(2), at: 1)
        weak var deleted = stack.pages[1]
        try stack.remove(at: 1)
        #expect(deleted != nil)
        stack.noteEdit()
        #expect(deleted == nil)
    }

    @Test func deletingTheShownPageShowsTheNextOne() throws {
        let stack = PageStack(pages: [page(1)])
        try stack.insert(page(2), at: 1)
        try stack.show(0)
        try stack.remove(at: 0)
        #expect(stack.pages.count == 1 && !stack.current.isParked)
        try stack.remove(at: 0)
        #expect(stack.pages.count == 1)
        try stack.undo()
        #expect(stack.pages.count == 2 && stack.currentIndex == 0 && !stack.current.isParked)
    }
}

struct PageProjectTests {
    private func page(_ value: UInt8, width: Int = 64) -> Page {
        let canvas = Canvas(size: IntSize(width: width, height: 48), colorSpace: Canvas.defaultColorSpace, background: .white)
        canvas.layers[0].buffer.fill(Pixel(r: value, g: 40, b: 200), in: IntRect(x: 4, y: 4, width: 20, height: 20))
        return Page(canvas: canvas, history: History(byteBudget: 64 << 20))
    }

    @Test func aProjectOfSeveralPagesReadsBackParked() throws {
        let stack = PageStack(pages: [page(10)])
        try stack.insert(page(120, width: 80), at: 1)
        stack.pages[1].resolution = 200
        let hashes = try stack.pages.map { page -> Int in
            if page.isParked { return try ProjectFile.decode(page.parked!).flattened().contentHash() }
            return page.canvas.flattened().contentHash()
        }
        let data = try ProjectFile.encode(pages: stack.pages, currentIndex: stack.currentIndex)
        let (stored, current) = try ProjectFile.storedPages(data)
        #expect(stored.count == 2 && current == 1)
        #expect(stored[1].resolution == 200 && stored[0].thumbnail != nil)
        let pages = try stored.map { try Page(stored: $0, history: History(byteBudget: 64 << 20)) }
        #expect(pages.allSatisfy { $0.isParked })
        #expect(pages[1].canvas.size == IntSize(width: 80, height: 48))
        for (page, hash) in zip(pages, hashes) {
            try page.unpark()
            #expect(page.canvas.flattened().contentHash() == hash)
        }
    }

    /// Review K, finding 6: a one-page project keeps its page's resolution.
    @Test func aOnePageProjectKeepsItsResolution() throws {
        let single = page(10)
        single.resolution = 300
        let data = try ProjectFile.encode(pages: [single], currentIndex: 0)
        #expect(data.starts(with: ProjectFile.magic))
        #expect(try ProjectFile.storedPages(data).pages[0].resolution == 300)
        #expect(try ProjectFile.decode(data).flattened().contentHash() == single.canvas.flattened().contentHash())
        let plain = try ProjectFile.encode(pages: [page(10)], currentIndex: 0)
        #expect(try ProjectFile.storedPages(plain).pages[0].resolution == Page.defaultResolution)
    }

    /// Review L, finding 7: pages made four at a time still come out in order.
    @Test func pagesMadeInParallelStayInOrder() throws {
        let stored = try ProjectFile.storedPages(count: 11) { index in
            (page(UInt8(index * 20)).canvas, Double(100 + index))
        }
        #expect(stored.map(\.resolution) == (0..<11).map { Double(100 + $0) })
    }

    /// Review K, finding 9: absurd thumbnail sizes in a damaged file are ignored, not multiplied.
    @Test func aHugeThumbnailSizeDoesntCrash() throws {
        let project = try ProjectFile.encode(page(1).canvas)
        let huge = ProjectFile.ThumbnailEntry(width: 3_037_000_500, height: 3_037_000_500, pixels: Data(count: 16))
        let manifest = ProjectFile.PagesManifest(currentIndex: 0, pages: [
            ProjectFile.PageEntry(resolution: 144, project: 0..<project.count, thumbnail: huge),
            ProjectFile.PageEntry(resolution: 144, project: 0..<project.count, thumbnail: nil),
        ])
        let json = try JSONEncoder().encode(manifest)
        var data = ProjectFile.pagesMagic
        var length = UInt32(json.count).littleEndian
        data.append(Data(bytes: &length, count: 4))
        data.append(json)
        data.append(project)
        let stored = try ProjectFile.storedPages(data)
        #expect(stored.pages.count == 2 && stored.pages[0].thumbnail == nil)
    }

    @Test func aOnePageProjectIsWrittenAsBefore() throws {
        let single = page(10)
        let data = try ProjectFile.encode(pages: [single], currentIndex: 0)
        #expect(data.starts(with: ProjectFile.magic))
        let canvas = try ProjectFile.decode(data)
        #expect(canvas.flattened().contentHash() == single.canvas.flattened().contentHash())
        let stored = try ProjectFile.storedPages(data)
        #expect(stored.pages.count == 1)
    }
}

struct PDFPagesTests {
    /// A two-page letter PDF: a black square on page 1, a red one on page 2, one inch in from the top-left.
    private func pdf() -> Data {
        let data = NSMutableData()
        var media = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = CGDataConsumer(data: data as CFMutableData)!
        let context = CGContext(consumer: consumer, mediaBox: &media, nil)!
        for color in [CGColor(gray: 0, alpha: 1), CGColor(red: 1, green: 0, blue: 0, alpha: 1)] {
            context.beginPDFPage(nil)
            context.setFillColor(color)
            context.fill(CGRect(x: 72, y: 792 - 144, width: 72, height: 72))
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    @Test func pagesRenderAtTheChosenResolution() throws {
        let data = pdf()
        #expect(try PDFPages.pageCount(data) == 2)
        let (first, resolution) = try PDFPages.render(data, page: 0, resolution: 144)
        #expect(resolution == 144)
        #expect(first.size == IntSize(width: 1224, height: 1584))
        let buffer = first.layers[0].buffer
        #expect(buffer.row(10)[10] == .white)
        #expect(buffer.row(200)[200] == .black)
        let (second, _) = try PDFPages.render(data, page: 1, resolution: 72)
        let red = second.layers[0].buffer.row(100)[100]
        #expect(red.r > 200 && red.g < 60 && red.b < 60 && red.a == 255)
        #expect(throws: (any Error).self) { try PDFPages.render(data, page: 2, resolution: 72) }
    }

    @Test func notAPDFIsAnError() {
        #expect(throws: (any Error).self) { try PDFPages.pageCount(Data("hello".utf8)) }
    }
}
