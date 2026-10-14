import AppKit

/// Help › Export Diagnostic Report…: zips the log files, recent ToonRepeater crash reports and a short system
/// summary so users can send them for debugging. Contains no launcher usernames or other personal data.
enum DiagnosticReport {
    static func export(brain: MultiBrain) {
        let panel = NSSavePanel()
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = "ToonRepeater-diagnostics-\(stamp).zip"
        panel.allowedFileTypes = ["zip"]
        panel.message = "The report contains ToonRepeater's logs, crash reports and system details, but no account names."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        do {
            try write(to: destination, summary: summary(brain: brain))
            Log.app.notice("exported diagnostic report")
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            Log.app.error("diagnostic export failed: \(error.localizedDescription)")
            UpdateManager.alert("Couldn't save the diagnostic report", error.localizedDescription, buttons: ["Close"])
        }
    }

    static func showLogFolder() {
        NSWorkspace.shared.open(LogFile.shared.directory)
    }

    private static func write(to destination: URL, summary: String) throws {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent("ToonRepeater-diagnostics-\(UUID().uuidString)")
            .appendingPathComponent("ToonRepeater diagnostics")
        defer { try? fm.removeItem(at: folder.deletingLastPathComponent()) }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        try summary.write(to: folder.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)

        LogFile.shared.flush()
        for file in LogFile.shared.files {
            try fm.copyItem(at: file, to: folder.appendingPathComponent(file.lastPathComponent))
        }

        // macOS writes crash reports here; include ToonRepeater's from the last 30 days.
        let reports = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/DiagnosticReports")
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        let crashes = ((try? fm.contentsOfDirectory(at: reports, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("ToonRepeater") }
            .filter { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast) > cutoff }
        if !crashes.isEmpty {
            let crashFolder = folder.appendingPathComponent("crash reports")
            try fm.createDirectory(at: crashFolder, withIntermediateDirectories: true)
            for crash in crashes { try fm.copyItem(at: crash, to: crashFolder.appendingPathComponent(crash.lastPathComponent)) }
        }

        try? fm.removeItem(at: destination)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--keepParent", folder.path, destination.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else {
            throw NSError(domain: "ToonRepeater", code: Int(ditto.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "Creating the zip file failed."])
        }
    }

    /// App, system and controller state. Deliberately excludes launcher usernames.
    static func summary(brain: MultiBrain) -> String {
        let info = ProcessInfo.processInfo
        var arch = "unknown"
        #if arch(arm64)
        arch = "arm64"
        #elseif arch(x86_64)
        arch = "x86_64"
        #endif
        let linked = brain.windowsPID.flatMap { $0 }.compactMap { $0 }.count
        return """
            ToonRepeater \(Settings.appVersion)
            Generated: \(Date())
            macOS: \(info.operatingSystemVersionString)
            Architecture: \(arch)\(info.isTranslated ? " (Rosetta)" : "")
            Accessibility permission: \(AXIsProcessTrusted() ? "granted" : "NOT granted")
            Game processes running: \(LauncherAutomation.enginePIDs.count)
            Linked game windows: \(linked)
            Launcher installed: \(LauncherAutomation.launcherURL != nil)
            Mode: \(brain.mode), throw mode: \(brain.throwMode), group: \(brain.group + 1)
            Keep alive: \(Settings.keepAlive), keep on top: \(Settings.keepOnTop), auto update: \(Settings.autoUpdate)
            Click Repeater method: \(Settings.repeaterMethod.rawValue), pause: \(Settings.repeaterDelay)s
            Analytics: \(Analytics.isAvailable ? (Analytics.consent.map { $0 ? "on" : "off" } ?? "not asked") : "not configured")
            Keybinds: \(Settings.keyMaps.sorted { $0.key < $1.key }.map { "\($0.key)=\(KeyCodes.string(of: UInt16($0.value)))" }.joined(separator: ", "))
            """
    }
}

private extension ProcessInfo {
    /// True when running under Rosetta.
    var isTranslated: Bool {
        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0) == 0 && translated == 1
    }
}
