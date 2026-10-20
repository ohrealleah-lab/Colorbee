import AppKit
import Testing
@testable import Colorbee

/// Review R, finding 3: View menu toggles still work while an effect's bar is open, so their checkmarks must follow.
@MainActor
struct MenuCheckmarkTests {
    @Test func rulersCheckmarkFollowsWhileAnEffectIsOpen() {
        let editor = makeEditor()
        editor.showsRulers = true
        editor.beginEffect(.gaussianBlur)
        #expect(editor.blocksDocumentCommands)
        let item = NSMenuItem(title: "Rulers", action: #selector(DocumentWindow.toggleRulers(_:)), keyEquivalent: "")
        #expect(DocumentWindow.isOn(item, in: editor) == true)
        editor.showsRulers = false
        #expect(DocumentWindow.isOn(item, in: editor) == false)
        #expect(DocumentWindow.isOn(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: ""), in: editor) == nil)
        editor.cancelEffect()
    }
}
