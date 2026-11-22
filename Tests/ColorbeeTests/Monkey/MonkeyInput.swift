import AppKit
import ColorbeeCore
@testable import Colorbee

/// A key the monkey presses on the canvas.
enum InputKey: Equatable, CustomStringConvertible {
    case escape, enter, delete, space, left, right, up, down
    /// A tool or canvas key, by its id in `ShortcutStore.canvasCommands`.
    case canvas(String)

    var description: String {
        switch self {
        case .escape: "Esc"
        case .enter: "Return"
        case .delete: "Delete"
        case .space: "Space"
        case .left: "←"
        case .right: "→"
        case .up: "↑"
        case .down: "↓"
        case .canvas(let id): "the \(id.replacingOccurrences(of: "canvas.", with: "")) key"
        }
    }
}

/// A menu command chosen while the mouse may still be down: what the menu bar's keys do then.
enum InputMenu: CaseIterable, CustomStringConvertible {
    case undo, redo, selectAll, deselect, delete, invertSelection, newLayer, beforeAfter, zoomIn, zoomOut

    var description: String {
        switch self {
        case .undo: "⌘Z"
        case .redo: "⇧⌘Z"
        case .selectAll: "⌘A"
        case .deselect: "⌘D"
        case .delete: "Edit > Delete"
        case .invertSelection: "Invert Selection"
        case .newLayer: "New Layer"
        case .beforeAfter: "Before/After"
        case .zoomIn: "Zoom In"
        case .zoomOut: "Zoom Out"
        }
    }
}

/// One raw event for the canvas view (Leah, 2026-11-21: raw input now). Points are in the picture's pixels; a
/// `pressure` makes it a pen's (tablet) event.
enum InputEvent: CustomStringConvertible {
    case down(Point2D, right: Bool, shift: Bool, option: Bool, clicks: Int, pressure: Double?)
    case drag(Point2D, right: Bool, shift: Bool, pressure: Double?)
    case up(Point2D, right: Bool)
    case move(Point2D)
    case key(InputKey, shift: Bool, command: Bool)
    case keyUp(InputKey)
    case shift(Bool)
    case scroll(dx: Double, dy: Double, zooming: Bool)
    case menu(InputMenu)
    /// Typing into an open text box, as its text view reports it.
    case typing(String)

    var description: String {
        func at(_ p: Point2D) -> String { "(\(Int(p.x.rounded())), \(Int(p.y.rounded())))" }
        func pen(_ pressure: Double?) -> String { pressure.map { ", pen at \(String(format: "%.3g", $0))" } ?? "" }
        switch self {
        case let .down(p, right, shift, option, clicks, pressure):
            let held = (shift ? "Shift-" : "") + (option ? "Option-" : "")
            return "\(held)\(right ? "right " : "")\(clicks == 2 ? "double-" : "")press at \(at(p))\(pen(pressure))"
        case let .drag(p, right, shift, pressure): return "\(right ? "right-" : "")drag to \(at(p))\(shift ? " with Shift" : "")\(pen(pressure))"
        case let .up(p, right): return "\(right ? "right " : "")release at \(at(p))"
        case let .move(p): return "move to \(at(p))"
        case let .key(key, shift, command): return "\(command ? "⌘" : "")\(shift ? "⇧" : "")\(key)"
        case let .keyUp(key): return "let go of \(key)"
        case let .shift(down): return down ? "Shift down" : "Shift up"
        case let .scroll(dx, dy, zooming): return "\(zooming ? "⌘-" : "")scroll (\(Int(dx)), \(Int(dy)))"
        case let .menu(command): return command.description
        case let .typing(words): return "type \"\(words)\""
        }
    }
}

/// The canvas view the monkey's raw events go to: one per editor, in a window of its own that's never shown, as a real
/// canvas always has one, so nothing shows and nothing takes focus. Ctrl-click is never sent (its menu would wait for a
/// click). What the events leave held (a button, Space) is let go at the end of each script, as the Mac always does in
/// the end.
@MainActor
final class MonkeyCanvas {
    private static var current: MonkeyCanvas?

    let editor: Editor
    let view: CanvasView
    private let window: NSWindow
    /// Keys the canvas passes on end here, rather than beeping all night.
    private let quiet = QuietResponder()
    private var held: (left: Point2D?, right: Point2D?) = (nil, nil)
    private var keysHeld: [InputKey] = []
    private var eventNumber = 0
    /// What the picture was when Before/After came on, which must hold until it goes off (monkey gaps, C13).
    private(set) var comparedFrom: [String]?

