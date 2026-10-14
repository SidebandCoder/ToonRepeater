import AppKit

/// Logs in four saved launcher accounts in turn, links every new game window to a controller slot,
/// then arranges the windows in a 2×2 grid.
final class Quickstart {
    static let slotNames = ["Group 1 – left toon", "Group 1 – right toon", "Group 2 – left toon", "Group 2 – right toon"]

    private let brain: MultiBrain
    private let onChange: () -> Void
    private let panel = ProgressPanel(title: "Quickstart – please don't use the mouse or keyboard")
    private var cancelled = false
    private(set) var isRunning = false

    init(brain: MultiBrain, onChange: @escaping () -> Void) {
        self.brain = brain
        self.onChange = onChange
        panel.onCancel = { [weak self] in self?.cancel() }
    }

    func cancel() {
        cancelled = true
        panel.setStatus("Cancelling…")
    }

    func start() {
        guard !isRunning else { return }
        guard AXIsProcessTrusted() else {
            UpdateManager.alert("Accessibility permission needed", "Quickstart drives the Toontown Launcher, which needs ToonRepeater's Accessibility permission.", buttons: ["Close"])
            return
        }
        isRunning = true
        cancelled = false
        // Use the account list read last time so the picker opens instantly; "Refresh Accounts" re-reads it.
        let remembered = Settings.launcherAccounts
        if remembered.isEmpty { readAccounts() } else { choose(from: remembered) }
    }

    private func readAccounts() {
        panel.show()
        status("Reading saved accounts from the launcher…")
        DispatchQueue.global(qos: .userInitiated).async { self.discoverAccounts() }
    }

    // MARK: Steps

    /// Opens the launcher, reads its saved accounts, then asks which four to use.
    private func discoverAccounts() {
        do {
            let (launcher, controls) = try LauncherAutomation.openLauncher(isCancelled: { [unowned self] in self.cancelled })
            let accounts = LauncherAutomation.savedAccounts(in: launcher, controls: controls)
            guard !accounts.isEmpty else { throw LauncherAutomation.Failure.noSavedAccounts }
            Log.app.notice("quickstart: read \(accounts.count) saved launcher accounts")
            DispatchQueue.main.async {
                Settings.launcherAccounts = accounts
                self.choose(from: accounts)
            }
        } catch {
            finish(error: error, completed: 0)
        }
    }

    private func choose(from accounts: [String]) {
        panel.close()
        let chosen: [String]
        switch QuickstartPicker.choose(from: accounts, previous: Settings.quickstartAccounts) {
        case .start(let accounts): chosen = accounts
        case .refresh: readAccounts(); return
        case .cancel: finish(error: nil, completed: 0); return
        }
        Settings.quickstartAccounts = chosen
        let positions = chosen.map { (accounts.firstIndex(of: $0) ?? 0) + 1 }

        let running = LauncherAutomation.enginePIDs
        if !running.isEmpty {
            let response = UpdateManager.alert(
                "\(running.count) game window\(running.count == 1 ? " is" : "s are") already open",
                "Quickstart opens four new clients. Quit the open games first?",
                buttons: ["Quit Games & Continue", "Cancel"])
            guard response == .alertFirstButtonReturn else {
                finish(error: nil, completed: 0)
                return
            }
            NSRunningApplication.runningApplications(withBundleIdentifier: LauncherAutomation.engineBundleID).forEach { $0.terminate() }
        }

        panel.show()
        DispatchQueue.global(qos: .userInitiated).async { self.logIn(chosen, positions: positions) }
    }

    private func logIn(_ accounts: [String], positions: [Int]) {
        let isCancelled = { [unowned self] in self.cancelled }
        var completed = 0
        do {
            for (slot, account) in accounts.enumerated() {
                let step = "\(Self.slotNames[slot]) (\(slot + 1) of \(accounts.count))"
                status("\(step): opening the launcher…")
                let (launcher, controls) = try LauncherAutomation.openLauncher(isCancelled: isCancelled)

                status("\(step): choosing the account…")
                try LauncherAutomation.selectAccount(account, position: positions[slot], in: launcher, controls: controls)

                status("\(step): logging in…")
                let pid = try LauncherAutomation.pressGo(controls, existingEngines: LauncherAutomation.enginePIDs, isCancelled: isCancelled)

                status("\(step): starting the game…")
                LauncherAutomation.waitForGameWindow(pid: pid)
                DispatchQueue.main.sync {
                    self.brain.assignWindowPID(pid, group: slot / 2, toon: slot % 2)
                    self.onChange()
                }
                completed += 1
                try LauncherAutomation.quitLauncher()
            }
            status("Arranging windows…")
            Thread.sleep(forTimeInterval: 1)
            DispatchQueue.main.async { Analytics.noteQuickstartRun() }
            finish(error: nil, completed: completed)
        } catch {
            finish(error: error, completed: completed)
        }
    }

