import XCTest
@testable import ToonRepeater

final class UpdateManagerTests: XCTestCase {
    func testVersionNumbersFromTags() {
        XCTAssertEqual(UpdateManager.versionNumbers("v1.2.3"), [1, 2, 3])
        XCTAssertEqual(UpdateManager.versionNumbers("1.2"), [1, 2])
        XCTAssertEqual(UpdateManager.versionNumbers("ToonRepeater-2.0"), [2, 0])
        XCTAssertEqual(UpdateManager.versionNumbers("v1.4-beta"), [1, 4])
        XCTAssertEqual(UpdateManager.versionNumbers("latest"), [])
    }

    func testNewerComparison() {
        XCTAssertTrue(UpdateManager.isNewer([1, 1], than: [1, 0]))
        XCTAssertTrue(UpdateManager.isNewer([1, 0, 1], than: [1, 0]))
        XCTAssertTrue(UpdateManager.isNewer([1, 10], than: [1, 9]), "numeric, not alphabetical")
        XCTAssertTrue(UpdateManager.isNewer([2], than: [1, 9, 9]))
        XCTAssertFalse(UpdateManager.isNewer([1, 0], than: [1, 0]))
        XCTAssertFalse(UpdateManager.isNewer([1, 0, 0], than: [1, 0]), "1.0.0 equals 1.0")
        XCTAssertFalse(UpdateManager.isNewer([0, 9], than: [1, 0]))
        XCTAssertFalse(UpdateManager.isNewer([], than: [1, 0]))
    }

    func testDecodesGitHubReleaseAndPicksAppZip() throws {
        let json = """
        {"tag_name": "v1.1", "name": "ToonRepeater 1.1", "body": "Fixes", "html_url": "https://github.com/o/r/releases/tag/v1.1",
         "draft": false, "prerelease": false,
         "assets": [
           {"name": "Source.zip", "browser_download_url": "https://github.com/o/r/releases/download/v1.1/Source.zip", "size": 10},
           {"name": "ToonRepeater.app.zip", "browser_download_url": "https://github.com/o/r/releases/download/v1.1/ToonRepeater.app.zip", "size": 650000}
         ]}
        """
        let release = try JSONDecoder().decode(UpdateManager.Release.self, from: Data(json.utf8))
        XCTAssertEqual(release.version, [1, 1])
        XCTAssertEqual(release.versionString, "1.1")
        XCTAssertEqual(release.appZip?.name, "ToonRepeater.app.zip")
        XCTAssertEqual(release.appZip?.size, 650000)
    }

    func testFallsBackToFirstZipAsset() throws {
        let json = """
        {"tag_name": "1.2.0", "html_url": "https://github.com/o/r/releases/tag/1.2.0",
         "assets": [{"name": "notes.txt", "browser_download_url": "https://x/notes.txt", "size": 1},
                    {"name": "ToonRepeater-1.2.zip", "browser_download_url": "https://x/a.zip", "size": 2}]}
        """
        let release = try JSONDecoder().decode(UpdateManager.Release.self, from: Data(json.utf8))
        XCTAssertEqual(release.appZip?.name, "ToonRepeater-1.2.zip")
        XCTAssertNil(release.body)
    }
}
