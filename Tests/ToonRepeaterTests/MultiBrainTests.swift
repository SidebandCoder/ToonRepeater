import AppKit
import XCTest
@testable import ToonRepeater

/// Checks key routing against the behaviour recovered from the original app.
final class MultiBrainTests: XCTestCase {
    struct Sent: Equatable {
        let pid: pid_t
        let key: UInt16
        let down: Bool
        let control: Bool
    }

    private var brain: MultiBrain!
    private var sent: [Sent] = []

    // Fake process IDs: group 1 = 101 (left) / 102 (right), group 2 = 201 / 202.
    override func setUp() {
        Settings.restoreDefaultKeys()
        brain = MultiBrain()
        sent = []
        brain.deliver = { [unowned self] event, pid in
            let key = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let down: Bool
            switch event.type {
            case .keyDown: down = true
            case .keyUp: down = false
            default: down = event.flags.contains(.maskControl) // flagsChanged for modifier keys
            }
            self.sent.append(Sent(pid: pid, key: key, down: down, control: event.flags.contains(.maskControl)))
        }
        brain.assignWindowPID(101, group: 0, toon: 0)
        brain.assignWindowPID(102, group: 0, toon: 1)
        brain.assignWindowPID(201, group: 1, toon: 0)
        brain.assignWindowPID(202, group: 1, toon: 1)
    }

    // MARK: Event helpers

    private func key(_ code: UInt16, down: Bool) -> NSEvent {
        NSEvent.keyEvent(with: down ? .keyDown : .keyUp, location: .zero, modifierFlags: [], timestamp: 0,
                         windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                         isARepeat: false, keyCode: code)!
    }

    /// A flagsChanged event, as macOS sends for modifier keys. `deviceBits` = NX_DEVICE*KEYMASK.
    private func modifier(_ code: UInt16, deviceBits: UInt64, shift: Bool) -> NSEvent {
        let cg = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!
        cg.type = .flagsChanged
        cg.flags = CGEventFlags(rawValue: (shift ? CGEventFlags.maskShift.rawValue : 0) | deviceBits)
        return NSEvent(cgEvent: cg)!
    }

    // MARK: Multi mode

    func testMovementKeysGoOnlyToTheirToon() {
        brain.handleMultiMode(key(13, down: true))   // W -> left toon forward
        brain.handleMultiMode(key(13, down: false))
        brain.handleMultiMode(key(123, down: true))  // ← -> right toon left
        XCTAssertEqual(sent, [
            Sent(pid: 101, key: 126, down: true, control: false),
            Sent(pid: 101, key: 126, down: false, control: false),
            Sent(pid: 102, key: 123, down: true, control: false),
        ])
    }

    func testGroupSelectsWhichWindowsReceive() {
        brain.group = 1
        brain.handleMultiMode(key(0, down: true))    // A -> group 2 left toon
        XCTAssertEqual(sent, [Sent(pid: 201, key: 123, down: true, control: false)])
    }

    func testUnboundKeysAreIgnored() {
        brain.handleMultiMode(key(17, down: true))   // T
        XCTAssertTrue(sent.isEmpty)
    }

    func testJumpSendsControlAndFlagsWhileHeld() {
        brain.handleMultiMode(modifier(56, deviceBits: 0x2, shift: true))  // L⇧ down -> left jump
        brain.handleMultiMode(key(13, down: true))                          // W while jumping
        brain.handleMultiMode(key(126, down: true))                         // ↑ (right toon, not jumping)
        brain.handleMultiMode(modifier(56, deviceBits: 0, shift: false))   // L⇧ up
        XCTAssertEqual(sent, [
            Sent(pid: 101, key: 59, down: true, control: true),
            Sent(pid: 101, key: 126, down: true, control: true),
            Sent(pid: 102, key: 126, down: true, control: false),
            Sent(pid: 101, key: 59, down: false, control: false),
        ])
    }