    private func finish(error: Error?, completed: Int) {
        if let error = error {
            Log.app.error("quickstart stopped after \(completed) clients: \(error.localizedDescription)")
            try? LauncherAutomation.quitLauncher()
        }
        DispatchQueue.main.async {
            if completed > 0 { self.arrangeWindows() }
            self.isRunning = false
            self.panel.close()
            NSApp.activate(ignoringOtherApps: true)
            if let error = error, (error as? LauncherAutomation.Failure).map({ if case .cancelled = $0 { return false } else { return true } }) ?? true {
                UpdateManager.alert(completed > 0 ? "Quickstart stopped after \(completed) of 4 clients" : "Quickstart couldn't start",
                                    error.localizedDescription, buttons: ["Close"])
            }
        }
    }

    /// Links up to four open game windows to the controller slots by screen position: top row → group 1,
    /// bottom row → group 2, left → left toon. Returns how many were linked.
    @discardableResult
    func linkOpenWindows() -> Int {
        let windows = ClickRepeater.gameWindows(pids: LauncherAutomation.enginePIDs)
            .sorted { ($0.bounds.midY, $0.bounds.midX) < ($1.bounds.midY, $1.bounds.midX) }
            .prefix(4)
        // Top two (by height) form group 1; each pair is ordered left to right.
        let rows = [Array(windows.prefix(2)), Array(windows.dropFirst(2))].map { $0.sorted { $0.bounds.midX < $1.bounds.midX } }
        for group in 0..<2 {
            for toon in 0..<2 {
                if toon < rows[group].count {
                    brain.assignWindowPID(rows[group][toon].pid, group: group, toon: toon)
                } else {
                    brain.clearWindowPID(group: group, toon: toon)
                }
            }
        }
        onChange()
        Log.app.notice("linked \(windows.count) open game windows")
        return windows.count
    }

    /// Places the linked game windows in a 2×2 grid, in slot order.
    func arrangeWindows() {
        let screen = NSApp.windows.first(where: { $0.isVisible && $0.contentViewController is ControllerViewController })?.screen
            ?? NSScreen.main ?? NSScreen.screens[0]
        LauncherAutomation.arrange(pids: brain.windowsPID.flatMap { $0 }, on: screen)
    }

    private func status(_ text: String) {
        Log.app.notice("quickstart: \(text)")
        DispatchQueue.main.async { self.panel.setStatus(text) }
    }
}

/// Asks which saved account goes in each of the four controller slots.
enum QuickstartPicker {
    enum Choice {
        case start([String])
        case refresh
        case cancel
    }

    static func choose(from accounts: [String], previous: [String]) -> Choice {
        guard accounts.count >= 4 else {
            let response = UpdateManager.alert(
                "Quickstart needs 4 saved accounts",
                "The launcher has \(accounts.count) saved account\(accounts.count == 1 ? "" : "s"). Log in once with Remember Me ticked for each account you want to use, then refresh.",
                buttons: ["Refresh Accounts", "Close"])
            return response == .alertFirstButtonReturn ? .refresh : .cancel
        }

        // Default to the previous choices where they're still saved, otherwise the first unused accounts.
        var defaults: [String] = []
        for slot in 0..<4 {
            if slot < previous.count, accounts.contains(previous[slot]), !defaults.contains(previous[slot]) {
                defaults.append(previous[slot])
            } else {
                defaults.append(accounts.first { !defaults.contains($0) && !previous.prefix(4).contains($0) }
                                ?? accounts.first { !defaults.contains($0) }!)
            }
        }

        let popups: [NSPopUpButton] = (0..<4).map { slot in
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.addItems(withTitles: accounts)
            popup.selectItem(withTitle: defaults[slot])
            return popup
        }
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 4 * 30))
        for (slot, popup) in popups.enumerated() {
            let y = CGFloat(3 - slot) * 30
            let label = NSTextField(labelWithString: Quickstart.slotNames[slot] + ":")
            label.frame = NSRect(x: 0, y: y + 4, width: 150, height: 17)
            label.alignment = .right
            popup.frame = NSRect(x: 158, y: y, width: 200, height: 26)
            accessory.addSubview(label)
            accessory.addSubview(popup)
        }

        while true {
            let alert = NSAlert()
            alert.messageText = "Quickstart"
            alert.informativeText = "Choose which saved account to log in for each controller slot. Added or removed accounts in the launcher? Click Refresh Accounts."
            alert.accessoryView = accessory
            alert.addButton(withTitle: "Start")
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Refresh Accounts")
            NSApp.activate(ignoringOtherApps: true)
            switch alert.runModal() {
            case .alertFirstButtonReturn: break
            case .alertThirdButtonReturn: return .refresh
            default: return .cancel
            }

            let chosen = popups.map { $0.titleOfSelectedItem ?? "" }
            if Set(chosen).count == 4 { return .start(chosen) }
            UpdateManager.alert("Choose four different accounts", "Each account can only be logged in once.", buttons: ["OK"])
        }
    }
}
