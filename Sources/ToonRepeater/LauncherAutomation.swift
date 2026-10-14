import AppKit

/// Drives the Toontown Rewritten launcher through Accessibility. Credentials stay inside the launcher:
/// ToonRepeater only steps through the accounts the launcher has saved in its username list.
enum LauncherAutomation {
    static let launcherBundleID = "com.toontownrewritten.Toontown-Launcher"
    static let engineBundleID = "com.toontownrewritten.engine"

    enum Failure: LocalizedError {
        case launcherMissing, launcherDidNotOpen, controlsNotFound, noSavedAccounts
        case accountNotFound, gameDidNotStart(String), cancelled

        var errorDescription: String? {
            switch self {
            case .launcherMissing: return "The Toontown Launcher isn't installed."
            case .launcherDidNotOpen: return "The Toontown Launcher didn't open its login window."
            case .controlsNotFound: return "Couldn't find the launcher's username field or GO button."
            case .noSavedAccounts: return "The launcher has no saved accounts. Log in once with Remember Me ticked for each account."
            case .accountNotFound: return "A chosen account is no longer saved in the launcher. Start Quickstart again and click Refresh Accounts."
            case .gameDidNotStart(let status): return "The game didn't start." + (status.isEmpty ? "" : " Launcher says: \(status)")
            case .cancelled: return "Quickstart was cancelled."
            }
        }
    }

