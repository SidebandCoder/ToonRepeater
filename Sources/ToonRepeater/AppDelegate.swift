import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var controllerWindow: NSWindow!
    private var controller: ControllerViewController!
    private var preferences: PreferencesWindowController?
    private var quickstart: Quickstart!
    private var clickRepeater: ClickRepeater!
    private var quickstartPrompt: QuickstartPrompt!

    func applicationDidFinishLaunching(_ notification: Notification) {
        if LauncherAutomation.dumpIfRequested() || Updater.testInstallIfRequested() {
            NSApp.terminate(nil)
            return
        }
        NSApp.mainMenu = buildMenu()

        controller = ControllerViewController()
        quickstart = Quickstart(brain: controller.brain) { [weak self] in self?.controller.refreshImages() }
        clickRepeater = ClickRepeater(brain: controller.brain)
        controller.onToggleRepeater = { [weak self] in self?.toggleClickRepeater(nil) }
        controllerWindow = NSWindow(contentViewController: controller)
        controllerWindow.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        controllerWindow.titlebarAppearsTransparent = true
        controllerWindow.title = ""
        controllerWindow.setFrameAutosaveName("ControllerWindow") // restores position only…
        controllerWindow.setContentSize(ControllerViewController.contentSize) // …size is fixed
        controllerWindow.makeKeyAndOrderFront(nil)
        quickstartPrompt = QuickstartPrompt { [weak self] in self?.quickstart.start() }
        NSApp.activate(ignoringOtherApps: true)

        #if DEBUG
        if let dir = DebugSnapshot.directory {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.quickstartPrompt.show(below: self.controllerWindow)
                DebugSnapshot.run(controller: self.controller, preferences: PreferencesWindowController(), into: dir,
                                  extra: self.controllerWindow.childWindows ?? [])
                NSApp.terminate(nil)
            }
            return
        }
        #endif

        Log.app.notice("ToonRepeater \(Settings.appVersion) launched on macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")

        quickstartPrompt.show(below: controllerWindow)

        DispatchQueue.main.async {
            self.checkAccessibility()
            Analytics.launch()
            self.welcomeIfFirstOpen()
            if Settings.autoUpdate { UpdateManager.checkForUpdate(userInitiated: false) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Before TelemetryDeck saves its queue on willTerminate, so the summary is kept if offline.
        Analytics.sessionEnded()
        Log.app.notice("quitting")
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.brain.releaseKeys()
    }

    // MARK: Launch checks

    /// Posting key events to other processes needs the Accessibility permission.
    private func checkAccessibility() {
        // Prompting also adds the app to the Accessibility list, so the user only has to switch it on.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        Log.app.notice("Accessibility trusted: \(trusted)")
        guard !trusted else { return }
        Log.app.error("Accessibility permission not granted")
        let response = UpdateManager.alert(
            "ToonRepeater does not have Accessibility permission",
            "ToonRepeater sends key events to your ToonTown processes. To allow this, enable ToonRepeater under System Settings › Privacy & Security › Accessibility, then relaunch.",
            buttons: ["Open Accessibility Settings", "Not Now"])
        if response == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func welcomeIfFirstOpen() {
        guard Settings.wasJustUpdated(), let changelog = UpdateManager.changelogURL else { return }
        if UpdateManager.alert("Welcome to ToonRepeater \(Settings.appVersion)",
                               "Would you like to view the latest changelog?",
                               buttons: ["Yes", "Not Now"]) == .alertFirstButtonReturn {
            NSWorkspace.shared.open(changelog)
        }
    }

    // MARK: Actions

    @objc func openPreferences(_ sender: Any?) {
        if preferences == nil { preferences = PreferencesWindowController() }
        preferences?.showWindow(nil)
        preferences?.window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func checkUpdates(_ sender: Any?) { UpdateManager.checkForUpdate(userInitiated: true) }

    @objc func openChangelog(_ sender: Any?) {
        if let url = UpdateManager.changelogURL {
            NSWorkspace.shared.open(url)
        } else {
            UpdateManager.alert("No changelog configured", "Set MCUpdateRepository in build.sh to your GitHub repository.", buttons: ["Close"])
        }
    }

    @objc func relaunch(_ sender: Any?) { Self.relaunch() }

    @objc func exportDiagnostics(_ sender: Any?) { DiagnosticReport.export(brain: controller.brain) }
    @objc func showLogFolder(_ sender: Any?) { DiagnosticReport.showLogFolder() }
    @objc func openProjectPage(_ sender: Any?) {
        if let repo = UpdateManager.repository, let url = URL(string: "https://github.com/\(repo)") { NSWorkspace.shared.open(url) }
    }

    @objc func toggleListeners(_ sender: Any?) { controller.toggleListeners(sender) }
    @objc func toggleMode(_ sender: Any?) { controller.toggleMode(sender) }
    @objc func startQuickstart(_ sender: Any?) {
        quickstartPrompt.close()
        quickstart.start()
    }

    @objc func showQuickstartPrompt(_ sender: Any?) { quickstartPrompt.show(below: controllerWindow) }
    @objc func arrangeWindows(_ sender: Any?) { quickstart.arrangeWindows() }

    @objc func linkOpenWindows(_ sender: Any?) {
        if quickstart.linkOpenWindows() == 0 {
            UpdateManager.alert("No game windows are open", "Start Toontown first, or use Quickstart.", buttons: ["Close"])
        }
    }

    @objc func toggleClickRepeater(_ sender: Any?) {
        clickRepeater.setEnabled(!clickRepeater.isEnabled)
        if clickRepeater.isEnabled { Analytics.noteRepeaterUsed() }
        controller.repeaterOn = clickRepeater.isEnabled
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(toggleClickRepeater(_:)) { item.state = clickRepeater.isEnabled ? .on : .off }
        return true
    }

    static func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; open \"\(Bundle.main.bundlePath)\""]
        try? task.run()
        NSApp.terminate(nil)
    }

    // MARK: Menu

    private func buildMenu() -> NSMenu {
        let main = NSMenu()

        let app = NSMenu(title: "ToonRepeater")
        app.addItem(withTitle: "About ToonRepeater", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Preferences…", action: #selector(openPreferences(_:)), keyEquivalent: ",")
        app.addItem(withTitle: "Check for Updates", action: #selector(checkUpdates(_:)), keyEquivalent: "")
        app.addItem(withTitle: "View Changelog", action: #selector(openChangelog(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Relaunch", action: #selector(relaunch(_:)), keyEquivalent: "r")
        app.addItem(withTitle: "Quit ToonRepeater", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu: app, title: "ToonRepeater")

        let controllerMenu = NSMenu(title: "Controller")
        controllerMenu.addItem(withTitle: "Toggle Controller", action: #selector(toggleListeners(_:)), keyEquivalent: "`")
        let mode = controllerMenu.addItem(withTitle: "Toggle Mode", action: #selector(toggleMode(_:)), keyEquivalent: "`")
        mode.keyEquivalentModifierMask = []
        controllerMenu.addItem(.separator())
        controllerMenu.addItem(withTitle: "Quickstart 4 Toons", action: #selector(startQuickstart(_:)), keyEquivalent: "k")
        controllerMenu.addItem(withTitle: "Show Quickstart Button", action: #selector(showQuickstartPrompt(_:)), keyEquivalent: "")
        controllerMenu.addItem(withTitle: "Link Open Game Windows", action: #selector(linkOpenWindows(_:)), keyEquivalent: "l")
        controllerMenu.addItem(withTitle: "Arrange Game Windows", action: #selector(arrangeWindows(_:)), keyEquivalent: "g")
        controllerMenu.addItem(.separator())
        controllerMenu.addItem(withTitle: "Click Repeater", action: #selector(toggleClickRepeater(_:)), keyEquivalent: "")
        main.addItem(submenu: controllerMenu, title: "Controller")

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(.separator())
        window.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        main.addItem(submenu: window, title: "Window")
        NSApp.windowsMenu = window

        let help = NSMenu(title: "Help")
        help.addItem(withTitle: "Export Diagnostic Report…", action: #selector(exportDiagnostics(_:)), keyEquivalent: "")
        help.addItem(withTitle: "Show Log Folder", action: #selector(showLogFolder(_:)), keyEquivalent: "")
        if UpdateManager.repository != nil {
            help.addItem(.separator())
            help.addItem(withTitle: "ToonRepeater on GitHub", action: #selector(openProjectPage(_:)), keyEquivalent: "")
        }
        main.addItem(submenu: help, title: "Help")
        NSApp.helpMenu = help

        return main
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
