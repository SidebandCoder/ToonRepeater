import AppKit

/// macOS virtual key codes used throughout the app, plus display names for the keybind editor.
enum KeyCodes {
    static let escape: UInt16 = 53
    static let grave: UInt16 = 50          // ` (Toggle Mode hotkey)
    static let one: UInt16 = 18
    static let two: UInt16 = 19
    static let home: UInt16 = 115          // keep-alive tap
    static let forwardDelete: UInt16 = 117 // ToonTown "throw pie"
    static let leftControl: UInt16 = 59    // ToonTown "jump"

    private static let names: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
        20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
        29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↵", 37: "L",
        38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M",
        47: ".", 48: "⇥", 49: "␣", 50: "`", 51: "⌫", 53: "⎋", 54: "R⌘", 55: "L⌘",
        56: "L⇧", 57: "⇪", 58: "L⌥", 59: "L⌃", 60: "R⇧", 61: "R⌥", 62: "R⌃", 63: "fn",
        65: "K.", 67: "K*", 69: "K+", 71: "Clr", 75: "K/", 76: "K↵", 78: "K-", 81: "K=",
        82: "K0", 83: "K1", 84: "K2", 85: "K3", 86: "K4", 87: "K5", 88: "K6", 89: "K7",
        91: "K8", 92: "K9", 96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
        103: "F11", 105: "F13", 107: "F14", 109: "F10", 111: "F12", 113: "F15", 114: "Help",
        115: "Home", 116: "PgUp", 117: "⌦", 118: "F4", 119: "End", 120: "F2", 121: "PgDn",
        122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    static func string(of keyCode: UInt16) -> String {
        names[keyCode] ?? "#\(keyCode)"
    }

    /// Device-specific modifier bits (IOKit NX_DEVICE*KEYMASK) so left/right modifiers are told apart.
    private static let deviceMask: [UInt16: UInt] = [
        59: 0x0001, 62: 0x2000, // L/R control
        56: 0x0002, 60: 0x0004, // L/R shift
        55: 0x0008, 54: 0x0010, // L/R command
        58: 0x0020, 61: 0x0040, // L/R option
    ]

    static func isModifier(_ keyCode: UInt16) -> Bool {
        deviceMask[keyCode] != nil || keyCode == 57 || keyCode == 63
    }

    /// Whether a flagsChanged event for `keyCode` is a press (true) or a release (false).
    static func isPressed(_ keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        if let mask = deviceMask[keyCode] { return flags.rawValue & mask != 0 }
        if keyCode == 63 { return flags.contains(.function) }
        if keyCode == 57 { return flags.contains(.capsLock) }
        return false
    }
}