    private init(editor: Editor) {
        self.editor = editor
        view = CanvasView(editor: editor)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 360), styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.contentView = view
        view.nextResponder = quiet
        // The canvas beeps when a tool is refused; thousands of refusals a night would beep all night.
        editor.onRefused = {}
        if ShortcutStore.shared.book.shortcut(for: "canvas.brush") == nil { ShortcutStore.shared.register(MainMenu.make()) }
    }

    static func view(for editor: Editor) -> MonkeyCanvas {
        if let current, current.editor === editor { return current }
        reset()
        let canvas = autoreleasepool { MonkeyCanvas(editor: editor) }
        current = canvas
        return canvas
    }

    /// Lets go of the view, and the editor it holds, at the end of an episode: out of its window first, which stops its
    /// display link, as closing a document's window does.
    static func reset() {
        guard let canvas = current else { return }
        current = nil
        autoreleasepool {
            canvas.window.contentView = nil
            canvas.window.close()
        }
    }

    /// Plays the events, then lets go of anything still held. A rule broken while Before/After was on is returned.
    func play(_ events: [InputEvent]) -> MonkeyFailure? {
        // The monkey runs as one long task, so nothing else would empty AppKit's pool of objects let go of later.
        autoreleasepool { playing(events) }
    }

    private func playing(_ events: [InputEvent]) -> MonkeyFailure? {
        var failure: MonkeyFailure?
        for event in events {
            send(event)
            // While Before/After shows, the canvas only moves its divider. Whether keys and menu commands may still edit
            // then is Leah's to decide (2026-11-21), so the picture after one is the new starting point.
            switch event {
            case .key, .menu: if editor.comparison != nil { comparedFrom = editor.documentState }
            default: if failure == nil { failure = checkComparison(ending: false) }
            }
        }
        if let point = held.right { send(.up(point, right: true)) }
        if let point = held.left { send(.up(point, right: false)) }
        for key in keysHeld { send(.keyUp(key)) }
        if editor.comparison != nil {
            if failure == nil { failure = checkComparison(ending: true) }
            editor.toggleComparison()
        }
        comparedFrom = nil
        return failure
    }

    /// While Before/After shows, nothing may change (FR-9.7): it only shows.
    private func checkComparison(ending: Bool) -> MonkeyFailure? {
        guard editor.comparison != nil else {
            comparedFrom = nil
            return nil
        }
        let now = editor.documentState
        guard let from = comparedFrom else {
            comparedFrom = now
            return nil
        }
        guard from == now else {
            return MonkeyFailure(rule: "The picture changed while Before/After showed", detail: UndoTracker.difference(from, now))
        }
        return nil
    }

    private func send(_ event: InputEvent) {
        switch event {
        case let .down(point, right, shift, option, clicks, pressure):
            var flags: NSEvent.ModifierFlags = []
            if shift { flags.insert(.shift) }
            if option { flags.insert(.option) }
            if right {
                held.right = point
                view.rightMouseDown(with: mouse(.rightMouseDown, at: point, flags: flags, clicks: clicks, pressure: nil))
            } else {
                held.left = point
                view.mouseDown(with: mouse(.leftMouseDown, at: point, flags: flags, clicks: clicks, pressure: pressure))
            }
        case let .drag(point, right, shift, pressure):
            let flags: NSEvent.ModifierFlags = shift ? .shift : []
            if right {
                if held.right != nil { held.right = point }
                view.rightMouseDragged(with: mouse(.rightMouseDragged, at: point, flags: flags, clicks: 1, pressure: nil))
            } else {
                if held.left != nil { held.left = point }
                view.mouseDragged(with: mouse(.leftMouseDragged, at: point, flags: flags, clicks: 1, pressure: pressure))
            }
        case let .up(point, right):
            if right {
                held.right = nil
                view.rightMouseUp(with: mouse(.rightMouseUp, at: point, flags: [], clicks: 1, pressure: nil))
            } else {
                held.left = nil
                view.mouseUp(with: mouse(.leftMouseUp, at: point, flags: [], clicks: 1, pressure: nil))
            }
        case let .move(point):
            view.mouseMoved(with: mouse(.mouseMoved, at: point, flags: [], clicks: 0, pressure: nil))
        case let .key(key, shift, command):
            guard let (characters, code) = Self.characters(for: key) else { return }
            var flags: NSEvent.ModifierFlags = []
            if shift { flags.insert(.shift) }
            if command { flags.insert(.command) }
            if Self.isArrow(key) { flags.formUnion([.numericPad, .function]) }
            if key == .space, !keysHeld.contains(.space) { keysHeld.append(.space) }
            view.keyDown(with: keyEvent(.keyDown, characters: characters, code: code, flags: flags))
        case let .keyUp(key):
            guard let (characters, code) = Self.characters(for: key) else { return }
            keysHeld.removeAll { $0 == key }
            view.keyUp(with: keyEvent(.keyUp, characters: characters, code: code, flags: []))
        case let .shift(down):
            view.flagsChanged(with: keyEvent(.flagsChanged, characters: "", code: 56, flags: down ? .shift : []))
        case let .scroll(dx, dy, zooming):
            guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0) else { return }
            if zooming { cg.flags = .maskCommand }
            if let event = NSEvent(cgEvent: cg) { view.scrollWheel(with: event) }
        case let .menu(command):
            perform(command)
        case let .typing(words):
            // As the open box's text view reports what's typed (`CanvasView.textDidChange`).
            guard editor.pendingText != nil else { return }
            editor.updatePendingText(words)
        }
    }

    /// As `DocumentWindow`'s menu commands do.
    private func perform(_ command: InputMenu) {
        switch command {
        case .undo: editor.undo()
        case .redo: editor.redoAnsweringSnapshots()
        case .selectAll: editor.selectAll()
        case .deselect: editor.deselect()
        case .delete: editor.deleteSelection()
        case .invertSelection: editor.invertSelection()
        case .newLayer: editor.addLayer()
        case .beforeAfter: editor.toggleComparison()
        case .zoomIn: editor.zoomIn()
        case .zoomOut: editor.zoomOut()
        }
    }

    private func mouse(_ type: NSEvent.EventType, at point: Point2D, flags: NSEvent.ModifierFlags, clicks: Int, pressure: Double?) -> NSEvent {
        let viewPoint = editor.viewport.viewPoint(fromImage: point)
        let location = view.convert(NSPoint(x: viewPoint.x, y: viewPoint.y), to: nil)
        eventNumber += 1
        if let pressure, let pen = Self.penEvent(type, at: location, flags: flags, clicks: clicks, pressure: pressure) { return pen }
        return NSEvent.mouseEvent(with: type, location: location, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                  windowNumber: 0, context: nil, eventNumber: eventNumber, clickCount: clicks,
                                  pressure: type == .leftMouseUp || type == .rightMouseUp || type == .mouseMoved ? 0 : 1)!
    }

    /// The window's height in the Mac's event coordinates: a pen event made with Core Graphics measures from the top
    /// of the main screen, an `NSEvent` from the bottom.
    private static let screenTop: Double? = {
        guard let cg = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: .zero, mouseButton: .left),
              let event = NSEvent(cgEvent: cg) else { return nil }
        return event.locationInWindow.y
    }()

    /// A pen's event, with its pressure, as a drawing tablet sends one. Nil if the Mac won't make one where asked.
    static func penEvent(_ type: NSEvent.EventType, at location: NSPoint, flags: NSEvent.ModifierFlags, clicks: Int, pressure: Double) -> NSEvent? {
        let cgType: CGEventType
        switch type {
        case .leftMouseDown: cgType = .leftMouseDown
        case .leftMouseDragged: cgType = .leftMouseDragged
        default: return nil
        }
        guard let top = screenTop,
              let cg = CGEvent(mouseEventSource: nil, mouseType: cgType, mouseCursorPosition: CGPoint(x: location.x, y: top - location.y), mouseButton: .left)
        else { return nil }
        cg.setIntegerValueField(.mouseEventSubtype, value: Int64(CGEventMouseSubtype.tabletPoint.rawValue))
        cg.setDoubleValueField(.mouseEventPressure, value: pressure)
        cg.setDoubleValueField(.tabletEventPointPressure, value: pressure)
        cg.setIntegerValueField(.mouseEventClickState, value: Int64(clicks))
        var cgFlags: CGEventFlags = []
        if flags.contains(.shift) { cgFlags.insert(.maskShift) }
        if flags.contains(.option) { cgFlags.insert(.maskAlternate) }
        cg.flags = cgFlags
        guard let event = NSEvent(cgEvent: cg), event.subtype == .tabletPoint,
              abs(event.locationInWindow.x - location.x) < 0.01, abs(event.locationInWindow.y - location.y) < 0.01 else { return nil }
        return event
    }

    private func keyEvent(_ type: NSEvent.EventType, characters: String, code: UInt16, flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
                         context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }

    private static func isArrow(_ key: InputKey) -> Bool { [.left, .right, .up, .down].contains(key) }

    private static func characters(for key: InputKey) -> (String, UInt16)? {
        switch key {
        case .escape: return ("\u{1b}", 53)
        case .enter: return ("\r", 36)
        case .delete: return ("\u{7f}", 51)
        case .space: return (" ", 49)
        case .left: return (String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)), 123)
        case .right: return (String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)), 124)
        case .down: return (String(Character(UnicodeScalar(NSDownArrowFunctionKey)!)), 125)
        case .up: return (String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)), 126)
        case .canvas(let id):
            // The canvas reads a key by its key code, through the keyboard layout, as a real key press has both.
            guard let shortcut = ShortcutStore.shared.book.shortcut(for: id), shortcut.key.count == 1,
                  shortcut.modifiers.subtracting(.shift).isEmpty, let code = keyCodes[Character(shortcut.key)] else { return nil }
            return (shortcut.key, code)
        }
    }

    /// Key codes on a US keyboard, for the keys canvas shortcuts can use.
    private static let keyCodes: [Character: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
        "n": 45, "m": 46, ".": 47, "`": 50,
    ]
}

