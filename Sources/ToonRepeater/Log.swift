import Foundation
import os

/// Logging to the unified log and to a rotating file users can send for debugging
/// (Help › Export Diagnostic Report…). Notices and errors go to the file; debug messages (every key press)
/// only to the unified log: `log stream --predicate 'subsystem == "ToonRepeater"' --level debug`.
///
/// Never log launcher usernames or anything else personal.
enum Log {
    static let app = Channel(category: "app")
    static let events = Channel(category: "events")

    struct Channel {
        private let logger: Logger
        private let category: String

        init(category: String) {
            self.category = category
            logger = Logger(subsystem: "ToonRepeater", category: category)
        }

        func debug(_ message: String) {
            logger.debug("\(message, privacy: .public)")
        }

        func notice(_ message: String) {
            logger.notice("\(message, privacy: .public)")
            LogFile.shared.append("[\(category)] \(message)")
        }

        func error(_ message: String) {
            logger.error("\(message, privacy: .public)")
            LogFile.shared.append("[\(category)] ERROR \(message)")
        }
    }
}

/// `~/Library/Logs/ToonRepeater/ToonRepeater.log`, rotated at 1 MB, keeping two older files.
final class LogFile {
    static let shared = LogFile()

    let directory: URL
    private var url: URL { directory.appendingPathComponent("ToonRepeater.log") }
    private let queue = DispatchQueue(label: "log-file")
    private let maxSize = 1_000_000
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private init() {
        directory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/ToonRepeater", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func append(_ line: String) {
        let stamped = "\(formatter.string(from: Date())) \(line)\n"
        queue.async {
            self.rotateIfNeeded()
            guard let data = stamped.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: self.url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: self.url)
            }
        }
    }

    /// Waits for pending writes, e.g. before exporting.
    func flush() { queue.sync {} }

    /// All log files, newest first.
    var files: [URL] {
        ["ToonRepeater.log", "ToonRepeater.1.log", "ToonRepeater.2.log"]
            .map { directory.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func rotateIfNeeded() {
        let fm = FileManager.default
        guard let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > maxSize else { return }
        let older = directory.appendingPathComponent("ToonRepeater.2.log")
        let old = directory.appendingPathComponent("ToonRepeater.1.log")
        try? fm.removeItem(at: older)
        try? fm.moveItem(at: old, to: older)
        try? fm.moveItem(at: url, to: old)
    }
}
