import AppKit
import Security

/// Checks GitHub for a newer release and, if the user chooses Update, downloads it, verifies it, replaces
/// the app and relaunches.
///
/// Releases are read from the GitHub Releases API for the repository in the `MCUpdateRepository` Info.plist key
/// ("owner/repo", set by build.sh). A release is used when its tag (e.g. `v1.1` or `1.1.0`) is a higher version
/// than this app's `CFBundleShortVersionString`, and it has a `ToonRepeater.app.zip` asset. Drafts and
/// pre-releases are ignored. With no repository configured, updates are disabled.
enum UpdateManager {
    struct Release: Decodable {
        let tagName: String
        let name: String?
        let body: String?
        let htmlURL: URL
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name", name, body, htmlURL = "html_url", assets
        }

        var version: [Int] { UpdateManager.versionNumbers(tagName) }
        var versionString: String { version.map(String.init).joined(separator: ".") }

        /// The app zip: `ToonRepeater.app.zip` if present, otherwise the first `.zip` asset.
        var appZip: Asset? {
            assets.first { $0.name == "ToonRepeater.app.zip" } ?? assets.first { $0.name.lowercased().hasSuffix(".zip") }
        }
    }

    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL
        let size: Int

        enum CodingKeys: String, CodingKey {
            case name, browserDownloadURL = "browser_download_url", size
        }
    }

    enum UpdateError: LocalizedError {
        case translocated, unzipFailed, noAppInZip, wrongBundle, badSignature(OSStatus), replaceFailed(String)

        var errorDescription: String? {
            switch self {
            case .translocated:
                return "macOS is running ToonRepeater from a temporary read-only location. Move ToonRepeater to your Applications folder, open it from there, and try again."
            case .unzipFailed: return "The downloaded file couldn't be unzipped."
            case .noAppInZip: return "The download doesn't contain ToonRepeater.app."
            case .wrongBundle: return "The download isn't ToonRepeater."
            case .badSignature(let status): return "The download's code signature didn't check out (error \(status)), so it wasn't installed."
            case .replaceFailed(let reason): return "Couldn't replace the app: \(reason)"
            }
        }
    }

    // MARK: Configuration

    static var repository: String? {
        let repo = (Bundle.main.object(forInfoDictionaryKey: "MCUpdateRepository") as? String)?
            .trimmingCharacters(in: .whitespaces)
        return (repo?.isEmpty ?? true) ? nil : repo
    }

    static var changelogURL: URL? {
        repository.flatMap { URL(string: "https://github.com/\($0)/releases") }
    }

    private static var latestReleaseURL: URL? {
        repository.flatMap { URL(string: "https://api.github.com/repos/\($0)/releases/latest") }
    }

    static var currentVersion: [Int] {
        versionNumbers(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")
    }

    /// "v1.2.3" / "1.2" / "ToonRepeater-1.2" → [1, 2, 3] / [1, 2] / [1, 2].
    static func versionNumbers(_ text: String) -> [Int] {
        guard let start = text.firstIndex(where: \.isNumber) else { return [] }
        return text[start...].split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }

    /// Compares versions numerically, treating missing parts as 0 (so 1.0 == 1.0.0).
    static func isNewer(_ candidate: [Int], than current: [Int]) -> Bool {
        let count = max(candidate.count, current.count)
        let a = candidate + Array(repeating: 0, count: count - candidate.count)
        let b = current + Array(repeating: 0, count: count - current.count)
        return a.lexicographicallyPrecedes(b) == false && a != b
    }

    // MARK: Checking

    /// Checks GitHub for a newer release. `userInitiated` also reports "up to date", skipped versions and errors.
    static func checkForUpdate(userInitiated: Bool) {
        guard let url = latestReleaseURL else {
            if userInitiated {
                alert("Updates aren't configured", "This build has no GitHub repository set (UPDATE_REPOSITORY in build.sh).", buttons: ["Close"])
            }
            return
        }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ToonRepeater/\(Settings.appVersion)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let release = status == 200 ? data.flatMap { try? JSONDecoder().decode(Release.self, from: $0) } : nil
            DispatchQueue.main.async {
                guard let release = release else {
                    if status == 404 {
                        Log.app.notice("update check: no releases published yet")
                        if userInitiated { alert("No releases yet", "There are no published ToonRepeater releases to update to.", buttons: ["Close"]) }
                    } else {
                        Log.app.error("update check failed: HTTP \(status) \(error?.localizedDescription ?? "")")
                        if userInitiated { alert("Couldn't check for updates", "GitHub couldn't be reached. Check your internet connection and try again.", buttons: ["Close"]) }
                    }
                    return
                }
                handle(release, userInitiated: userInitiated)
            }
        }.resume()
    }

    private static func handle(_ release: Release, userInitiated: Bool) {
        let current = currentVersion.map(String.init).joined(separator: ".")
        guard isNewer(release.version, than: currentVersion), let zip = release.appZip else {
            Log.app.notice("update check: latest release \(release.tagName); running \(current)")
            if userInitiated { alert("ToonRepeater is up to date", "You have the latest version, \(current).", buttons: ["Close"]) }
            return
        }
        if !userInitiated, Settings.skippedUpdateVersion == release.versionString {
            Log.app.notice("update check: \(release.versionString) available but skipped")
            return
        }
        Log.app.notice("update check: \(release.versionString) available (running \(current))")

        var notes = (release.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if notes.count > 700 { notes = String(notes.prefix(700)) + "…" }
        let alert = NSAlert()
        alert.messageText = "ToonRepeater \(release.versionString) is available"
        alert.informativeText = "You have version \(current). Update now? ToonRepeater will download the new version, replace itself and restart."
            + (notes.isEmpty ? "" : "\n\nWhat's new:\n\(notes)")
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Skip This Version")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: Updater(release: release, asset: zip).start()
        case .alertThirdButtonReturn: Settings.skippedUpdateVersion = release.versionString
        default: break
        }
    }

    @discardableResult
    static func alert(_ title: String, _ text: String, buttons: [String]) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        buttons.forEach { alert.addButton(withTitle: $0) }
        return alert.runModal()
    }
}

