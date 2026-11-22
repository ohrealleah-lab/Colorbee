import Foundation

/// The file a picture was opened from, kept while it's an unsaved project (stage 34c).
struct OriginalFile: Equatable {
    let url: URL
    let type: String
    /// When it was last changed as Colorbee knew it, so macOS can ask if another app changed it since.
    let modified: Date?

    /// It goes back to the file once it's one plain layer again, unless the project was saved somewhere of its own,
    /// the file is gone, or another window has it open; then it stays a project and ⌘S asks where. The disk and the
    /// other windows are only asked once the rest allows it: this runs after every edit, and a disk that's gone away
    /// can take seconds to answer (review AI, findings 5 and 8).
    func canReturn(isLayered: Bool, savedAsProject: Bool, exists: @autoclosure () -> Bool,
                   openElsewhere: @autoclosure () -> Bool = false) -> Bool {
        !isLayered && !savedAsProject && !openElsewhere() && exists()
    }
}
