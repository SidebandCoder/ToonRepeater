import AppKit

enum Mode { case multi, mirror }
enum ThrowMode { case charge, low }

/// Translates key presses in the controller window into key events posted to the game processes.
///
/// Windows are arranged as two groups of two toons: `windowsPID[group][toon]`, toon 0 = left, 1 = right.
/// Multi mode drives the active group's two toons with separate keybinds; Mirror mode copies every
/// key press to all four windows.
final class MultiBrain {
    /// Process names (or name fragments) accepted as game windows.
    static let gameWhitelist = [
        "ods_darwin", "Toontown Rewritten", "Toontown Offline", "Corporate Clash",
        "tooniversal_darwin", "fellowship", "toon", "Toon",
    ]

    private let keyboardSource = CGEventSource(stateID: .hidSystemState)
    private(set) var windowsPID: [[pid_t?]] = [[nil, nil], [nil, nil]]
    private(set) var mode: Mode = .multi
    private(set) var throwMode: ThrowMode = .charge
    var group = 0

    private var modifierKeysDown: Set<UInt16> = []
    private var keysDown: Set<UInt16> = []
    private var keepAliveTimer: Timer?

    /// Delivers an event to a process; replaceable so tests can observe routing.
    var deliver: (CGEvent, pid_t) -> Void = { event, pid in
        Log.events.debug("post key \(event.getIntegerValueField(.keyboardEventKeycode)) type \(event.type.rawValue) flags \(event.flags.rawValue) -> pid \(pid)")
        event.postToPid(pid)
    }

    // MARK: Modes

    func swapMode() { mode = (mode == .multi) ? .mirror : .multi }
    func swapThrowMode() { throwMode = (throwMode == .charge) ? .low : .charge }

    // MARK: Window assignment

    /// Assigns the frontmost application to a slot if it is a supported game. Returns whether it was assigned.
    @discardableResult
    func setWindowPID(group: Int, toon: Int) -> Bool {
        defer { NSApp.activate(ignoringOtherApps: true) }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let name = app.localizedName else {
            Log.app.notice("assign g\(group) t\(toon): frontmost app is ToonRepeater or unknown")
            return false
        }
        let isGame = Self.gameWhitelist.contains(name)
            || Self.gameWhitelist.contains { name.contains($0) }
        Log.app.notice("assign g\(group) t\(toon): \(name) [\(app.bundleIdentifier ?? "?")] pid \(app.processIdentifier) accepted=\(isGame)")
        guard isGame else { return false }
        windowsPID[group][toon] = app.processIdentifier
        return true
    }

    func clearWindowPID(group: Int, toon: Int) { windowsPID[group][toon] = nil }

    func assignWindowPID(_ pid: pid_t, group: Int, toon: Int) { windowsPID[group][toon] = pid }

    // MARK: Event handling

    /// Multi mode: each toon in the active group responds to its own keybinds.
    func handleMultiMode(_ event: NSEvent) {
        let keyCode = event.keyCode

        // Escape goes to both toons of the group (closes menus/dialogs in game).
        if keyCode == KeyCodes.escape, let cg = event.cgEvent {
            for toon in 0..<2 { post(cg, toon: toon, group: group) }
            return
        }

        guard let isDown = trackKeyState(event) else { return }

        for toon in 0..<2 {
            guard let action = Settings.action(toon: toon, keyCode: keyCode),
                  let pid = windowsPID[group][toon],
                  let ev = CGEvent(keyboardEventSource: keyboardSource, virtualKey: action.gameKey, keyDown: isDown)
            else { continue }

            // While this toon's jump key is held, ToonTown needs the control flag on its other keys.
            let jumpKey = Settings.key(toon: toon, action: .jump)
            let jumping = modifierKeysDown.contains(jumpKey) || keysDown.contains(jumpKey)
            ev.flags = jumping ? .maskControl : []

            if action == .throwpie && throwMode == .low {
                if isDown { tapThrow(to: [pid]) }
            } else {
                deliver(ev, pid)
            }
        }
    }

    /// Mirror mode: every key goes to all four windows, with the mirror-throw key mapped to throw.
    func handleMirrorMode(_ event: NSEvent) {
        if event.keyCode == Settings.mirrorThrowKey {
            let isDown = (event.type == .keyDown)
            if throwMode == .low {
                if isDown { tapThrow(to: allPIDs) }
            } else if let ev = CGEvent(keyboardEventSource: keyboardSource, virtualKey: KeyCodes.forwardDelete, keyDown: isDown) {
                postToAll(ev)
            }
            return
        }
        if let cg = event.cgEvent { postToAll(cg) }
    }

    /// Updates held-key bookkeeping; returns whether the key is now down, or nil for other event types.
    private func trackKeyState(_ event: NSEvent) -> Bool? {
        let keyCode = event.keyCode
        switch event.type {
        case .keyDown:
            keysDown.insert(keyCode)
            return true
        case .keyUp:
            keysDown.remove(keyCode)
            return false
        case .flagsChanged:
            let pressed = KeyCodes.isPressed(keyCode, flags: event.modifierFlags)
            if pressed { modifierKeysDown.insert(keyCode) } else { modifierKeysDown.remove(keyCode) }
            return pressed
        default:
            return nil
        }
    }

    /// Forgets held keys and lifts them in game, so no toon keeps running after focus leaves the controller.
    func releaseKeys() {
        let held = keysDown.union(modifierKeysDown)
        keysDown.removeAll()
        modifierKeysDown.removeAll()
        guard mode == .multi else { return }
        for keyCode in held {
            for toon in 0..<2 {
                guard let action = Settings.action(toon: toon, keyCode: keyCode),
                      let pid = windowsPID[group][toon],
                      let up = CGEvent(keyboardEventSource: keyboardSource, virtualKey: action.gameKey, keyDown: false)
                else { continue }
                up.flags = []
                deliver(up, pid)
            }
        }
    }

    // MARK: Posting

    private var allPIDs: [pid_t] { windowsPID.flatMap { $0 }.compactMap { $0 } }

    private func post(_ event: CGEvent, toon: Int, group: Int) {
        if let pid = windowsPID[group][toon] { deliver(event, pid) }
    }

    private func postToAll(_ event: CGEvent) {
        allPIDs.forEach { deliver(event, $0) }
    }

    /// A quick press-and-release of the throw key: a low (uncharged) throw.
    private func tapThrow(to pids: [pid_t]) {
        for isDown in [true, false] {
            guard let ev = CGEvent(keyboardEventSource: keyboardSource, virtualKey: KeyCodes.forwardDelete, keyDown: isDown) else { continue }
            ev.flags = []
            pids.forEach { deliver(ev, $0) }
        }
    }

    // MARK: Keep alive

    /// Taps Home in every window once a minute so the game doesn't log idle toons out.
    func setKeepAlive(_ on: Bool) {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
        guard on else { return }
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.sendKeepAlive()
        }
    }

    private func sendKeepAlive() {
        for isDown in [true, false] {
            if let ev = CGEvent(keyboardEventSource: keyboardSource, virtualKey: KeyCodes.home, keyDown: isDown) {
                postToAll(ev)
            }
        }
    }
}
