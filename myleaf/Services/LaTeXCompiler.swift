import Foundation
import OSLog

private let buildLogger = Logger(subsystem: "com.65zlui.myleaf", category: "build")

enum CompilationError: LocalizedError {
    case engineNotFound
    case compilationFailed(log: String, logFile: URL?)
    case outputNotFound(log: String, logFile: URL?)
    case processError(String, log: String, logFile: URL?)
    case timedOut(seconds: Int, log: String, logFile: URL?)

    var errorDescription: String? {
        switch self {
        case .engineNotFound:
            return "No LaTeX engine found. Please install Tectonic via the button above."
        case .compilationFailed(let log, _):
            return log
        case .outputNotFound:
            return "Compilation succeeded but no PDF was generated."
        case .processError(let msg, _, _):
            return "Failed to run LaTeX engine: \(msg)"
        case .timedOut(let seconds, _, _):
            return "Compilation timed out after \(seconds) seconds. Check your network connection (Tectonic downloads packages on first use) and try again."
        }
    }

    /// The full, structured build log (engine output included), when there is one.
    var buildLog: String? {
        switch self {
        case .compilationFailed(let log, _),
             .outputNotFound(let log, _),
             .processError(_, let log, _),
             .timedOut(_, let log, _):
            return log
        case .engineNotFound:
            return nil
        }
    }

    /// Path of the persisted log file for this failure.
    var buildLogFile: URL? {
        switch self {
        case .compilationFailed(_, let url),
             .outputNotFound(_, let url),
             .processError(_, _, let url),
             .timedOut(_, _, let url):
            return url
        case .engineNotFound:
            return nil
        }
    }
}

struct TeXEngine: Equatable {
    enum Kind: String {
        case tectonic
        case pdflatex

        var displayName: String {
            switch self {
            case .tectonic: return "Tectonic"
            case .pdflatex: return "pdflatex"
            }
        }
    }

    let kind: Kind
    let url: URL
    /// Short version string, e.g. "0.17.0". Nil when the probe failed.
    let version: String?

    var displayName: String { kind.displayName }
    var path: String { url.path }

    var versionDescription: String {
        if let version { return "\(displayName) \(version)" }
        return displayName
    }