    static var launcherURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: launcherBundleID)
    }

    static var runningLauncher: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: launcherBundleID).first
    }

    static var enginePIDs: Set<pid_t> {
        Set(NSRunningApplication.runningApplications(withBundleIdentifier: engineBundleID).map(\.processIdentifier))
    }

    // MARK: Launcher steps (call off the main thread; they block while waiting)

    struct LoginControls {
        let username: AXElement
        let password: AXElement
        let go: AXElement
        let status: AXElement?
    }

    /// Quits any running launcher, opens a fresh one and waits for its login controls.
    static func openLauncher(isCancelled: () -> Bool) throws -> (NSRunningApplication, LoginControls) {
        try quitLauncher()
        guard let url = launcherURL else { throw Failure.launcherMissing }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)

        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if isCancelled() { throw Failure.cancelled }
            if let app = runningLauncher, let controls = loginControls(pid: app.processIdentifier) {
                return (app, controls)
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        throw runningLauncher == nil ? Failure.launcherDidNotOpen : Failure.controlsNotFound
    }

    static func loginControls(pid: pid_t) -> LoginControls? {
        let app = AXElement.application(pid: pid)
        guard let window = app.windows.first(where: { $0.first { $0.role == kAXComboBoxRole } != nil }),
              let username = window.first(where: { $0.role == kAXComboBoxRole }),
              let password = window.first(where: { $0.subrole == kAXSecureTextFieldSubrole }),
              // GO is the large square button beside the login fields.
              let go = window.all(where: { $0.role == kAXButtonRole })
                  .filter({ ($0.frame?.width ?? 0) >= 80 && ($0.frame?.height ?? 0) >= 80 })
                  .max(by: { ($0.frame?.width ?? 0) < ($1.frame?.width ?? 0) })
        else { return nil }
        let status = window.first { $0.identifier == "_NS:247" && $0.role == kAXStaticTextRole }
        return LoginControls(username: username, password: password, go: go, status: status)
    }

    /// Runs `block` on the main thread, whether or not we're already on it.
    private static func onMain(_ block: () -> Void) {
        if Thread.isMainThread { block() } else { DispatchQueue.main.sync(execute: block) }
    }

    /// Focuses and clears the username box.
    private static func resetUsername(in app: NSRunningApplication, controls: LoginControls) {
        onMain { _ = app.activate(options: []) }
        Thread.sleep(forTimeInterval: 0.4)
        controls.username.set(kAXFocusedAttribute, kCFBooleanTrue)
        controls.username.set(kAXValueAttribute, "" as CFString)
        Thread.sleep(forTimeInterval: 0.2)
    }

    /// Presses ↓ the way a real keyboard does: arrow keys carry the function and keypad flags and the
    /// arrow's special character, which Cocoa needs to treat the press as "move down".
    private static func arrowDown(pause: TimeInterval = 0.35) {
        let source = CGEventSource(stateID: .hidSystemState)
        var arrow: UniChar = 0xF701 // NSDownArrowFunctionKey
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 125, keyDown: down) else { continue }
            event.flags = [.maskSecondaryFn, .maskNumericPad]
            event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &arrow)
            event.post(tap: .cghidEventTap)
        }
        Thread.sleep(forTimeInterval: pause)
    }

    /// Height of one row in the launcher's account list, and the list's top/bottom padding.
    private static let rowHeight: CGFloat = 19
    private static let listInset: CGFloat = 3

    /// Opens the username list and returns its on-screen frame (top-left origin), or nil if it didn't open.
    private static func openAccountList(in app: NSRunningApplication, controls: LoginControls) -> CGRect? {
        onMain { _ = app.activate(options: []) }
        if !(controls.username.attribute(kAXExpandedAttribute) as Bool? ?? false) {
            controls.username.first(maxDepth: 2) { $0.role == kAXButtonRole }?.perform(kAXPressAction)
        }
        for _ in 0..<10 {
            Thread.sleep(forTimeInterval: 0.15)
            let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
            for window in windows where (window[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier {
                guard let b = window[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
                let frame = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
                // The list is a small window about as wide as the username box.
                if frame.height < 400, let field = controls.username.frame, abs(frame.width - field.width) < 40,
                   abs(frame.midX - field.midX) < 40 {
                    return frame
                }
            }
        }
        return nil
    }

    private static func rowCount(in list: CGRect) -> Int {
        max(1, Int(((list.height - 2 * listInset) / rowHeight).rounded()))
    }

    /// Clicks row `index` of the open list, as the user would, so the launcher fills in that account.
    private static func clickRow(_ index: Int, in list: CGRect) {
        let point = CGPoint(x: list.midX, y: list.minY + listInset + rowHeight * (CGFloat(index) + 0.5))
        let source = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }
        Thread.sleep(forTimeInterval: 0.5)
    }

    private static let maxSavedAccounts = 30

    /// Chooses the `position`-th (1-based) saved account the way a person does: open the username list,
    /// arrow down to it (the list shows only a couple of rows and scrolls with the highlight), then click it.
    /// Returns the username now in the box.
    private static func chooseAccount(at position: Int, in app: NSRunningApplication, controls: LoginControls,
                                      slow: Bool = false) -> String? {
        resetUsername(in: app, controls: controls)
        guard let list = openAccountList(in: app, controls: controls) else { return nil }
        for _ in 0..<position { arrowDown(pause: slow ? 0.7 : 0.35) }
        if slow { Thread.sleep(forTimeInterval: 0.5) }
        // The highlight sits on the top row after one press, then on the bottom row as the list scrolls.
        clickRow(min(position - 1, rowCount(in: list) - 1), in: list)
        let name = controls.username.stringValue
        return name.isEmpty ? nil : name
    }

    /// Usernames saved in the launcher, in list order. Shown only in the Quickstart picker; never logged.
    static func savedAccounts(in app: NSRunningApplication, controls: LoginControls) -> [String] {
        let names = savedAccountsInOnePass(in: app, controls: controls)
        resetUsername(in: app, controls: controls)
        return names
    }

    /// Reads the list top to bottom in one pass: choose the first account, then repeatedly reopen the list
    /// (which reopens with the chosen account highlighted), press ↓ once and click the newly highlighted row.
    /// Stops when ↓ no longer moves to a new account (the end of the list), confirming with a slower retry
    /// in case a keypress lagged.
    private static func savedAccountsInOnePass(in app: NSRunningApplication, controls: LoginControls) -> [String] {
        guard let first = chooseAccount(at: 1, in: app, controls: controls)
                ?? chooseAccount(at: 1, in: app, controls: controls, slow: true) else { return [] }
        var names = [first]
        while names.count < maxSavedAccounts {
            var next = stepToNextAccount(from: names.count, in: app, controls: controls)
            if next == nil || names.contains(next!) {
                // The end of the list, or a lagging keypress. Retry once slowly; if the selection has drifted
                // off the last account, re-select it first.
                if next != names.last { _ = chooseAccount(at: names.count, in: app, controls: controls, slow: true) }
                next = stepToNextAccount(from: names.count, in: app, controls: controls, slow: true)
            }
            guard let name = next, !names.contains(name) else { break }
            names.append(name)
        }
        return names
    }

    /// With the account at `position` (1-based) chosen, moves to the next one: reopen the list, ↓, click.
    private static func stepToNextAccount(from position: Int, in app: NSRunningApplication, controls: LoginControls,
                                          slow: Bool = false) -> String? {
        guard let list = openAccountList(in: app, controls: controls) else { return nil }
        if slow { Thread.sleep(forTimeInterval: 0.4) }
        arrowDown(pause: slow ? 0.7 : 0.35)
        // The highlight is on the top row while the list hasn't scrolled, then stays on the bottom row.
        clickRow(min(position, rowCount(in: list) - 1), in: list)
        let name = controls.username.stringValue
        return name.isEmpty ? nil : name
    }

    /// Selects the saved account `username`. Tries `position` (1-based, where it was when the accounts were
    /// read) first, then scans the whole list in case the launcher reordered it.
    static func selectAccount(_ username: String, position: Int, in app: NSRunningApplication, controls: LoginControls) throws {
        if chooseAccount(at: position, in: app, controls: controls) != username,
           chooseAccount(at: position, in: app, controls: controls, slow: true) != username {
            var previous: String?
            var found = false
            for candidate in 1...maxSavedAccounts {
                let name = chooseAccount(at: candidate, in: app, controls: controls)
                if name == username { found = true; break }
                if name == nil || name == previous { break } // end of the list
                previous = name
            }
            guard found else { throw Failure.accountNotFound }
        }
        Thread.sleep(forTimeInterval: 0.3) // let the launcher fill in the saved password
    }

    /// Presses GO and waits for a new game process. Returns its pid.
    static func pressGo(_ controls: LoginControls, existingEngines: Set<pid_t>, isCancelled: () -> Bool) throws -> pid_t {
        controls.go.perform(kAXPressAction)
        // Allow time for patching, the login queue or a two-factor prompt.
        let deadline = Date().addingTimeInterval(300)
        while Date() < deadline {
            if isCancelled() { throw Failure.cancelled }
            if let pid = enginePIDs.subtracting(existingEngines).first { return pid }
            Thread.sleep(forTimeInterval: 1)
        }
        throw Failure.gameDidNotStart(controls.status?.stringValue ?? "")
    }

    /// Waits until a game process has opened a window, so quitting the launcher can't interrupt startup.
    static func waitForGameWindow(pid: pid_t, timeout: TimeInterval = 60) {
        let deadline = Date().addingTimeInterval(timeout)
        let app = AXElement.application(pid: pid)
        while Date() < deadline, app.windows.isEmpty { Thread.sleep(forTimeInterval: 0.5) }
    }

    static func quitLauncher() throws {
        guard let app = runningLauncher else { return }
        app.terminate()
        let deadline = Date().addingTimeInterval(10)
        while !app.isTerminated && Date() < deadline { Thread.sleep(forTimeInterval: 0.25) }
        if !app.isTerminated { app.forceTerminate() }
        Thread.sleep(forTimeInterval: 0.5)
    }

    // MARK: Window layout

    /// Arranges game windows in a 2×2 grid on the screen containing the controller.
    static func arrange(pids: [pid_t?], on screen: NSScreen) {
        guard let primary = NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let size = CGSize(width: visible.width / 2, height: visible.height / 2)
        for (slot, pid) in pids.enumerated() {
            guard let pid = pid, let window = AXElement.application(pid: pid).windows.first else { continue }
            // AX uses top-left origin coordinates measured from the primary screen's top edge.
            let column = CGFloat(slot % 2), row = CGFloat(slot / 2)
            var origin = CGPoint(x: visible.minX + column * size.width,
                                 y: primary.frame.maxY - visible.maxY + row * size.height)
            var windowSize = size
            if let position = AXValueCreate(.cgPoint, &origin) { window.set(kAXPositionAttribute, position) }
            if let sizeValue = AXValueCreate(.cgSize, &windowSize) { window.set(kAXSizeAttribute, sizeValue) }
        }
    }

    // MARK: Diagnostics

    /// `open -n ToonRepeater.app --args --dump-launcher <file>` writes the launcher's UI structure
    /// (roles, labels, positions; no field contents) and quits.
    static func dumpIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--dump-launcher"), i + 1 < args.count else { return false }
        let url = URL(fileURLWithPath: args[i + 1])
        var text = "trusted=\(AXIsProcessTrusted())\n"
        if let app = runningLauncher {
            text += "launcher pid=\(app.processIdentifier)\n" + AXElement.application(pid: app.processIdentifier).outline()
        } else {
            text += "launcher not running\n"
        }
        // `--test-select`: read the saved accounts and select the last one, without pressing GO.
        // Reports counts and outcomes only, never usernames.
        if args.contains("--test-select"), let app = runningLauncher {
            if let controls = loginControls(pid: app.processIdentifier) {
                let names = savedAccounts(in: app, controls: controls)
                text += "saved accounts: \(names.count), distinct: \(Set(names).count)\n"
                if let last = names.last {
                    do {
                        try selectAccount(last, position: names.count, in: app, controls: controls)
                        text += "select last account: ok\n"
                    } catch {
                        text += "select last account: \(error.localizedDescription)\n"
                    }
                }
            } else {
                text += "controls not found\n"
            }
        }
        try? text.write(to: url, atomically: true, encoding: .utf8)
        return true
    }
}