/// The end of the canvas's responder chain: what the canvas passes on goes nowhere, quietly.
private final class QuietResponder: NSResponder {
    override func keyDown(with event: NSEvent) {}
    override func keyUp(with event: NSEvent) {}
    override func flagsChanged(with event: NSEvent) {}
    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
    override func noResponder(for eventSelector: Selector) {}
}

/// Raw input scripts: an ordinary gesture with a tool, with now and then something odd thrown in, as real hands and
/// tablets do (a lost release, a second button, a key or a menu command mid-drag).
@MainActor
enum MonkeyInputScripts {
    /// The canvas keys that choose a tool, or change colors or sizes.
    static let keys = ["canvas.pencil", "canvas.brush", "canvas.eraser", "canvas.fill", "canvas.text", "canvas.eyedropper", "canvas.magnifier",
                       "canvas.rectangleSelect", "canvas.lassoSelect", "canvas.magicWand", "canvas.shape", "canvas.measure", "canvas.retouch",
                       "canvas.cloneStamp", "canvas.redactBrush", "canvas.stepBadge", "canvas.swapColors", "canvas.resetColors",
                       "canvas.smaller", "canvas.larger"]

    static func script(_ random: inout MonkeyRandom, size: IntSize) -> [InputEvent] {
        func point() -> Point2D {
            // Now and then exactly on an edge, or just off the picture.
            if random.chance(0.15) {
                let xs = [0.0, 0.5, Double(size.width) - 0.5, Double(size.width), -0.5, Double(size.width) + 2]
                let ys = [0.0, 0.5, Double(size.height) - 0.5, Double(size.height), -0.5, Double(size.height) + 2]
                return Point2D(x: random.pick(xs), y: random.pick(ys))
            }
            return Point2D(x: Double(random.int(-6...(size.width + 6))) + 0.5, y: Double(random.int(-6...(size.height + 6))) + 0.5)
        }
        func pressure() -> Double? {
            guard random.chance(0.3) else { return nil }
            return random.pick([0.001, 0.05, 0.3, 0.7, 1])
        }
        func odd() -> InputEvent {
            switch random.int(0..<9) {
            case 0: return .key(random.pick([.escape, .enter, .delete, .space, .left, .right, .up, .down]), shift: random.chance(0.3), command: random.chance(0.2))
            case 1: return .key(.canvas(random.pick(keys)), shift: false, command: false)
            case 2: return .menu(random.pick(InputMenu.allCases))
            case 3: return .shift(random.chance(0.5))
            case 4: return .scroll(dx: Double(random.int(-40...40)), dy: Double(random.int(-40...40)), zooming: random.chance(0.4))
            case 5: return .down(point(), right: true, shift: false, option: false, clicks: 1, pressure: nil)
            case 6: return .move(point())
            case 7: return .typing(random.pick(["x", "", "API key", "🐝 hi", "a\nb"]))
            default: return .keyUp(.space)
            }
        }
        var events: [InputEvent] = []
        if random.chance(0.8) { events.append(.key(.canvas(random.pick(keys)), shift: false, command: false)) }
        let strokes = random.int(1...3)
        for _ in 0..<strokes {
            let right = random.chance(0.2)
            // A drag with no press first: the press went to another window.
            if random.chance(0.05) { events.append(.drag(point(), right: right, shift: false, pressure: nil)) }
            events.append(.down(point(), right: right, shift: random.chance(0.15), option: random.chance(0.15),
                                clicks: random.chance(0.1) ? 2 : 1, pressure: right ? nil : pressure()))
            for _ in 0..<random.int(0...6) {
                if random.chance(0.12) { events.append(odd()) }
                events.append(.drag(point(), right: right, shift: random.chance(0.15), pressure: right ? nil : pressure()))
            }
            if random.chance(0.12) { events.append(odd()) }
            // A lost release: the next press comes with this one still down.
            if !random.chance(0.08) { events.append(.up(point(), right: right)) }
        }
        if random.chance(0.15) { events.append(.up(point(), right: random.chance(0.5))) }
        if random.chance(0.3) { events.append(.typing(random.pick(["Hi", "API key", "a@b.io", ""]))) }
        if random.chance(0.3) { events.append(odd()) }
        return events
    }
}
