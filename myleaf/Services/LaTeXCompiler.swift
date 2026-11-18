import Foundation

enum CompilationError: LocalizedError {
    case engineNotFound
    case compilationFailed(log: String)
    case outputNotFound
    case processError(String)
    case timedOut(seconds: Int)

    var errorDescription: String? {
        switch self {
        case .engineNotFound:
            return "No LaTeX engine found. Please install Tectonic via the button above."
        case .compilationFailed(let log):
            return log
        case .outputNotFound:
            return "Compilation succeeded but no PDF was generated."
        case .processError(let msg):
            return "Failed to run LaTeX engine: \(msg)"
        case .timedOut(let seconds):
            return "Compilation timed out after \(seconds) seconds. Check your network connection (Tectonic downloads packages on first use) and try again."
        }
    }
}

enum TeXEngine: Equatable {
    case tectonic(URL)
    case pdflatex(URL)

    var displayName: String {
        switch self {
        case .tectonic: return "Tectonic"
        case .pdflatex: return "pdflatex"
        }
    }

    var path: String {
        switch self {
        case .tectonic(let url), .pdflatex(let url):
            return url.path
        }
    }
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

    /// Detect available TeX engine. Priority: installed tectonic → system tectonic → system pdflatex
    func detectEngine() -> TeXEngine? {
        let fm = FileManager.default

        // 1. Check app-installed tectonic
        if fm.isExecutableFile(atPath: installedTectonicPath.path) {
            let e = TeXEngine.tectonic(installedTectonicPath)
            engine = e
            return e
        }

        // 2. Check system tectonic
        let tectonicCandidates = [
            "/opt/homebrew/bin/tectonic",
            "/usr/local/bin/tectonic"
        ]
        for path in tectonicCandidates {
            if fm.isExecutableFile(atPath: path) {
                let e = TeXEngine.tectonic(URL(fileURLWithPath: path))
                engine = e
                return e
            }
        }

        // 3. Check system pdflatex
        let pdflatexCandidates = [
            "/Library/TeX/texbin/pdflatex",
            "/usr/local/bin/pdflatex",
            "/opt/homebrew/bin/pdflatex",
            "/usr/texbin/pdflatex"
        ]
        for path in pdflatexCandidates {
            if fm.isExecutableFile(atPath: path) {
                let e = TeXEngine.pdflatex(URL(fileURLWithPath: path))
                engine = e
                return e
            }
        }

        // 4. Fallback: which
        if let path = runWhich("tectonic") {
            let e = TeXEngine.tectonic(URL(fileURLWithPath: path))
            engine = e
            return e
        }
        if let path = runWhich("pdflatex") {
            let e = TeXEngine.pdflatex(URL(fileURLWithPath: path))
            engine = e
            return e
        }

        engine = nil
        return nil
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
            return .failure(.engineNotFound)
        }

        let fm = FileManager.default
        let workDir = fm.temporaryDirectory
            .appendingPathComponent("myleaf-build-\(UUID().uuidString)")
        let outDir = workDir.appendingPathComponent("output")

        do {
            try fm.createDirectory(at: outDir, withIntermediateDirectories: true)
        } catch {
            return .failure(.processError("Failed to create temp directory: \(error.localizedDescription)"))
        }

        // Compile from the project directory when possible so that relative
        // paths (images, \input files, .bib files) resolve correctly.
        var compileFile: URL?
        var temporarySibling: URL?

        if let documentURL {
            let projectDir = documentURL.deletingLastPathComponent()
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

        if compileFile == nil {
            let texFile = workDir.appendingPathComponent("document.tex")
            do {
                try source.write(to: texFile, atomically: true, encoding: .utf8)
                compileFile = texFile
            } catch {
                try? fm.removeItem(at: workDir)
                return .failure(.processError("Failed to write temp files: \(error.localizedDescription)"))
            }
        }

        defer {
            if let temporarySibling {
                try? fm.removeItem(at: temporarySibling)
            }
            try? fm.removeItem(at: workDir)
        }

        guard let inputFile = compileFile else {
            return .failure(.processError("No input file"))
        }

        let workingDirectory = inputFile.deletingLastPathComponent()
        let arguments: [String]
        switch engine {
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

        let outcome = await runProcess(
            executable: URL(fileURLWithPath: engine.path),
            arguments: arguments,
            workingDirectory: workingDirectory,
            logURL: workDir.appendingPathComponent("build.log")
        )

        switch outcome {
        case .failure(let error):
            return .failure(error)
        case .success(let exitCode):
            let log = readLog(at: workDir.appendingPathComponent("build.log"))

            guard exitCode == 0 else {
                return .failure(.compilationFailed(log: log.isEmpty ? "LaTeX engine exited with status \(exitCode)." : log))
            }

            // Tectonic names the output after the input file; pdflatex does the same.
            let pdfURL = outDir
                .appendingPathComponent(inputFile.deletingPathExtension().lastPathComponent)
                .appendingPathExtension("pdf")

            guard let data = try? Data(contentsOf: pdfURL), !data.isEmpty else {
                return .failure(.outputNotFound)
            }

            return .success(CompilationOutput(pdfData: data, log: log))
        }
    }

    // MARK: - Process Execution

    /// Runs a process with stdout/stderr redirected to a log file.
    ///
    /// Using files instead of pipes is deliberate: `waitUntilExit()` together
    /// with `Pipe` can deadlock once the child writes more than the 64 KB pipe
    /// buffer (very common with verbose LaTeX logs). File redirection has no
    /// such limit.
    private func runProcess(
        executable: URL,
        arguments: [String],
        workingDirectory: URL,
        logURL: URL
    ) async -> Result<Int32, CompilationError> {
        let timeout = compilationTimeout
        return await withCheckedContinuation { (continuation: CheckedContinuation<Result<Int32, CompilationError>, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let fm = FileManager.default
                fm.createFile(atPath: logURL.path, contents: nil)

                guard let logHandle = try? FileHandle(forWritingTo: logURL) else {
                    continuation.resume(returning: .failure(.processError("Failed to open log file")))
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
                    continuation.resume(returning: .failure(.processError(error.localizedDescription)))
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
                    continuation.resume(returning: .failure(.timedOut(seconds: Int(timeout))))
                } else {
                    continuation.resume(returning: .success(process.terminationStatus))
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
