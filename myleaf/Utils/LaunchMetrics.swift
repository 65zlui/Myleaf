import Foundation
import OSLog

/// Lightweight launch instrumentation. Read with:
/// `log show --last 2m --predicate 'subsystem == "com.65zlui.myleaf" AND category == "launch"'`
enum LaunchMetrics {
    private static let start = Date()
    private static let logger = Logger(subsystem: "com.65zlui.myleaf", category: "launch")

    private static let logDirectory: URL = {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        return library
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("myleaf", isDirectory: true)
    }()

    private static let writeQueue = DispatchQueue(
        label: "com.65zlui.myleaf.launch-log",
        qos: .utility
    )

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()

    static func mark(_ name: String) {
        let elapsed = Date().timeIntervalSince(start)
        logger.info("\(name, privacy: .public): \(elapsed, format: .fixed(precision: 3))s")

        let line = "\(name): \(String(format: "%.3f", elapsed))s\n"
        let file = logDirectory
            .appendingPathComponent("launch-\(dayFormatter.string(from: Date())).log")

        // Never put disk I/O on the launch path.
        writeQueue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: logDirectory, withIntermediateDirectories: true)
            if !fm.fileExists(atPath: file.path) {
                fm.createFile(atPath: file.path, contents: nil)
            }
            if let handle = try? FileHandle(forWritingTo: file) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data(line.utf8))
            }
        }
    }
}