// MARK: - Download and install

/// Downloads a release zip with progress, verifies the app inside, replaces this app and relaunches.
final class Updater {
    private static var active: Updater?

    private let release: UpdateManager.Release
    private let asset: UpdateManager.Asset
    private let panel = ProgressPanel(title: "Updating ToonRepeater")
    private var task: URLSessionDownloadTask?
    private var progressObservation: NSKeyValueObservation?

    init(release: UpdateManager.Release, asset: UpdateManager.Asset) {
        self.release = release
        self.asset = asset
    }

    func start() {
        guard Updater.active == nil else { return }
        if Bundle.main.bundlePath.contains("/AppTranslocation/") {
            fail(UpdateManager.UpdateError.translocated, offerBrowser: false)
            return
        }
        Updater.active = self
        panel.onCancel = { [weak self] in self?.task?.cancel() }
        panel.show()
        panel.setStatus("Downloading ToonRepeater \(release.versionString)…")
        panel.setProgress(0)

        let task = URLSession.shared.downloadTask(with: asset.browserDownloadURL) { [weak self] location, response, error in
            guard let self = self else { return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (error as? URLError)?.code == .cancelled {
                DispatchQueue.main.async { self.finish() }
                return
            }
            guard status == 200, let location = location else {
                DispatchQueue.main.async {
                    self.fail(NSError(domain: "ToonRepeater", code: status,
                                      userInfo: [NSLocalizedDescriptionKey: "The download failed (HTTP \(status))."]), offerBrowser: true)
                }
                return
            }
            // The downloaded file is deleted when this handler returns, so install synchronously here.
            do {
                try self.install(zip: location)
                DispatchQueue.main.async {
                    Log.app.notice("installed update \(self.release.versionString); relaunching")
                    self.panel.setStatus("Restarting…")
                    AppDelegate.relaunch()
                }
            } catch {
                DispatchQueue.main.async { self.fail(error, offerBrowser: true) }
            }
        }
        progressObservation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            DispatchQueue.main.async { self?.panel.setProgress(progress.fractionCompleted) }
        }
        self.task = task
        task.resume()
    }

