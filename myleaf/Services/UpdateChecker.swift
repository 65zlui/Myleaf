import Foundation
import AppKit
import Darwin
import Observation

/// A published release discovered on GitHub.
struct UpdateRelease: Equatable, Identifiable {
    let version: String          // "0.3.0"
    let displayName: String      // "myleaf 0.3"
    let notes: String
    let pageURL: URL
    let packageURL: URL          // the installer .pkg asset
    let packageName: String      // "myleaf-0.3.pkg"

    var id: String { version }
}

enum UpdateError: LocalizedError {
    case network(String)
    case noInstallerAsset
    case installerOpenFailed

    var errorDescription: String? {
        switch self {
        case .network(let message):
            return "Update check failed: \(message)"
        case .noInstallerAsset:
            return "The latest release has no installer package."
        case .installerOpenFailed:
            return "The downloaded installer could not be opened."
        }
    }
}

/// Checks the project's GitHub releases and downloads the installer for a
/// newer version. It deliberately stops at opening the .pkg: the final install
/// (and the admin authorization macOS requires for /Applications) is left to
/// Installer.app, so the app never silently replaces its own bundle.
@Observable
@MainActor
final class UpdateChecker {
    enum State: Equatable {
        case idle
        case checking
        case upToDate(current: String)
        case available(UpdateRelease)
        case downloading(version: String)
        case installerOpened(version: String)
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var lastChecked: Date?

    private let repository: String
    private let session: URLSession

    init(repository: String = "65zlui/Myleaf", session: URLSession = .shared) {
        self.repository = repository
        self.session = session
    }

    /// True while a check or download is in flight.
    var isBusy: Bool {
        switch state {
        case .checking, .downloading: return true
        default: return false
        }
    }

    // MARK: - Check

    func check(currentVersion: String) async {
        guard !isBusy else { return }
        state = .checking

        do {
            guard let apiURL = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
                throw UpdateError.network("Invalid API URL.")
            }

            var request = URLRequest(url: apiURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("myleaf/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 20

            let (data, response) = try await session.data(for: request)
            try Self.validate(response)

            let release = try Self.decodeRelease(data)
            lastChecked = Date()

            if Self.compareVersions(release.version, currentVersion) == .orderedDescending {
                state = .available(release)
            } else {
                state = .upToDate(current: currentVersion)
            }
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    // MARK: - Download

    /// Downloads the release's .pkg and opens it with Installer.app. The
    /// package's preinstall script quits myleaf before replacing it.
    func downloadAndOpenInstaller(for release: UpdateRelease, currentVersion: String) async {
        guard !isBusy else { return }
        state = .downloading(version: release.version)

        do {
            var request = URLRequest(url: release.packageURL)
            request.setValue("myleaf/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 300

            let (temporaryURL, response) = try await session.download(for: request)
            try Self.validate(response)

            let fileManager = FileManager.default
            let destination = fileManager.temporaryDirectory
                .appendingPathComponent(release.packageName)
            try? fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: temporaryURL, to: destination)
            Self.removeQuarantine(from: destination)

            guard NSWorkspace.shared.open(destination) else {
                throw UpdateError.installerOpenFailed
            }
            state = .installerOpened(version: release.version)
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    // MARK: - GitHub payload

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let name: String?
        let body: String?
        let htmlURL: URL
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case body
            case htmlURL = "html_url"
            case assets
        }
    }

    nonisolated static func decodeRelease(_ data: Data) throws -> UpdateRelease {
        let github = try JSONDecoder().decode(GitHubRelease.self, from: data)
        let version = github.tagName.hasPrefix("v")
            ? String(github.tagName.dropFirst())
            : github.tagName

        guard let installer = github.assets.first(where: {
            $0.name.hasSuffix(".pkg") && !$0.name.localizedCaseInsensitiveContains("uninstaller")
        }) else {
            throw UpdateError.noInstallerAsset
        }

        return UpdateRelease(
            version: version,
            displayName: github.name ?? "myleaf \(version)",
            notes: github.body ?? "",
            pageURL: github.htmlURL,
            packageURL: installer.browserDownloadURL,
            packageName: installer.name
        )
    }

    // MARK: - Helpers

    nonisolated static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw UpdateError.network("Invalid server response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw UpdateError.network("GitHub returned HTTP \(http.statusCode).")
        }
    }

    /// Numeric-aware comparison, so "0.3" > "0.2.9" and "0.2" == "0.2.0".
    nonisolated static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = versionComponents(lhs)
        let right = versionComponents(rhs)

        if left.isEmpty && right.isEmpty { return .orderedSame }
        if left.isEmpty { return .orderedAscending }
        if right.isEmpty { return .orderedDescending }

        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a < b ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    nonisolated static func versionComponents(_ version: String) -> [Int] {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = trimmed.hasPrefix("v") || trimmed.hasPrefix("V")
            ? String(trimmed.dropFirst())
            : trimmed
        return withoutPrefix
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
    }

    /// Downloaded packages normally have no quarantine flag when fetched with
    /// URLSession, but strip it defensively so Installer never refuses them.
    nonisolated private static func removeQuarantine(from url: URL) {
        let name = "com.apple.quarantine"
        if getxattr(url.path, name, nil, 0, 0, 0) > 0 {
            removexattr(url.path, name, 0)
        }
    }

    nonisolated private static func message(for error: Error) -> String {
        if let updateError = error as? UpdateError {
            return updateError.errorDescription ?? "Update failed."
        }
        return error.localizedDescription
    }
}
