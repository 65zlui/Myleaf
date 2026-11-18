import Foundation

/// Persists one log file per compilation under ~/Library/Logs/myleaf so users
/// (and support requests) can inspect exactly what the LaTeX engine did.
enum BuildLogStore {

    static let maxLogCount = 30

    /// ~/Library/Logs/myleaf
    static var directory: URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        return library
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("myleaf", isDirectory: true)
    }

    private static let fileStampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter
    }()

    /// Writes a log and returns its URL. Old logs beyond `maxLogCount` are
    /// pruned automatically.
    @discardableResult
    static func save(_ contents: String, date: Date = Date()) -> URL? {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let name = "build-\(fileStampFormatter.string(from: date)).log"
            let url = directory.appendingPathComponent(name)
            try contents.write(to: url, atomically: true, encoding: .utf8)
            pruneOldLogs()
            return url
        } catch {
            return nil
        }
    }

    /// Newest first.
    static func recentLogs() -> [URL] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return urls
            .filter { $0.pathExtension == "log" }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return l > r
            }
    }

    private static func pruneOldLogs() {
        let logs = recentLogs()
        guard logs.count > maxLogCount else { return }
        for url in logs.dropFirst(maxLogCount) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
