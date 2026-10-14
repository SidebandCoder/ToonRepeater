import AppKit

/// Clone battle mode: a left click in one linked game window is repeated at the same spot in every other
/// linked game window, so all toons pick the same gag (or target, or button).
final class ClickRepeater {
    enum Method: String, CaseIterable {
        /// Bring each window forward, click it, then return focus. Visibly switches windows.
        case foreground
        /// Post the click straight to each window's process. Toontown ignores clicks on inactive windows,
        /// so this doesn't work for it; kept for other games that accept first-click events.
        case background

        var title: String {
            switch self {
            case .foreground: return "Bring each window forward"
            case .background: return "Background clicks (doesn't work with Toontown)"
            }
        }
    }

    /// Tags events we post so the click monitor ignores them.
    private static let marker: Int64 = 0x4D43_4C4E // "MCLN"

    private let brain: MultiBrain
    private var monitor: Any?
    private var pendingTargets: [(pid: pid_t, point: CGPoint, windowID: CGWindowID)] = []
    private var source: (pid: pid_t, point: CGPoint, missed: Bool)?
    private let queue = DispatchQueue(label: "clone-clicks")
    private var activationObserver: Any?
    /// Most recent app activation that ToonRepeater didn't cause itself.
    private var lastActivation: (pid: pid_t, time: Date)?
    private var frontmostPID: pid_t?
    private let eventSource = CGEventSource(stateID: .hidSystemState)

    private(set) var isEnabled = false

    init(brain: MultiBrain) { self.brain = brain }

