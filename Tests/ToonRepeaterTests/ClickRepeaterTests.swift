import XCTest
@testable import ToonRepeater

final class ClickRepeaterTests: XCTestCase {
    private let tb = ClickRepeater.titleBarHeight

    func testSameSizedWindowsMapToTheSameOffset() {
        let left = CGRect(x: 0, y: 38, width: 864, height: 509)
        let right = CGRect(x: 864, y: 38, width: 864, height: 509)
        let click = CGPoint(x: 400, y: 38 + tb + 300)
        let mapped = ClickRepeater.absolutePosition(of: ClickRepeater.relativePosition(of: click, in: left), in: right)
        XCTAssertEqual(mapped.x, 864 + 400, accuracy: 0.001)
        XCTAssertEqual(mapped.y, click.y, accuracy: 0.001)
    }

    func testPositionsScaleWithinTheContentAreaBelowTheTitleBar() {
        let small = CGRect(x: 0, y: 0, width: 400, height: 300 + tb)
        let large = CGRect(x: 1000, y: 500, width: 800, height: 600 + tb)
        let centre = CGPoint(x: 200, y: tb + 150)
        let mapped = ClickRepeater.absolutePosition(of: ClickRepeater.relativePosition(of: centre, in: small), in: large)
        XCTAssertEqual(mapped.x, 1400, accuracy: 0.001)
        XCTAssertEqual(mapped.y, 500 + tb + 300, accuracy: 0.001)
    }

    func testCocoaToQuartzFlipsAroundThePrimaryScreen() {
        let height = NSScreen.screens.first?.frame.height ?? 0
        XCTAssertEqual(ClickRepeater.cgPoint(fromCocoa: NSPoint(x: 10, y: height - 20)), CGPoint(x: 10, y: 20))
    }
}
