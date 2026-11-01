import ColorbeeCore
import CoreGraphics
import Foundation

/// An Auto-Redact review in progress (FR-9.3): every page, whole, whatever is selected (FR-11.6).
struct AutoRedactSession {
    /// One page that was read, and what was found on it.
    struct PageResult {
        let pageID: UUID
        /// The page as it was read; Apply refuses if it has changed since (review E, finding 2).
        let revision: Int
        let canvasSize: IntSize
        var scan: TextScan?
        /// The faces Vision found (FR-9.7 item 10), each with an id kept while the review is open.
        var faces: [(id: UUID, rect: IntRect)]?
        var matches: [RedactionMatch] = []
    }

    /// Tells this run's scan from an earlier run's that finishes late.
    let id = UUID()
    /// Some page read has more than one layer, so hidden layers matter.
    let anyLayered: Bool
    /// In page order.
    var pages: [PageResult]
    /// Why Apply couldn't redact (a page changed, or a layer is locked).
    var problem: String?
    var failure: String?
    /// The page that couldn't be read. Pages after it weren't read either, so nothing can be applied (review K, finding 2).
    var failedPage: UUID?
    /// Matches the person unchecked to keep visible.
    var keptVisible: Set<UUID> = []
    var treatment: RedactionTreatment = .solidFill
    /// The match last clicked in the list.
    var focused: UUID?
    /// While Apply works through the pages: how many are done, of how many.
    var applying: (done: Int, total: Int)?

    var isReading: Bool { failure == nil && pages.contains { $0.scan == nil || $0.faces == nil } }
    var pagesRead: Int { pages.count { $0.scan != nil && $0.faces != nil } }
    var isMultiPage: Bool { pages.count > 1 }
    var matches: [RedactionMatch] { pages.flatMap(\.matches) }
    var selectedMatches: [RedactionMatch] { matches.filter { !keptVisible.contains($0.id) } }

    func matches(onPage id: UUID) -> [RedactionMatch] {
        pages.first { $0.pageID == id }?.matches ?? []
    }

    func selectedMatches(onPage id: UUID) -> [RedactionMatch] {
        matches(onPage: id).filter { !keptVisible.contains($0.id) }
    }
}
