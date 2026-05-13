import Foundation
import PDFKit

enum ExportError: LocalizedError {
    case noPDF
    case pandocNotFound
    case conversionFailed(String)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .noPDF:
            return "No compiled PDF available. Please compile first (⌘B)."
        case .pandocNotFound:
            return "Pandoc is required for Word export. Click 'Install Pandoc' to set it up."
        case .conversionFailed(let log):
            return "Word conversion failed:\n\(log)"
        case .saveFailed(let msg):
            return "Failed to save file: \(msg)"
        }
    }
}

final class ExportService {

    private let appSupportDir: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("myleaf", isDirectory: true)
    }()

    private var pandocPath: URL? {
        let candidates = [
            appSupportDir.appendingPathComponent("bin/pandoc").path,
            "/opt/homebrew/bin/pandoc",
            "/usr/local/bin/pandoc"
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        // which fallback
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "which pandoc"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let out = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !out.isEmpty,
                   FileManager.default.isExecutableFile(atPath: out) {
                    return URL(fileURLWithPath: out)
                }
            }
        } catch {}

        return nil
    }

    var isPandocInstalled: Bool { pandocPath != nil }

    // MARK: - PDF Export

    func exportPDF(pdfDocument: PDFDocument?, suggestedName: String) throws {
        guard let pdf = pdfDocument, let data = pdf.dataRepresentation() else {
            throw ExportError.noPDF
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = suggestedName.replacingOccurrences(of: ".tex", with: ".pdf")

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try data.write(to: url)
        } catch {
            throw ExportError.saveFailed(error.localizedDescription)
        }
    }

    // MARK: - Word Export

    func exportWord(source: String, suggestedName: String) async throws {
        guard let pandoc = pandocPath else {
            throw ExportError.pandocNotFound
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "docx")].compactMap { $0 }
        panel.nameFieldStringValue = suggestedName.replacingOccurrences(of: ".tex", with: ".docx")

        guard panel.runModal() == .OK, let outputURL = panel.url else { return }

        // Write tex to temp
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("myleaf-export-\(UUID().uuidString)")
        let texFile = tempDir.appendingPathComponent("document.tex")

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try source.write(to: texFile, atomically: true, encoding: .utf8)

        let outPath = outputURL.path

        // Run pandoc
        let result: Result<Void, ExportError> = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = pandoc
                process.arguments = [
                    texFile.path,
                    "-o", outPath,
                    "--from=latex",
                    "--to=docx"
                ]
                process.currentDirectoryURL = tempDir

                let stderrPipe = Pipe()
                process.standardError = stderrPipe
                process.standardOutput = Pipe()

                do {
                    try process.run()
                    process.waitUntilExit()

                    if process.terminationStatus == 0 {
                        continuation.resume(returning: .success(()))
                    } else {
                        let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                        let log = String(data: data, encoding: .utf8) ?? "Unknown error"
                        continuation.resume(returning: .failure(.conversionFailed(log)))
                    }
                } catch {
                    continuation.resume(returning: .failure(.conversionFailed(error.localizedDescription)))
                }
            }
        }

        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)

        if case .failure(let err) = result {
            throw err
        }
    }

    // MARK: - Pandoc Install

    func installPandoc(progress: @escaping (Double, String) -> Void) async throws {
        progress(0, "Fetching Pandoc release info...")

        let apiURL = URL(string: "https://api.github.com/repos/jgm/pandoc/releases/latest")!
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            throw ExportError.conversionFailed("Failed to fetch Pandoc release info")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = json["assets"] as? [[String: Any]] else {
            throw ExportError.conversionFailed("Failed to parse Pandoc release")
        }

        // Find macOS zip
        let arch: String
        #if arch(arm64)
        arch = "arm64-macOS"
        #else
        arch = "x86_64-macOS"
        #endif

        guard let asset = assets.first(where: { ($0["name"] as? String)?.contains(arch) == true && ($0["name"] as? String)?.hasSuffix(".zip") == true }),
              let urlStr = asset["browser_download_url"] as? String,
              let downloadURL = URL(string: urlStr) else {
            throw ExportError.conversionFailed("No compatible Pandoc binary found")
        }

        progress(0.1, "Downloading Pandoc...")

        let (localURL, dlResp) = try await URLSession.shared.download(from: downloadURL)
        guard let dlHttp = dlResp as? HTTPURLResponse, dlHttp.statusCode == 200 else {
            throw ExportError.conversionFailed("Pandoc download failed")
        }

        let zipDest = FileManager.default.temporaryDirectory.appendingPathComponent("pandoc-download.zip")
        try? FileManager.default.removeItem(at: zipDest)
        try FileManager.default.moveItem(at: localURL, to: zipDest)

        progress(0.6, "Extracting Pandoc...")

        let binDir = appSupportDir.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)

        // Unzip to temp, then find the pandoc binary
        let extractDir = FileManager.default.temporaryDirectory.appendingPathComponent("pandoc-extract-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-o", zipDest.path, "-d", extractDir.path]
        unzip.standardOutput = Pipe()
        unzip.standardError = Pipe()
        try unzip.run()
        unzip.waitUntilExit()

        guard unzip.terminationStatus == 0 else {
            throw ExportError.conversionFailed("Failed to extract Pandoc archive")
        }

        progress(0.8, "Installing...")

        // Find the pandoc binary recursively
        let pandocBin = findFile(named: "pandoc", in: extractDir)
        guard let pandocBin = pandocBin else {
            throw ExportError.conversionFailed("Pandoc binary not found in archive")
        }

        let destBin = binDir.appendingPathComponent("pandoc")
        try? FileManager.default.removeItem(at: destBin)
        try FileManager.default.copyItem(at: pandocBin, to: destBin)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destBin.path)

        // Cleanup
        try? FileManager.default.removeItem(at: zipDest)
        try? FileManager.default.removeItem(at: extractDir)

        progress(1.0, "Pandoc installed successfully!")
    }

    private func findFile(named name: String, in dir: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: nil) else { return nil }
        while let url = enumerator.nextObject() as? URL {
            if url.lastPathComponent == name && fm.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }
}