    /// Numeric-aware version comparison. A missing version sorts below any known one.
    static func compareVersions(_ lhs: String?, _ rhs: String?) -> ComparisonResult {
        let left = versionComponents(lhs)
        let right = versionComponents(rhs)

        if left.isEmpty && right.isEmpty { return .orderedSame }
        if left.isEmpty { return .orderedAscending }
        if right.isEmpty { return .orderedDescending }

        let count = max(left.count, right.count)
        for index in 0..<count {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a < b ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    private static func versionComponents(_ version: String?) -> [Int] {
        guard let version else { return [] }
        return version
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
    }
}

/// Per-phase wall-clock measurements for a single compile.
struct CompilationTimings: Equatable {
    var preparation: TimeInterval = 0
    var engine: TimeInterval = 0
    var pdfLoad: TimeInterval = 0
    var total: TimeInterval = 0
}

enum CompilerStatus: Equatable {
    case checking
    case ready(engine: TeXEngine)
    case notFound
}

/// The artifacts of a successful compilation. The PDF is kept in memory so
/// temporary files can be removed as soon as compilation finishes.
struct CompilationOutput {
    let pdfData: Data
    let log: String
    let logFileURL: URL?
    let duration: TimeInterval
    let timings: CompilationTimings
}

final class LaTeXCompiler {

    /// Seconds before a runaway compilation is terminated.
    private let compilationTimeout: TimeInterval = 300

    private(set) var engine: TeXEngine?

    /// App Support path where tectonic is installed
    private var installedTectonicPath: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("myleaf", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("tectonic")
    }

    // MARK: - Engine Detection

    /// Detects available engines and selects the newest Tectonic build.
    ///
    /// Older Tectonic releases (e.g. 0.16.x) can spend several seconds on a
    /// bundle-index network check even for tiny documents, while 0.17.x uses
    /// the cache and starts in fractions of a second. Every Tectonic candidate
    /// is therefore probed with `--version` and the highest version wins.
    /// pdflatex is used only when no Tectonic is available.
    func detectEngine() -> TeXEngine? {
        let fm = FileManager.default

        var tectonicPaths = [
            installedTectonicPath.path,
            "/opt/homebrew/bin/tectonic",
            "/usr/local/bin/tectonic"
        ]

        // Only pay for a login-shell lookup when none of the usual locations
        // exist; this keeps launch-time detection fast.
        if !tectonicPaths.contains(where: { fm.isExecutableFile(atPath: $0) }),
           let which = runWhich("tectonic") {
            tectonicPaths.append(which)
        }

        var seen = Set<String>()
        var tectonicEngines: [TeXEngine] = []

        for path in tectonicPaths {
            let url = URL(fileURLWithPath: path)
            guard fm.isExecutableFile(atPath: url.path) else { continue }
            let key = url.resolvingSymlinksInPath().path
            guard seen.insert(key).inserted else { continue }
            tectonicEngines.append(TeXEngine(
                kind: .tectonic,
                url: url,
                version: Self.queryVersion(at: url, kind: .tectonic)
            ))
        }

        var best: TeXEngine?
        for candidate in tectonicEngines {
            guard let current = best else {
                best = candidate
                continue
            }
            if TeXEngine.compareVersions(candidate.version, current.version) == .orderedDescending {
                best = candidate
            }
        }

        if let best {
            engine = best
            return best
        }

        var pdflatexPaths = [
            "/Library/TeX/texbin/pdflatex",
            "/usr/local/bin/pdflatex",
            "/opt/homebrew/bin/pdflatex",
            "/usr/texbin/pdflatex"
        ]
        if !pdflatexPaths.contains(where: { fm.isExecutableFile(atPath: $0) }),
           let which = runWhich("pdflatex") {
            pdflatexPaths.append(which)
        }

        seen.removeAll()
        for path in pdflatexPaths {
            let url = URL(fileURLWithPath: path)
            guard fm.isExecutableFile(atPath: url.path) else { continue }
            let key = url.resolvingSymlinksInPath().path
            guard seen.insert(key).inserted else { continue }
            let selected = TeXEngine(
                kind: .pdflatex,
                url: url,
                version: Self.queryVersion(at: url, kind: .pdflatex)
            )
            engine = selected
            return selected
        }

        engine = nil
        return nil
    }

    // MARK: - Version Helpers

    /// Runs `<engine> --version` and extracts a short, display-friendly version.
    private static func queryVersion(at url: URL, kind: TeXEngine.Kind) -> String? {
        let process = Process()
        process.executableURL = url
        process.arguments = ["--version"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }

            let firstLine = output
                .split(whereSeparator: \.isNewline)
                .first
                .map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let firstLine, !firstLine.isEmpty else { return nil }

            if kind == .tectonic,
               let range = firstLine.range(of: #"\d+\.\d+(?:\.\d+)?"#, options: .regularExpression) {
                return String(firstLine[range])
            }
            return firstLine
        } catch {
            return nil
        }
    }

    private func runWhich(_ command: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "which \(command)"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !output.isEmpty,
                   FileManager.default.isExecutableFile(atPath: output) {
                    return output
                }
            }
        } catch {}

