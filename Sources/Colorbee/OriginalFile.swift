import Foundation

/// The file a picture was opened from, kept while it's an unsaved project (stage 34c).
struct OriginalFile: Equatable {
    let url: URL
    let type: String
    /// When it was last changed as Colorbee knew it, so macOS can ask if another app changed it since.
    let modified: Date?

    /// It goes back to the file once it's one plain layer again, unless the project was saved somewhere of its own or
    /// the file is gone; then it stays a project and ⌘S asks where.
    func canReturn(isLayered: Bool, savedAsProject: Bool, exists: Bool) -> Bool {
        !isLayered && !savedAsProject && exists
    }
}
