import AppKit

/// Toon actions, in the order the original stores them per toon.
enum Action: String, CaseIterable {
    case left, right, backward, forward, jump, throwpie

    var title: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        case .backward: return "Backward"
        case .forward: return "Forward"
        case .jump: return "Jump"
        case .throwpie: return "Throw"
        }
    }

    /// The key ToonTown itself listens for (its default controls).
    var gameKey: UInt16 {
        switch self {
        case .left: return 123
        case .right: return 124
        case .backward: return 125
        case .forward: return 126
        case .jump: return KeyCodes.leftControl
        case .throwpie: return KeyCodes.forwardDelete
        }
    }
}

/// Persistent settings, stored in UserDefaults under the same key names the original app used.
enum Settings {
    static let defaults = UserDefaults.standard
    static let didChange = Notification.Name("SettingsDidChange")

    // MARK: Keybinds

    static let defaultKeyMaps: [String: Int] = [
        "mirrorthrow": 42, "throwtoggle": 63,                        // \  fn
        "lLeft": 0, "lRight": 2, "lBackward": 1, "lForward": 13,     // A D S W
        "lJump": 56, "lThrow": 42,                                   // L⇧ \
        "rLeft": 123, "rRight": 124, "rBackward": 125, "rForward": 126, // arrows
        "rJump": 60, "rThrow": 42,                                   // R⇧ \
    ]

    /// Settings key for an action of a toon (0 = left, 1 = right).
    static func keyName(toon: Int, action: Action) -> String {
        let suffix: String
        switch action {
        case .left: suffix = "Left"
        case .right: suffix = "Right"
        case .backward: suffix = "Backward"
        case .forward: suffix = "Forward"
        case .jump: suffix = "Jump"
        case .throwpie: suffix = "Throw"
        }
        return (toon == 0 ? "l" : "r") + suffix
    }

    static var keyMaps: [String: Int] {
        get {
            var maps = defaultKeyMaps
            if let stored = defaults.dictionary(forKey: "keyMaps") as? [String: Int] {
                maps.merge(stored) { _, new in new }
            }
            return maps
        }
        set { defaults.set(newValue, forKey: "keyMaps"); notify() }
    }

    static func key(_ name: String) -> UInt16 { UInt16(keyMaps[name] ?? 0) }

    static func setKey(_ name: String, _ code: UInt16) {
        var maps = keyMaps
        maps[name] = Int(code)
        keyMaps = maps
    }

    static func key(toon: Int, action: Action) -> UInt16 { key(keyName(toon: toon, action: action)) }

    /// Which action (if any) a physical key performs for a toon.
    static func action(toon: Int, keyCode: UInt16) -> Action? {
        Action.allCases.first { key(toon: toon, action: $0) == keyCode }
    }

    static var mirrorThrowKey: UInt16 { key("mirrorthrow") }
    static var toggleThrowKey: UInt16 { key("throwtoggle") }

    static func restoreDefaultKeys() { keyMaps = defaultKeyMaps }

    // MARK: Colours

    enum Colour: String, CaseIterable {
        case background, targetOn, targetOff, mode, multi, mirror, charge, low

        var title: String {
            switch self {
            case .background: return "Background"
            case .targetOn: return "Target On"
            case .targetOff: return "Target Off"
            case .mode: return "Mode Indicator"
            case .multi: return "Multi Mode"
            case .mirror: return "Mirror Mode"
            case .charge: return "Charge Throw Mode"
            case .low: return "Low Throw Mode"
            }
        }

        var defaultColour: NSColor {
            switch self {
            case .background: return .white
            case .targetOn: return .systemGreen
            case .targetOff: return .red
            case .mode, .charge, .low: return .darkGray
            case .multi: return .green
            case .mirror: return .purple
            }
        }
    }

    static func colour(_ c: Colour) -> NSColor {
        if let data = defaults.data(forKey: "colour." + c.rawValue),
           let colour = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
            return colour
        }
        return c.defaultColour
    }

    static func setColour(_ c: Colour, _ colour: NSColor) {
        let data = try? NSKeyedArchiver.archivedData(withRootObject: colour, requiringSecureCoding: true)
        defaults.set(data, forKey: "colour." + c.rawValue)
        notify()
    }

    static func restoreDefaultColours() {
        Colour.allCases.forEach { defaults.removeObject(forKey: "colour." + $0.rawValue) }
        notify()
    }

    // MARK: General

    static var keepAlive: Bool {
        get { defaults.bool(forKey: "keepAlive") }
        set { defaults.set(newValue, forKey: "keepAlive"); notify() }
    }

    static var keepOnTop: Bool {
        get { defaults.bool(forKey: "keepOnTop") }
        set { defaults.set(newValue, forKey: "keepOnTop"); notify() }
    }

    static var autoUpdate: Bool {
        get { defaults.object(forKey: "autoUpdate") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "autoUpdate"); notify() }
    }

    enum ArrangeSide: String, CaseIterable {
        case right, left
    }

    /// Share of the screen width (0.3…1) that Arrange Game Windows fills with the 2×2 grid.
    static var arrangeWidthFraction: CGFloat {
        get { CGFloat((defaults.object(forKey: "arrangeWidthFraction") as? Double) ?? 1) }
        set { defaults.set(Double(min(1, max(0.3, newValue))), forKey: "arrangeWidthFraction") }
    }

    /// Which side of the screen the grid sits on when it doesn't fill the whole width.
    static var arrangeSide: ArrangeSide {
        get { defaults.string(forKey: "arrangeSide").flatMap(ArrangeSide.init) ?? .right }
        set { defaults.set(newValue.rawValue, forKey: "arrangeSide") }
    }

    /// How Click Repeater delivers clicks to the other game windows.
    static var repeaterMethod: ClickRepeater.Method {
        get { defaults.string(forKey: "repeaterMethod").flatMap(ClickRepeater.Method.init) ?? .foreground }
        set { defaults.set(newValue.rawValue, forKey: "repeaterMethod"); notify() }
    }

    /// Pause, in seconds, at each stage of a bring-forward clone click (activate, hover, press, release).
    static var repeaterDelay: Double {
        get { (defaults.object(forKey: "repeaterDelay") as? Double) ?? 0.25 }
        set { defaults.set(min(1, max(0.05, newValue)), forKey: "repeaterDelay") }
    }

    /// The launcher's saved usernames, in list order, as last read by Quickstart. Lets the account picker open
    /// instantly; refreshed on request. Only usernames are kept; passwords stay in the launcher.
    static var launcherAccounts: [String] {
        get { defaults.stringArray(forKey: "launcherAccounts") ?? [] }
        set { defaults.set(newValue, forKey: "launcherAccounts") }
    }

    /// Launcher usernames Quickstart last logged in, in slot order (G1 left, G1 right, G2 left, G2 right).
    /// Only usernames are kept; passwords stay in the launcher.
    static var quickstartAccounts: [String] {
        get { defaults.stringArray(forKey: "quickstartAccounts") ?? [] }
        set { defaults.set(newValue, forKey: "quickstartAccounts") }
    }

    /// A release version the user chose to skip; automatic checks don't offer it again.
    static var skippedUpdateVersion: String? {
        get { defaults.string(forKey: "skippedUpdateVersion") }
        set { defaults.set(newValue, forKey: "skippedUpdateVersion") }
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    /// True on the first launch after updating from an earlier version (not on a fresh install);
    /// remembers the current version afterwards.
    static func wasJustUpdated() -> Bool {
        let last = defaults.string(forKey: "lastVersion")
        defaults.set(appVersion, forKey: "lastVersion")
        return last != nil && last != appVersion
    }

    private static func notify() {
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}
