import AppKit
import TelemetryDeck

/// Opt-in, anonymous usage statistics via TelemetryDeck.
///
/// Sent only after the user agrees (asked once on first launch; changeable in Preferences):
/// - `App.installed`: once per install.
/// - `App.sessionEnded`: minutes the app ran, peak number of linked game windows, Quickstart runs and
///   Click Repeater uses during that session.
/// - TelemetryDeck's own session start signal, with app version, macOS version and Mac model type.
///
/// Every signal carries a random install ID, created on first launch and hashed by TelemetryDeck before it
/// leaves the Mac. Nothing else is sent: no launcher usernames, file paths, process IDs or hardware serials.
/// Analytics stays off entirely when the build has no TelemetryDeck app ID (`TELEMETRYDECK_APP_ID` in build.sh).
enum Analytics {
    private static let defaults = UserDefaults.standard
    private static var started = false

    // Session counters
    private static let launchedAt = Date()
    private static var peakLinkedWindows = 0
    private static var quickstartRuns = 0
    private static var repeaterUses = 0

    static var appID: String? {
        let id = (Bundle.main.object(forInfoDictionaryKey: "TelemetryDeckAppID") as? String)?
            .trimmingCharacters(in: .whitespaces)
        return (id?.isEmpty ?? true) ? nil : id
    }

    static var isAvailable: Bool { appID != nil }

    /// nil until the user has answered the consent prompt.
    static var consent: Bool? {
        get { defaults.object(forKey: "analyticsConsent") as? Bool }
        set {
            defaults.set(newValue, forKey: "analyticsConsent")
            newValue == true ? start() : stop()
        }
    }

    /// Random per-install identifier; hashed by TelemetryDeck before sending.
    private static var installID: String {
        if let id = defaults.string(forKey: "installID") { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: "installID")
        return id
    }

    // MARK: Lifecycle

    /// Starts analytics at launch if the user has opted in, or asks them the first time.
    static func launch() {
        guard isAvailable else { return }
        if consent == nil { askForConsent() } else if consent == true { start() }
    }

    private static func askForConsent() {
        let alert = NSAlert()
        alert.messageText = "Help improve ToonRepeater?"
        alert.informativeText = """
            ToonRepeater can send anonymous usage statistics: that it was installed, how long it runs, how \
            many game windows it controls, and which features are used. A random ID counts installs; no \
            account names or personal information are ever sent.

            You can change this any time in Preferences › General.
            """
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Don't Allow")
        NSApp.activate(ignoringOtherApps: true)
        consent = alert.runModal() == .alertFirstButtonReturn
        Log.app.notice("analytics consent: \(consent == true)")
    }

    private static func start() {
        guard let appID = appID, !started else { return }
        let config = TelemetryDeck.Config(appID: appID)
        config.defaultUser = installID
        TelemetryDeck.initialize(config: config)
        started = true
        if !defaults.bool(forKey: "installSignalSent") {
            TelemetryDeck.signal("App.installed")
            defaults.set(true, forKey: "installSignalSent")
        }
    }

    private static func stop() {
        guard started else { return }
        TelemetryDeck.terminate()
        started = false
    }

    // MARK: Events

    static func noteLinkedWindows(_ count: Int) { peakLinkedWindows = max(peakLinkedWindows, count) }
    static func noteQuickstartRun() { quickstartRuns += 1 }
    static func noteRepeaterUsed() { repeaterUses += 1 }

    /// Sends the session summary. Called when the app quits; TelemetryDeck caches it if offline.
    static func sessionEnded() {
        guard started else { return }
        let minutes = Date().timeIntervalSince(launchedAt) / 60
        TelemetryDeck.signal("App.sessionEnded", parameters: [
            "peakLinkedWindows": String(peakLinkedWindows),
            "quickstartRuns": String(quickstartRuns),
            "clickRepeaterUses": String(repeaterUses),
        ], floatValue: (minutes * 10).rounded() / 10)
        TelemetryDeck.requestImmediateSync()
    }
}
