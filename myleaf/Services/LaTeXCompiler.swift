import Foundation

enum CompilationError: LocalizedError {
    case engineNotFound
    case compilationFailed(log: String)
    case outputNotFound
    case processError(String)

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

final class LaTeXCompiler {

    private(set) var engine: TeXEngine?
    private var previousTempDir: URL?

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

    func compile(source: String) async -> Result<URL, CompilationError> {
        guard let engine = engine else {
            return .failure(.engineNotFound)
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("myleaf-\(UUID().uuidString)")
        let texFile = tempDir.appendingPathComponent("document.tex")
        let pdfFile = tempDir.appendingPathComponent("document.pdf")

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try source.write(to: texFile, atomically: true, encoding: .utf8)
        } catch {
            return .failure(.processError("Failed to write temp files: \(error.localizedDescription)"))
        }

        let currentEngine = engine
        let result: Result<URL, CompilationError> = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.currentDirectoryURL = tempDir

                switch currentEngine {
                case .tectonic(let url):
                    process.executableURL = url
                    process.arguments = ["document.tex"]
                case .pdflatex(let url):
                    process.executableURL = url
                    process.arguments = [
                        "-interaction=nonstopmode",
                        "-halt-on-error",
                        "-output-directory", tempDir.path,
                        "document.tex"
                    ]
                }

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let log = String(data: stdoutData, encoding: .utf8) ?? ""
                    let errLog = String(data: stderrData, encoding: .utf8) ?? ""

                    if process.terminationStatus == 0 {
                        if FileManager.default.fileExists(atPath: pdfFile.path) {
                            continuation.resume(returning: .success(pdfFile))
                        } else {
                            continuation.resume(returning: .failure(.outputNotFound))
                        }
                    } else {
                        let fullLog = [log, errLog].filter { !$0.isEmpty }.joined(separator: "\n")
                        continuation.resume(returning: .failure(.compilationFailed(log: fullLog)))
                    }
                } catch {
                    continuation.resume(returning: .failure(.processError(error.localizedDescription)))
                }
            }
        }

        // Cleanup previous temp dir
        if let prev = previousTempDir {
            try? FileManager.default.removeItem(at: prev)
        }
        previousTempDir = tempDir

        return result
    }
}
