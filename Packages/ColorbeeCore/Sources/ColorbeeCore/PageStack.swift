/// A document's pages, which one is shown, and the undo of page changes (FR-11.6). Each page undoes its own
/// edits; adding, duplicating, deleting and moving pages are undone here, when such a change is the newest
/// thing done in the document. `noteEdit()` says a page was changed, which makes earlier page changes too old
/// to undo, as edits do in an image.
public final class PageStack {
    public private(set) var pages: [Page]
    public private(set) var currentIndex: Int

    private enum Change {
        case insert(Page, at: Int)
        case remove(Page, at: Int)
        case move(from: Int, to: Int)

        var name: String {
            switch self {
            case .insert: "Add Page"
            case .remove: "Delete Page"
            case .move: "Move Page"
            }
        }
    }

    private struct Step {
        let change: Change
        let stamp: Int
    }

    private var undoSteps: [Step] = []
    private var redoSteps: [Step] = []
    private var clock = 0
    private var lastEdit = 0

    /// `pages` must not be empty. Every page but the one shown should already be parked.
    public init(pages: [Page], currentIndex: Int = 0) {
        precondition(!pages.isEmpty, "A document has at least one page")
        self.pages = pages
        self.currentIndex = min(max(0, currentIndex), pages.count - 1)
    }

    public var current: Page { pages[currentIndex] }

    /// Shows another page: the one shown is parked, the new one brought back.
    public func show(_ index: Int) throws {
        guard pages.indices.contains(index), index != currentIndex else { return }
        try current.park()
        currentIndex = index
        try current.unpark()
    }

    /// Forgets every page change and every page's undo history, letting go of deleted pages, so nothing from
    /// before can be brought back (Remove Earlier Versions and Undo History, after a redaction).
    public func forgetHistory() {
        undoSteps = []
        redoSteps = []
        for page in pages { page.history.removeAll() }
    }

    /// A page was edited.
    public func noteEdit() {
        clock += 1
        lastEdit = clock
        redoSteps = []
    }

    /// Adds `page` (parked or not) at `index` and shows it.
    public func insert(_ page: Page, at index: Int) throws {
        let index = min(max(0, index), pages.count)
        try current.park()
        pages.insert(page, at: index)
        currentIndex = index
        try current.unpark()
        record(.insert(page, at: index))
    }

    /// Deletes the page at `index`; the last page can't be deleted. Shows the page after it, or before.
    public func remove(at index: Int) throws {
        guard pages.count > 1, pages.indices.contains(index) else { return }
        let page = pages[index]
        try page.park()
        let shown = current
        pages.remove(at: index)
        if shown === page {
            currentIndex = min(index, pages.count - 1)
            try current.unpark()
        } else {
            currentIndex = pages.firstIndex { $0 === shown } ?? 0
        }
        record(.remove(page, at: index))
    }

    public func move(from source: Int, to destination: Int) {
        guard source != destination, pages.indices.contains(source), pages.indices.contains(destination) else { return }
        moveWithoutRecording(from: source, to: destination)
        record(.move(from: source, to: destination))
    }

    private func moveWithoutRecording(from source: Int, to destination: Int) {
        let shown = current
        pages.insert(pages.remove(at: source), at: destination)
        currentIndex = pages.firstIndex { $0 === shown } ?? 0
    }

    private func record(_ change: Change) {
        clock += 1
        undoSteps.append(Step(change: change, stamp: clock))
        redoSteps = []
    }

    /// The page change ⌘Z would undo, if it's newer than every page edit.
    public var undoName: String? {
        guard let step = undoSteps.last, step.stamp > lastEdit else { return nil }
        return step.change.name
    }

    public var redoName: String? { redoSteps.last?.change.name }

    public func undo() throws {
        guard undoName != nil, let step = undoSteps.popLast() else { return }
        try apply(inverseOf: step.change)
        redoSteps.append(step)
    }

    public func redo() throws {
        guard let step = redoSteps.popLast() else { return }
        try apply(step.change)
        clock += 1
        undoSteps.append(Step(change: step.change, stamp: clock))
    }

    private func apply(_ change: Change) throws {
        switch change {
        case .insert(let page, let index):
            try current.park()
            pages.insert(page, at: min(index, pages.count))
            currentIndex = pages.firstIndex { $0 === page } ?? 0
            try current.unpark()
        case .remove(let page, _):
            guard let index = pages.firstIndex(where: { $0 === page }) else { return }
            try removeWithoutRecording(at: index)
        case .move(let source, let destination):
            moveWithoutRecording(from: source, to: destination)
        }
    }

    private func apply(inverseOf change: Change) throws {
        switch change {
        case .insert(let page, _):
            guard let index = pages.firstIndex(where: { $0 === page }) else { return }
            try removeWithoutRecording(at: index)
        case .remove(let page, let index):
            try current.park()
            pages.insert(page, at: min(index, pages.count))
            currentIndex = pages.firstIndex { $0 === page } ?? 0
            try current.unpark()
        case .move(let source, let destination):
            moveWithoutRecording(from: destination, to: source)
        }
    }

    private func removeWithoutRecording(at index: Int) throws {
        guard pages.count > 1 else { return }
        let page = pages[index]
        let shown = current
        try page.park()
        pages.remove(at: index)
        if shown === page {
            currentIndex = min(index, pages.count - 1)
            try current.unpark()
        } else {
            currentIndex = pages.firstIndex { $0 === shown } ?? 0
        }
    }
}
