import AppKit
import Testing
@testable import Colorbee

/// Leah uses the Mac while tests run: Colorbee must start hidden for them, with no windows and no focus.
@MainActor
struct TestHostTests {
    @Test func startsHiddenWithNoWindows() {
        #expect(TestHost.isActive)
        #expect(NSApp.delegate is TestHost)
        #expect(NSApp.activationPolicy() == .prohibited)
        #expect(!NSApp.isActive)
        #expect(NSApp.windows.filter(\.isVisible).isEmpty)
        #expect(NSDocumentController.shared.documents.isEmpty)
    }
}
