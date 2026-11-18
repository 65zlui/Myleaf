import Foundation

@Observable
@MainActor
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
        guard !isInstalling else { return }

        isInstalling = true
        progress = 0
        statusMessage = "Fetching latest release info..."

        defer {
            isInstalling = false
        }

        // 1. Get download URL from GitHub API
        let downloadURL = try await fetchDownloadURL()

        // 2. Download the tar.gz
        progress = 0.15
        statusMessage = "Downloading Tectonic..."
        let archivePath = try await downloadFile(from: downloadURL)
        defer { try? FileManager.default.removeItem(at: archivePath) }

        // 3. Extract off the main actor — tar can take a moment on slower disks
        progress = 0.75
        statusMessage = "Extracting..."
        let destinationBin = binDir
        let archive = archivePath
        try await Task.detached(priority: .userInitiated) {
            try Self.extractTectonic(archive: archive, binDir: destinationBin)
        }.value

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
        request.timeoutInterval = 30

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
        var request = URLRequest(url: url)
        request.timeoutInterval = 300

        let (localURL, response) = try await URLSession.shared.download(for: request)
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            throw InstallerError.networkError("Download failed with HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }

        // Move to a known temp location (the download URL is ephemeral)
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("tectonic-download.tar.gz")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: localURL, to: dest)

        progress = 0.7
        return dest
    }

    // MARK: - Extract

    /// Extracts the archive into a temporary directory, then copies the
    /// `tectonic` binary into `binDir`. Release archives have used both a flat
    /// layout and a version-named subdirectory, so the binary is located
    /// recursively instead of assuming a fixed path.
    nonisolated private static func extractTectonic(archive: URL, binDir: URL) throws {
        let fm = FileManager.default
        let extractDir = fm.temporaryDirectory
            .appendingPathComponent("tectonic-extract-\(UUID().uuidString)")
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: extractDir) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xzf", archive.path, "-C", extractDir.path]

        let logURL = extractDir.appendingPathComponent("tar.log")
        fm.createFile(atPath: logURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logURL)
        defer { try? logHandle.close() }
        process.standardError = logHandle
        process.standardOutput = logHandle

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errData = (try? Data(contentsOf: logURL)) ?? Data()
            let errMsg = String(data: errData, encoding: .utf8) ?? "Unknown error"
            throw InstallerError.extractionFailed(errMsg)
        }

        guard let binary = findFile(named: "tectonic", in: extractDir) else {
            throw InstallerError.extractionFailed("tectonic binary not found in archive")
        }

        try fm.createDirectory(at: binDir, withIntermediateDirectories: true)
        let destination = binDir.appendingPathComponent("tectonic")
        try? fm.removeItem(at: destination)
        try fm.copyItem(at: binary, to: destination)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
    }

    nonisolated private static func findFile(named name: String, in dir: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.isExecutableKey]) else {
            return nil
        }
        while let url = enumerator.nextObject() as? URL {
            if url.lastPathComponent == name, fm.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        return nil
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
