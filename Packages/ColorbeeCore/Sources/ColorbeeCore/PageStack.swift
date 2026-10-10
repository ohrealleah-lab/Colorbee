/// A document's pages, which one is shown, and the undo of page changes (FR-11.6). Each page undoes its own
/// edits; adding, duplicating, deleting and moving pages are undone here, when such a change is the newest
/// thing done in the document. `noteEdit()` says a page was changed, which makes earlier page changes too old
/// to undo, as edits do in an image.
public final class PageStack {
    public private(set) var pages: [Page]
    public private(set) var currentIndex: Int

    private enum Change {
        case insert([Page], at: Int, name: String)
        case remove(Page, at: Int)
        case move(from: Int, to: Int)

        var name: String {
            switch self {
            case .insert(_, _, let name): name
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

    /// Pages out of the document that undo or redo can still bring back (deleted ones, or added ones undone).
    public var restorablePages: [Page] {
        (undoSteps + redoSteps).map { step -> [Page] in
            switch step.change {
            case .insert(let added, _, _): added.filter { page in !pages.contains { $0 === page } }
            case .remove(let page, _): pages.contains { $0 === page } ? [] : [page]
            case .move: []
            }
        }.flatMap { $0 }
    }

    /// Shows another page: the new one is brought back, the one shown parked.
    public func show(_ index: Int) throws {
        guard pages.indices.contains(index), index != currentIndex else { return }
        try change(to: pages, showing: pages[index])
    }

    /// Puts `newPages` in place, showing `shown`. The page to show is brought back before the old one is parked, and if
    /// either step fails nothing has changed (review K, finding 5): every page but the shown one stays parked.
    private func change(to newPages: [Page], showing shown: Page) throws {
        let old = current
        if shown !== old {
            try shown.unpark()
            do {
                try old.park()
            } catch {
                try? shown.park()
                throw error
            }
        }
        pages = newPages
        currentIndex = newPages.firstIndex { $0 === shown } ?? 0
    }

    /// `pages` without the one at `index`, and the page to show then: the same one, or the next (or previous) if the
    /// one shown is removed.
    private func removing(at index: Int) -> (pages: [Page], shown: Page) {
        var remaining = pages
        let removed = remaining.remove(at: index)
        let shown = removed === current ? remaining[min(index, remaining.count - 1)] : current
        return (remaining, shown)
    }

    private func inserting(_ added: [Page], at index: Int) -> [Page] {
        var all = pages
        all.insert(contentsOf: added, at: min(max(0, index), all.count))
        return all
    }

    /// Forgets every page change and every page's undo history, letting go of deleted pages, so nothing from
    /// before can be brought back (Remove Earlier Versions and Undo History, after a redaction).
    public func forgetHistory() {
        undoSteps = []
        redoSteps = []
        for page in pages { page.history.removeAll() }
    }

    /// A page was edited. Page changes before it can't be undone any more, so their steps, and the deleted pages they
    /// held, are let go (review L, finding 5).
    public func noteEdit() {
        clock += 1
        lastEdit = clock
        undoSteps = []
        redoSteps = []
    }

    /// Adds `page` (parked or not) at `index` and shows it.
    public func insert(_ page: Page, at index: Int) throws {
        try insert([page], at: index, named: "Add Page")
    }

    /// Adds `added` at `index` as one step, showing the first; every other one should already be parked. Undoing it
    /// shows the page before them again (FR-11.7: the page that was shown when pages were imported after it).
    public func insert(_ added: [Page], at index: Int, named name: String) throws {
        guard let first = added.first else { return }
        let index = min(max(0, index), pages.count)
        try change(to: inserting(added, at: index), showing: first)
        record(.insert(added, at: index, name: name))
    }

    /// Deletes the page at `index`; the last page can't be deleted. Shows the page after it, or before.
    public func remove(at index: Int) throws {
        guard pages.count > 1, pages.indices.contains(index) else { return }
        let page = pages[index]
        let after = removing(at: index)
        try change(to: after.pages, showing: after.shown)
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

    /// A step is taken off its list only once it has worked, so a failure leaves it there to try again.
    public func undo() throws {
        guard undoName != nil, let step = undoSteps.last else { return }
        try apply(inverseOf: step.change)
        undoSteps.removeLast()
        redoSteps.append(step)
    }

    public func redo() throws {
        guard let step = redoSteps.last else { return }
        try apply(step.change)
        redoSteps.removeLast()
        clock += 1
        undoSteps.append(Step(change: step.change, stamp: clock))
    }

    private func apply(_ change: Change) throws {
        switch change {
        case .insert(let added, let index, _):
            try self.change(to: inserting(added, at: index), showing: added[0])
        case .remove(let page, _):
            guard let index = pages.firstIndex(where: { $0 === page }), pages.count > 1 else { return }
            let after = removing(at: index)
            try self.change(to: after.pages, showing: after.shown)
        case .move(let source, let destination):
            moveWithoutRecording(from: source, to: destination)
        }
    }

    private func apply(inverseOf change: Change) throws {
        switch change {
        case .insert(let added, _, _) where added.count == 1:
            guard let index = pages.firstIndex(where: { $0 === added[0] }), pages.count > 1 else { return }
            let after = removing(at: index)
            try self.change(to: after.pages, showing: after.shown)
        case .insert(let added, _, _):
            let remaining = pages.filter { page in !added.contains { $0 === page } }
            guard !remaining.isEmpty, let first = pages.firstIndex(where: { $0 === added[0] }) else { return }
            let shown = added.contains { $0 === current } ? remaining[max(0, min(first - 1, remaining.count - 1))] : current
            try self.change(to: remaining, showing: shown)
        case .remove(let page, let index):
            try self.change(to: inserting([page], at: index), showing: page)
        case .move(let source, let destination):
            moveWithoutRecording(from: destination, to: source)
        }
    }
}