    func testBothShiftsJumpBothToonsIndependently() {
        brain.handleMultiMode(modifier(56, deviceBits: 0x2, shift: true))        // L⇧ down
        brain.handleMultiMode(modifier(60, deviceBits: 0x2 | 0x4, shift: true))  // R⇧ down
        brain.handleMultiMode(modifier(56, deviceBits: 0x4, shift: true))        // L⇧ up, R⇧ still held
        XCTAssertEqual(sent.map(\.pid), [101, 102, 101])
        XCTAssertEqual(sent.map(\.key), [59, 59, 59])
        XCTAssertEqual(sent.last?.control, false, "left toon's jump released")
    }

    func testThrowChargeHoldsDeleteForBothToons() {
        brain.handleMultiMode(key(42, down: true))   // \ is bound to throw for both toons
        brain.handleMultiMode(key(42, down: false))
        XCTAssertEqual(sent, [
            Sent(pid: 101, key: 117, down: true, control: false),
            Sent(pid: 102, key: 117, down: true, control: false),
            Sent(pid: 101, key: 117, down: false, control: false),
            Sent(pid: 102, key: 117, down: false, control: false),
        ])
    }

    func testThrowLowTapsDeleteOnPressOnly() {
        brain.swapThrowMode()
        XCTAssertEqual(brain.throwMode, .low)
        brain.handleMultiMode(key(42, down: true))
        brain.handleMultiMode(key(42, down: false))
        XCTAssertEqual(sent, [
            Sent(pid: 101, key: 117, down: true, control: false),
            Sent(pid: 101, key: 117, down: false, control: false),
            Sent(pid: 102, key: 117, down: true, control: false),
            Sent(pid: 102, key: 117, down: false, control: false),
        ])
    }

    func testEscapeGoesToBothToonsOfGroup() {
        brain.handleMultiMode(key(53, down: true))
        XCTAssertEqual(sent.map(\.pid), [101, 102])
        XCTAssertEqual(sent.map(\.key), [53, 53])
    }

    func testReleaseKeysLiftsHeldMovement() {
        brain.handleMultiMode(key(13, down: true))   // hold W
        sent = []
        brain.releaseKeys()
        XCTAssertEqual(sent, [Sent(pid: 101, key: 126, down: false, control: false)])
    }

    func testRebindingIsHonoured() {
        Settings.setKey("lForward", 34)              // I
        brain.handleMultiMode(key(13, down: true))   // W no longer bound
        brain.handleMultiMode(key(34, down: true))
        XCTAssertEqual(sent, [Sent(pid: 101, key: 126, down: true, control: false)])
    }

    // MARK: Mirror mode

    func testMirrorCopiesRawKeysToAllWindows() {
        brain.swapMode()
        brain.handleMirrorMode(key(13, down: true))  // W as-is
        XCTAssertEqual(Set(sent.map(\.pid)), [101, 102, 201, 202])
        XCTAssertEqual(Set(sent.map(\.key)), [13])
    }

    func testMirrorThrowChargeAndLow() {
        brain.swapMode()
        brain.handleMirrorMode(key(42, down: true))
        brain.handleMirrorMode(key(42, down: false))
        XCTAssertEqual(sent.count, 8)
        XCTAssertEqual(Set(sent.map(\.key)), [117])
        XCTAssertEqual(sent.filter(\.down).count, 4)

        sent = []
        brain.swapThrowMode()
        brain.handleMirrorMode(key(42, down: true))
        brain.handleMirrorMode(key(42, down: false))
        XCTAssertEqual(sent.count, 8, "press = 4 downs + 4 ups, release = nothing")
    }

    func testUnassignedWindowsReceiveNothing() {
        brain.clearWindowPID(group: 0, toon: 1)
        brain.handleMultiMode(key(126, down: true))  // ↑ for the (now unassigned) right toon
        XCTAssertTrue(sent.isEmpty)
    }
}