    func setEnabled(_ on: Bool) {
        guard on != isEnabled else { return }
        isEnabled = on
        if on {
            frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let self = self,
                      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self.frontmostPID = app.processIdentifier
                if !self.busy { self.lastActivation = (app.processIdentifier, Date()) }
            }
            monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
                self?.handle(event)
            }
        } else {
            if let monitor = monitor { NSEvent.removeMonitor(monitor) }
            if let observer = activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
            monitor = nil
            activationObserver = nil
        }
        Log.app.notice("clone clicks \(on ? "on" : "off")")
    }

    // MARK: Handling

    private func handle(_ event: NSEvent) {
        if event.cgEvent?.getIntegerValueField(.eventSourceUserData) == Self.marker { return }
        let point = Self.cgPoint(fromCocoa: NSEvent.mouseLocation)

        if busy { return }
        if event.type == .leftMouseDown {
            pendingTargets = []
            source = nil
            let linked = Set(brain.windowsPID.flatMap { $0 }.compactMap { $0 })
            let windows = Self.gameWindows(pids: linked)
            // The clicked window is the frontmost window under the cursor, and it must be a linked game.
            let clicked = Self.topWindow(at: point)
            Log.app.notice("clone: mouse down at \(Int(point.x)),\(Int(point.y)) top pid \(clicked?.pid ?? -1) linked=\(clicked.map { linked.contains($0.pid) } ?? false) gameWindows=\(windows.count)")
            guard let clicked = clicked, linked.contains(clicked.pid),
                  let from = windows.first(where: { $0.id == clicked.id }) else { return }
            let relative = Self.relativePosition(of: point, in: from.bounds)
            source = (from.pid, point, clickWasSwallowed(by: from.pid))
            pendingTargets = windows.filter { $0.pid != from.pid }.map {
                ($0.pid, Self.absolutePosition(of: relative, in: $0.bounds), $0.id)
            }
            Log.app.notice("clone click from pid \(from.pid) missed=\(self.source?.missed ?? false) rel \(relative.x),\(relative.y) to \(self.pendingTargets.count) windows")
            if Settings.repeaterMethod == .background { postBackground(down: true) }
        } else if event.type == .leftMouseUp, !pendingTargets.isEmpty {
            switch Settings.repeaterMethod {
            case .background: postBackground(down: false)
            case .foreground: clickForeground()
            }
            pendingTargets = []
        }
    }

    /// Whether the click on `pid`'s window only brought it to the front. macOS doesn't pass an activating
    /// click on to Toontown, so that click needs repeating too. A click on a window that was already in front
    /// did register, and isn't repeated (it could toggle something, like the Shticker Book, back off).
    private func clickWasSwallowed(by pid: pid_t) -> Bool {
        if frontmostPID != pid { return true } // the activation notification hasn't arrived yet
        guard let last = lastActivation, last.pid == pid else { return false }
        return Date().timeIntervalSince(last.time) < 0.5
    }

    private func postBackground(down: Bool) {
        for target in pendingTargets {
            guard let event = CGEvent(mouseEventSource: eventSource, mouseType: down ? .leftMouseDown : .leftMouseUp,
                                      mouseCursorPosition: target.point, mouseButton: .left) else { continue }
            event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(target.windowID))
            event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(target.windowID))
            event.postToPid(target.pid)
            Log.app.notice("clone: posted \(down ? "down" : "up") to pid \(target.pid) window \(target.windowID) at \(Int(target.point.x)),\(Int(target.point.y))")
        }
    }

    /// True while a bring-forward clone cycle is running; clicks made meanwhile aren't cloned.
    private var busy = false

    /// Clicks each other window in turn by bringing it forward, then returns to the window the user clicked,
    /// repeating the click there too if the user's own click only brought that window forward.
    private func clickForeground() {
        let targets = pendingTargets
        guard let source = source, !busy else { return }
        busy = true
        let step = Settings.repeaterDelay
        queue.async {
            for target in targets {
                guard Self.bringForward(target.pid, settle: step) else {
                    Log.app.notice("clone: pid \(target.pid) didn't come forward; skipped")
                    continue
                }
                self.press(at: target.point, step: step)
                Log.app.notice("clone: clicked pid \(target.pid) at \(Int(target.point.x)),\(Int(target.point.y)) step \(step)s")
            }
            if source.missed, Self.bringForward(source.pid, settle: step) {
                self.press(at: source.point, step: step)
                Log.app.notice("clone: repeated the missed click on the original window, pid \(source.pid)")
            } else {
                _ = Self.bringForward(source.pid, settle: 0.05)
            }
            CGWarpMouseCursorPosition(source.point)
            // Let our own activation of the original window land before watching for user activations again.
            Thread.sleep(forTimeInterval: 0.1)
            DispatchQueue.main.async { self.busy = false }
        }
    }

    /// Clicks at `point` in the frontmost window. The game needs a moment to notice the cursor over the
    /// button (Toontown's buttons react to hover) and to see the press.
    private func press(at point: CGPoint, step: TimeInterval) {
        CGWarpMouseCursorPosition(point)
        let move = CGEvent(mouseEventSource: eventSource, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
        move?.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        move?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: step * 0.6)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            let event = CGEvent(mouseEventSource: eventSource, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
            event?.setIntegerValueField(.eventSourceUserData, value: Self.marker)
            event?.setIntegerValueField(.mouseEventClickState, value: 1)
            event?.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: step * 0.5)
        }
    }

    /// Activates an app, waits (up to 1 s) until it is frontmost, then lets it settle for `settle` seconds.
    private static func bringForward(_ pid: pid_t, settle: TimeInterval) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        // Accessibility can raise another app even while ToonRepeater is in the background.
        let element = AXElement.application(pid: pid)
        element.set(kAXFrontmostAttribute, kCFBooleanTrue)
        element.windows.first?.perform(kAXRaiseAction)
        DispatchQueue.main.sync { _ = app.activate(options: []) }
        for _ in 0..<50 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
                Thread.sleep(forTimeInterval: settle) // let the game treat its window as active
                return true
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return false
    }

    // MARK: Geometry

    struct GameWindow {
        let id: CGWindowID
        let pid: pid_t
        let bounds: CGRect // screen coordinates, top-left origin, including the title bar
    }

    static func gameWindows(pids: Set<pid_t>) -> [GameWindow] {
        let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        var result: [GameWindow] = []
        for info in list {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid),
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let b = info[kCGWindowBounds as String] as? [String: CGFloat],
                  !result.contains(where: { $0.pid == pid }) else { continue }
            result.append(GameWindow(id: id, pid: pid,
                                     bounds: CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)))
        }
        return result
    }

    /// Frontmost normal window containing `point`.
    static func topWindow(at point: CGPoint) -> (id: CGWindowID, pid: pid_t)? {
        let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        for info in list where (info[kCGWindowLayer as String] as? Int) == 0 {
            guard let b = info[kCGWindowBounds as String] as? [String: CGFloat],
                  CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0).contains(point),
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t else { continue }
            return (id, pid)
        }
        return nil
    }

    /// Standard title bar height; game UI is laid out in the content area below it.
    static let titleBarHeight: CGFloat = {
        let content = NSRect(x: 0, y: 0, width: 100, height: 100)
        return NSWindow.frameRect(forContentRect: content, styleMask: [.titled]).height - content.height
    }()

    static func contentRect(of bounds: CGRect) -> CGRect {
        CGRect(x: bounds.minX, y: bounds.minY + titleBarHeight, width: bounds.width, height: max(1, bounds.height - titleBarHeight))
    }

    /// Position within a window's content area as fractions (0…1) of its width and height.
    static func relativePosition(of point: CGPoint, in bounds: CGRect) -> CGPoint {
        let content = contentRect(of: bounds)
        return CGPoint(x: (point.x - content.minX) / content.width, y: (point.y - content.minY) / content.height)
    }

    static func absolutePosition(of relative: CGPoint, in bounds: CGRect) -> CGPoint {
        let content = contentRect(of: bounds)
        return CGPoint(x: content.minX + relative.x * content.width, y: content.minY + relative.y * content.height)
    }

    /// Converts a Cocoa screen point (bottom-left origin) to Quartz coordinates (top-left origin).
    static func cgPoint(fromCocoa point: NSPoint) -> CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: point.x, y: primaryHeight - point.y)
    }
}
