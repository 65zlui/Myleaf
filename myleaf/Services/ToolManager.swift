import Foundation

enum ManagedTool: String, CaseIterable, Identifiable {
    case tectonic
    case pandoc

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tectonic: return "Tectonic"
        case .pandoc: return "Pandoc"
        }
    }

    var description: String {
        switch self {
        case .tectonic: return "LaTeX typesetting engine (~25 MB)"
        case .pandoc: return "Document format converter for Word export (~110 MB)"
        }
    }

    var icon: String {
        switch self {
        case .tectonic: return "hammer.fill"
        case .pandoc: return "doc.richtext.fill"
        }
    }

    var binaryName: String { rawValue }
}

@Observable
@MainActor
final class ToolManager {

    static let shared = ToolManager()

    var toolStates: [ManagedTool: ToolState] = [:]
    var isWorking = false
    var workingTool: ManagedTool?
    var progress: Double = 0
    var statusMessage = ""

    private let fm = FileManager.default

    private let appSupportDir: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("myleaf", isDirectory: true)
    }()

    var binDir: URL { appSupportDir.appendingPathComponent("bin", isDirectory: true) }

    private init() {
        refreshAll()
    }

    // MARK: - Status

    func refreshAll() {
        for tool in ManagedTool.allCases {
            toolStates[tool] = checkState(tool)
        }
    }

    func isInstalled(_ tool: ManagedTool) -> Bool {
        if case .installed = toolStates[tool] { return true }
        return false
    }

    private func binaryPath(_ tool: ManagedTool) -> URL {
        binDir.appendingPathComponent(tool.binaryName)
    }

    private func checkState(_ tool: ManagedTool) -> ToolState {
        let path = binaryPath(tool)
        guard fm.isExecutableFile(atPath: path.path) else {
            return .notInstalled
        }

        // Get file size
        let size = (try? fm.attributesOfItem(atPath: path.path)[.size] as? Int64) ?? 0

        // Try to get version
        let version = queryVersion(tool)

        return .installed(version: version, size: size, path: path.path)
    }

    private func queryVersion(_ tool: ManagedTool) -> String? {
        let path = binaryPath(tool)
        guard fm.isExecutableFile(atPath: path.path) else { return nil }

        let process = Process()
        process.executableURL = path
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) {
                // Take first line only
                return output.components(separatedBy: .newlines).first
            }
        } catch {}
        return nil
    }

    // MARK: - Uninstall

    func uninstall(_ tool: ManagedTool) throws {
        let path = binaryPath(tool)

        if fm.fileExists(atPath: path.path) {
            try fm.removeItem(at: path)
        }

        // For tectonic, also clean up its cache
        if tool == .tectonic {
            cleanTectonicCache()
        }

        // Clean up empty bin dir
        if let contents = try? fm.contentsOfDirectory(atPath: binDir.path), contents.isEmpty {
            try? fm.removeItem(at: binDir)
        }

        // Clean up empty app support dir
        if let contents = try? fm.contentsOfDirectory(atPath: appSupportDir.path), contents.isEmpty {
            try? fm.removeItem(at: appSupportDir)
        }

        toolStates[tool] = .notInstalled
    }

    private func cleanTectonicCache() {
        // Tectonic stores its cache in ~/Library/Caches/Tectonic
        let cacheDir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Tectonic")
        if let dir = cacheDir, fm.fileExists(atPath: dir.path) {
            try? fm.removeItem(at: dir)
        }

        // Also check XDG-style cache path
        let xdgCache = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/Tectonic")
        if fm.fileExists(atPath: xdgCache.path) {
            try? fm.removeItem(at: xdgCache)
        }
    }

    /// Calculate total disk space used by all managed tools
    func totalDiskUsage() -> Int64 {
        var total: Int64 = 0
        for (_, state) in toolStates {
            if case .installed(_, let size, _) = state {
                total += size
            }
        }
        // Add tectonic cache size
        total += tectonicCacheSize()
        return total
    }

    func tectonicCacheSize() -> Int64 {
        var total: Int64 = 0
        let cacheDirs = [
            fm.urls(for: .cachesDirectory, in: .userDomainMask).first?
                .appendingPathComponent("Tectonic"),
            fm.homeDirectoryForCurrentUser
                .appendingPathComponent(".cache/Tectonic")
        ].compactMap { $0 }

        for dir in cacheDirs {
            if let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) {
                while let url = enumerator.nextObject() as? URL {
                    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    total += Int64(size)
                }
            }
        }
        return total
    }
}

// MARK: - ToolState

enum ToolState: Equatable {
    case notInstalled
    case installed(version: String?, size: Int64, path: String)

    static func == (lhs: ToolState, rhs: ToolState) -> Bool {
        switch (lhs, rhs) {
        case (.notInstalled, .notInstalled): return true
        case (.installed(let v1, let s1, let p1), .installed(let v2, let s2, let p2)):
            return v1 == v2 && s1 == s2 && p1 == p2
        default: return false
        }
    }
}

// MARK: - Formatting

extension Int64 {
    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: self)
    }
}
