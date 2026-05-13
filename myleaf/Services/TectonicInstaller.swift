import Foundation

@Observable
final class TectonicInstaller {

    var isInstalling = false
    var progress: Double = 0
    var statusMessage = ""

    private let appSupportDir: URL = {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("myleaf", isDirectory: true)
    }()

    var binDir: URL { appSupportDir.appendingPathComponent("bin", isDirectory: true) }
    var tectonicPath: URL { binDir.appendingPathComponent("tectonic") }

    var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: tectonicPath.path)
    }

    // MARK: - Install

    func install() async throws {
        isInstalling = true
        progress = 0
        statusMessage = "Fetching latest release info..."

        defer { isInstalling = false }

        // 1. Get download URL from GitHub API
        let downloadURL = try await fetchDownloadURL()

        // 2. Download the tar.gz
        statusMessage = "Downloading Tectonic..."
        let archivePath = try await downloadFile(from: downloadURL)

        // 3. Extract
        statusMessage = "Extracting..."
        progress = 0.8
        try extractTectonic(archive: archivePath)

        // 4. Verify
        guard isInstalled else {
            throw InstallerError.extractionFailed("tectonic binary not found after extraction")
        }

        progress = 1.0
        statusMessage = "Tectonic installed successfully!"
    }

    // MARK: - GitHub Release

    private func fetchDownloadURL() async throws -> URL {
        let apiURL = URL(string: "https://api.github.com/repos/tectonic-typesetting/tectonic/releases/latest")!
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            throw InstallerError.networkError("Failed to fetch release info")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = json["assets"] as? [[String: Any]] else {
            throw InstallerError.parseError
        }

        // Detect architecture
        let arch: String
        #if arch(arm64)
        arch = "aarch64-apple-darwin"
        #else
        arch = "x86_64-apple-darwin"
        #endif

        guard let asset = assets.first(where: { ($0["name"] as? String)?.contains(arch) == true }),
              let urlStr = asset["browser_download_url"] as? String,
              let url = URL(string: urlStr) else {
            throw InstallerError.noMatchingAsset
        }

        return url
    }

    // MARK: - Download

    private func downloadFile(from url: URL) async throws -> URL {
        let (localURL, response) = try await URLSession.shared.download(from: url)
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            throw InstallerError.networkError("Download failed")
        }

        // Move to a known temp location (the download URL is ephemeral)
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("tectonic-download.tar.gz")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: localURL, to: dest)

        progress = 0.7
        return dest
    }

    // MARK: - Extract

    private func extractTectonic(archive: URL) throws {
        let fm = FileManager.default

        // Ensure bin directory exists
        try fm.createDirectory(at: binDir, withIntermediateDirectories: true)

        // Extract using tar
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xzf", archive.path, "-C", binDir.path]
        process.currentDirectoryURL = binDir

        let pipe = Pipe()
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8) ?? "Unknown error"
            throw InstallerError.extractionFailed(errMsg)
        }

        // Make executable
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tectonicPath.path)

        // Cleanup archive
        try? fm.removeItem(at: archive)
    }
}

// MARK: - Errors

enum InstallerError: LocalizedError {
    case networkError(String)
    case parseError
    case noMatchingAsset
    case extractionFailed(String = "")

    var errorDescription: String? {
        switch self {
        case .networkError(let msg): return "Network error: \(msg)"
        case .parseError: return "Failed to parse GitHub release info"
        case .noMatchingAsset: return "No compatible Tectonic binary found for this platform"
        case .extractionFailed(let msg): return "Extraction failed\(msg.isEmpty ? "" : ": \(msg)")"
        }
    }
}