    /// Diagnostics: `ToonRepeater --test-install <zip> <result file>` installs a release zip over this copy of
    /// the app using the real unzip/verify/replace steps, without relaunching, and writes the outcome.
    static func testInstallIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--test-install"), i + 2 < args.count else { return false }
        let zip = URL(fileURLWithPath: args[i + 1])
        let release = UpdateManager.Release(tagName: "test", name: nil, body: nil,
                                            htmlURL: URL(string: "https://github.com")!, assets: [])
        let updater = Updater(release: release, asset: UpdateManager.Asset(name: zip.lastPathComponent, browserDownloadURL: zip, size: 0))
        var result: String
        do {
            try updater.install(zip: zip)
            result = "installed"
        } catch {
            result = "failed: \(error.localizedDescription)"
        }
        try? result.write(toFile: args[i + 2], atomically: true, encoding: .utf8)
        return true
    }

    private func install(zip: URL) throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("ToonRepeaterUpdate-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: work) }
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        if !Thread.isMainThread {
            DispatchQueue.main.async { self.panel.setStatus("Installing ToonRepeater \(self.release.versionString)…") }
        }

        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, work.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw UpdateManager.UpdateError.unzipFailed }

        guard let newApp = try fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" }) else { throw UpdateManager.UpdateError.noAppInZip }
        try verify(newApp)

        do {
            _ = try fm.replaceItemAt(Bundle.main.bundleURL, withItemAt: newApp)
        } catch {
            throw UpdateManager.UpdateError.replaceFailed(error.localizedDescription)
        }
    }

    /// The new app must be ToonRepeater (same bundle ID) with a valid code signature. When this copy is signed
    /// with a certificate, the new one must be signed with the same certificate too, so a tampered download
    /// can't replace it. (Ad-hoc builds can only check that the signature is intact.)
    private func verify(_ newApp: URL) throws {
        guard Bundle(url: newApp)?.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw UpdateManager.UpdateError.wrongBundle
        }
        var newCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(newApp as CFURL, [], &newCode) == errSecSuccess, let newCode = newCode else {
            throw UpdateManager.UpdateError.badSignature(errSecCSUnsigned)
        }
        let requirement = Updater.currentCertificateRequirement()
        let status = SecStaticCodeCheckValidity(newCode, SecCSFlags(), requirement)
        guard status == errSecSuccess else { throw UpdateManager.UpdateError.badSignature(status) }
    }

    /// This app's designated requirement, if it is certificate-based (not an ad-hoc cdhash requirement).
    private static func currentCertificateRequirement() -> SecRequirement? {
        var selfCode: SecCode?
        var staticCode: SecStaticCode?
        var requirement: SecRequirement?
        var text: CFString?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let selfCode = selfCode,
              SecCodeCopyStaticCode(selfCode, [], &staticCode) == errSecSuccess, let staticCode = staticCode,
              SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess, let requirement = requirement,
              SecRequirementCopyString(requirement, [], &text) == errSecSuccess,
              let string = text as String?, string.contains("certificate") || string.contains("anchor")
        else { return nil }
        return requirement
    }

    private func fail(_ error: Error, offerBrowser: Bool) {
        Log.app.error("update to \(release.versionString) failed: \(error.localizedDescription)")
        finish()
        if offerBrowser {
            if UpdateManager.alert("The update couldn't be installed", error.localizedDescription + "\n\nDownload it from GitHub instead?",
                                   buttons: ["Open GitHub", "Close"]) == .alertFirstButtonReturn {
                NSWorkspace.shared.open(release.htmlURL)
            }
        } else {
            UpdateManager.alert("The update couldn't be installed", error.localizedDescription, buttons: ["Close"])
        }
    }

    private func finish() {
        panel.close()
        progressObservation = nil
        Updater.active = nil
    }
}
