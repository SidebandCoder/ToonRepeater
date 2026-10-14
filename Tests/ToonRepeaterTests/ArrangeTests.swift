import XCTest
@testable import ToonRepeater

final class ArrangeTests: XCTestCase {
    // A 1728×1117 screen with a 37 pt menu bar: Cocoa visible frame (0, 0, 1728, 1080).
    private let visible = CGRect(x: 0, y: 0, width: 1728, height: 1080)
    private let primaryHeight: CGFloat = 1117

    func testFullWidthGridFillsTheScreenBelowTheMenuBar() {
        let frames = LauncherAutomation.gridFrames(visible: visible, primaryHeight: primaryHeight, widthFraction: 1, side: .right)
        XCTAssertEqual(frames[0], CGRect(x: 0, y: 37, width: 864, height: 540))    // G1 left
        XCTAssertEqual(frames[1], CGRect(x: 864, y: 37, width: 864, height: 540))  // G1 right
        XCTAssertEqual(frames[2], CGRect(x: 0, y: 577, width: 864, height: 540))   // G2 left
        XCTAssertEqual(frames[3], CGRect(x: 864, y: 577, width: 864, height: 540)) // G2 right
    }

    func testSeventyPercentOnTheRight() {
        let frames = LauncherAutomation.gridFrames(visible: visible, primaryHeight: primaryHeight, widthFraction: 0.7, side: .right)
        let width: CGFloat = 1209 // floor(1728 × 0.7)
        XCTAssertEqual(frames[0].minX, 1728 - width)
        XCTAssertEqual(frames[1].maxX, 1728 - 1, accuracy: 1, "grid ends at the right edge")
        XCTAssertEqual(frames[0].width, 604)
        XCTAssertEqual(frames[2].minY, 37 + 540)
    }

    func testSeventyPercentOnTheLeft() {
        let frames = LauncherAutomation.gridFrames(visible: visible, primaryHeight: primaryHeight, widthFraction: 0.7, side: .left)
        XCTAssertEqual(frames[0].minX, 0)
        XCTAssertEqual(frames[1].minX, 604)
    }

    func testSecondScreenOffsets() {
        // A second display to the right of the primary, with no menu bar.
        let second = CGRect(x: 1728, y: -200, width: 1920, height: 1080)
        let frames = LauncherAutomation.gridFrames(visible: second, primaryHeight: primaryHeight, widthFraction: 0.5, side: .right)
        XCTAssertEqual(frames[0].minX, 1728 + 960)
        XCTAssertEqual(frames[0].minY, primaryHeight - 880) // top edge of that screen in top-left coordinates
    }
}
