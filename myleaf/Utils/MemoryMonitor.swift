import Foundation

/// Lightweight memory leak detection using the `leaks` CLI tool.
/// Only active in DEBUG builds.
enum MemoryMonitor {

    private static var isRunning = false
    private static var timer: DispatchSourceTimer?

    /// Start periodic leak checking (every 60 seconds).
    /// Does nothing in RELEASE builds or if already running.
    static func start() {
        #if DEBUG
        guard !isRunning else { return }

        let pid = ProcessInfo.processInfo.processIdentifier
        console("MemoryMonitor started for pid \(pid)")

        isRunning = true
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .background))
        t.schedule(deadline: .now() + 30, repeating: .seconds(60), leeway: .seconds(10))
        t.setEventHandler { runLeaksCheck() }
        t.resume()
        timer = t

        // First check after a short delay
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 5) {
            runLeaksCheck()
        }
        #else
        // No-op in Release
        #endif
    }

    /// Stop periodic checking.
    static func stop() {
        #if DEBUG
        timer?.cancel()
        timer = nil
        isRunning = false
        console("MemoryMonitor stopped")
        #endif
    }

    /// Trigger an immediate leak check.
    static func check() {
        #if DEBUG
        runLeaksCheck()
        #endif
    }

    // MARK: - Private

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private static func console(_ message: String) {
        let ts = dateFormatter.string(from: Date())
        print("[\(ts)] [MemoryMonitor] \(message)")
    }

    private static func runLeaksCheck() {
        let pid = ProcessInfo.processInfo.processIdentifier

        // Check for leaks using the `leaks` command with --output to get machine-readable results
        let output = shell("/usr/bin/leaks", "\(pid)", "--output=/dev/stdout")
        let stderr = shell("/usr/bin/leaks", "\(pid)", "--nostacks")

        if output.contains("leaks Report") || stderr.contains("leaks Report") {
            // Leaks found
            let combined = output + stderr
            // Count the number of leaked objects
            let leakCount = combined.components(separatedBy: "leak").count - 1
            let processCount = combined.components(separatedBy: "Process").count - 1
            let totalLeaks = leakCount + processCount

            if totalLeaks > 0 {
                console("⚠️  \(totalLeaks) leak(s) detected!")
                // Print the first ~15 lines of the leak report
                let lines = combined.components(separatedBy: "\n")
                for line in lines.prefix(20) where !line.isEmpty {
                    if line.contains("leak") || line.contains("Leak") || line.contains("Process") {
                        print("  \(line.trimmingCharacters(in: .whitespaces))")
                    }
                }
            } else {
                console("No leaks detected ✅")
            }
        } else {
            console("No leaks detected ✅")
        }
    }

    /// Run a shell command and return its output.
    @discardableResult
    private static func shell(_ args: String...) -> String {
        let process = Process()
        process.launchPath = "/usr/bin/env"
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        process.launch()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return String(data: data, encoding: .utf8) ?? ""
    }
}