        return nil
    }

    // MARK: - Compilation

    /// Compiles `source` and returns the resulting PDF data.
    ///
    /// If `documentURL` is provided, the document is written to a temporary
    /// sibling file inside the document's own directory and compiled from
    /// there. This makes relative references (`\input`, `\includegraphics`,
    /// `\bibliography`) resolve exactly as they do when the user compiles the
    /// file with a command-line tool. The temporary file is removed afterwards.
    func compile(source: String, documentURL: URL? = nil) async -> Result<CompilationOutput, CompilationError> {
        guard let engine = engine else {
            buildLogger.error("Compile requested but no engine is available")
            return .failure(.engineNotFound)
        }

        let startedAt = Date()
        buildLogger.info("Compile started with \(engine.versionDescription, privacy: .public)")

        let fm = FileManager.default
        let workDir = fm.temporaryDirectory
            .appendingPathComponent("myleaf-build-\(UUID().uuidString)")
        let outDir = workDir.appendingPathComponent("output")

        do {
            try fm.createDirectory(at: outDir, withIntermediateDirectories: true)
        } catch {
            return .failure(.processError(
                "Failed to create temp directory: \(error.localizedDescription)",
                log: "", logFile: nil
            ))
        }

        // Compile from the project directory when possible so that relative
        // paths (images, \input files, .bib files) resolve correctly.
        var compileFile: URL?
        var temporarySibling: URL?

        if let documentURL {
            let projectDir = documentURL.deletingLastPathComponent()

            // If the buffer matches the file on disk, compile the real file
            // directly — no temporary sibling is needed.
            if let onDisk = try? String(contentsOf: documentURL, encoding: .utf8), onDisk == source {
                compileFile = documentURL
            } else {
                let sibling = projectDir.appendingPathComponent("myleaf-compile-\(UUID().uuidString.prefix(8)).tex")
                do {
                    try source.write(to: sibling, atomically: true, encoding: .utf8)
                    compileFile = sibling
                    temporarySibling = sibling
                } catch {
                    // Directory not writable (read-only volume, permissions, …):
                    // fall back to a self-contained temp compile below.
                }
            }
        }

        if compileFile == nil {
            let texFile = workDir.appendingPathComponent("document.tex")
            do {
                try source.write(to: texFile, atomically: true, encoding: .utf8)
                compileFile = texFile
            } catch {
                try? fm.removeItem(at: workDir)
                return .failure(.processError(
                    "Failed to write temp files: \(error.localizedDescription)",
                    log: "", logFile: nil
                ))
            }
        }

        defer {
            if let temporarySibling {
                try? fm.removeItem(at: temporarySibling)
            }
            try? fm.removeItem(at: workDir)
        }

        guard let inputFile = compileFile else {
            return .failure(.processError("No input file", log: "", logFile: nil))
        }

        let workingDirectory = inputFile.deletingLastPathComponent()
        let arguments: [String]
        switch engine.kind {
        case .tectonic:
            arguments = ["--outdir", outDir.path, "--keep-logs", inputFile.path]
        case .pdflatex:
            arguments = [
                "-interaction=nonstopmode",
                "-halt-on-error",
                "-output-directory", outDir.path,
                inputFile.path
            ]
        }

        let preparation = Date().timeIntervalSince(startedAt)
        let commandLine = ([engine.path] + arguments).map(Self.shellQuoted).joined(separator: " ")
        buildLogger.info("Running \(engine.versionDescription, privacy: .public): \(commandLine, privacy: .public)")

        let engineLogURL = workDir.appendingPathComponent("build.log")
        let engineStart = Date()
        let run = await runProcess(
            executable: URL(fileURLWithPath: engine.path),
            arguments: arguments,
            workingDirectory: workingDirectory,
            logURL: engineLogURL
        )
        let engineDuration = Date().timeIntervalSince(engineStart)
        let engineLog = readLog(at: engineLogURL)

        // Read the PDF before building the log so its time is measured too.
        var pdfData: Data?
        var pdfLoad: TimeInterval = 0
        if run.launchError == nil, !run.timedOut, (run.exitCode ?? -1) == 0 {
            // Tectonic names the output after the input file; pdflatex does the same.
            let pdfURL = outDir
                .appendingPathComponent(inputFile.deletingPathExtension().lastPathComponent)
                .appendingPathExtension("pdf")
            let pdfStart = Date()
            if let data = try? Data(contentsOf: pdfURL), !data.isEmpty {
                pdfData = data
            }
            pdfLoad = Date().timeIntervalSince(pdfStart)
        }

        let total = Date().timeIntervalSince(startedAt)
        let timings = CompilationTimings(
            preparation: preparation,
            engine: engineDuration,
            pdfLoad: pdfLoad,
            total: total
        )

        let buildLog = makeBuildLog(
            startedAt: startedAt,
            timings: timings,
            engine: engine,
            inputFile: inputFile,
            workingDirectory: workingDirectory,
            arguments: arguments,
            engineLog: engineLog,
            run: run
        )
        let savedLogURL = BuildLogStore.save(buildLog, date: startedAt)

        if let launchError = run.launchError {
            buildLogger.error("Failed to launch engine: \(launchError, privacy: .public)")
            return .failure(.processError(launchError, log: buildLog, logFile: savedLogURL))
        }

        if run.timedOut {
            buildLogger.error("Compilation timed out after \(self.compilationTimeout) seconds")
            return .failure(.timedOut(
                seconds: Int(compilationTimeout),
                log: buildLog,
                logFile: savedLogURL
            ))
        }

        let exitCode = run.exitCode ?? -1
        guard exitCode == 0 else {
            buildLogger.error("Compilation failed with exit status \(exitCode)")
            return .failure(.compilationFailed(log: buildLog, logFile: savedLogURL))
        }

        guard let data = pdfData else {
            buildLogger.error("Engine exited successfully but produced no PDF")
            return .failure(.outputNotFound(log: buildLog, logFile: savedLogURL))
        }

        buildLogger.info("Compilation succeeded in \(timings.total, format: .fixed(precision: 2)) s (engine \(timings.engine, format: .fixed(precision: 2)) s)")
        return .success(CompilationOutput(
            pdfData: data,
            log: buildLog,
            logFileURL: savedLogURL,
            duration: timings.total,
            timings: timings
        ))
    }

    // MARK: - Build Log

    private func makeBuildLog(
        startedAt: Date,
        timings: CompilationTimings,
        engine: TeXEngine,
        inputFile: URL,
        workingDirectory: URL,
        arguments: [String],
        engineLog: String,
        run: ProcessRunResult
    ) -> String {
        let command = ([engine.path] + arguments).map(Self.shellQuoted).joined(separator: " ")

        var lines: [String] = [
            "myleaf build log",
            "================",
            "Started: \(Self.logTimestamp(startedAt))",
            "Engine: \(engine.displayName)",
            "Engine version: \(engine.version ?? "unknown")",
            "Engine path: \(engine.path)",
            "Input: \(inputFile.path)",
            "Working directory: \(workingDirectory.path)",
            "Command: \(command)",
            "Timeout: \(Int(compilationTimeout))s",
            "",
            "--- engine output ---",
            engineLog.isEmpty ? "(no output)" : engineLog,
            "",
            "--- result ---",
        ]

        if let launchError = run.launchError {
            lines.append("Launch error: \(launchError)")
        } else if run.timedOut {
            lines.append("Timed out after \(Int(compilationTimeout))s")
        } else {
            lines.append("Exit status: \(run.exitCode ?? -1)")
        }

        lines.append("")
        lines.append("--- timings ---")
        lines.append("Preparation: \(Self.seconds(timings.preparation))s")
        lines.append("Engine run: \(Self.seconds(timings.engine))s")
        lines.append("PDF read: \(Self.seconds(timings.pdfLoad))s")
        lines.append("Total: \(Self.seconds(timings.total))s")
        lines.append("Finished: \(Self.logTimestamp(Date()))")
        lines.append("")

        return lines.joined(separator: "\n")
    }

    private static func seconds(_ value: TimeInterval) -> String {
        String(format: "%.3f", value)
    }

    private static func shellQuoted(_ value: String) -> String {
        guard !value.isEmpty else { return "''" }
        let needsQuoting = value.rangeOfCharacter(
            from: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'\\$`"))
        ) != nil
        guard needsQuoting else { return value }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static let logTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private static func logTimestamp(_ date: Date) -> String {
        logTimestampFormatter.string(from: date)
    }

    // MARK: - Process Execution

    /// Runs a process with stdout/stderr redirected to a log file.
    ///
    /// Using files instead of pipes is deliberate: `waitUntilExit()` together
    /// with `Pipe` can deadlock once the child writes more than the 64 KB pipe
    /// buffer (very common with verbose LaTeX logs). File redirection has no
    /// such limit.
    private struct ProcessRunResult {
        var exitCode: Int32? = nil
        var timedOut: Bool = false
        var launchError: String? = nil
    }

    private func runProcess(
        executable: URL,
        arguments: [String],
        workingDirectory: URL,
        logURL: URL
    ) async -> ProcessRunResult {
        let timeout = compilationTimeout
        return await withCheckedContinuation { (continuation: CheckedContinuation<ProcessRunResult, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let fm = FileManager.default
                fm.createFile(atPath: logURL.path, contents: nil)

                guard let logHandle = try? FileHandle(forWritingTo: logURL) else {
                    continuation.resume(returning: ProcessRunResult(launchError: "Failed to open log file"))
                    return
                }

                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                process.currentDirectoryURL = workingDirectory
                process.standardOutput = logHandle
                process.standardError = logHandle

                do {
                    try process.run()
                } catch {
                    try? logHandle.close()
                    continuation.resume(returning: ProcessRunResult(launchError: error.localizedDescription))
                    return
                }

                let deadline = Date().addingTimeInterval(timeout)
                var timedOut = false
                while process.isRunning {
                    if Date() > deadline {
                        timedOut = true
                        process.terminate()
                        // Give the engine a moment to exit cleanly, then force kill.
                        Thread.sleep(forTimeInterval: 1.0)
                        if process.isRunning {
                            kill(process.processIdentifier, SIGKILL)
                        }
                        break
                    }
                    Thread.sleep(forTimeInterval: 0.05)
                }

                process.waitUntilExit()
                try? logHandle.close()

                if timedOut {
                    continuation.resume(returning: ProcessRunResult(timedOut: true))
                } else {
                    continuation.resume(returning: ProcessRunResult(exitCode: process.terminationStatus))
                }
            }
        }
    }

    private func readLog(at url: URL) -> String {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Keep the error panel responsive with enormous logs.
        let limit = 200_000
        if trimmed.count > limit {
            return String(trimmed.suffix(limit))
        }
        return trimmed
    }
}
