import Testing
import Foundation
@testable import myleaf

struct UpdateVersionTests {

    @Test func comparesNumericComponents() {
        #expect(UpdateChecker.compareVersions("0.2.0", "0.2") == .orderedSame)
        #expect(UpdateChecker.compareVersions("0.2", "0.2.0") == .orderedSame)
        #expect(UpdateChecker.compareVersions("0.3", "0.2.9") == .orderedDescending)
        #expect(UpdateChecker.compareVersions("0.1.9", "0.2") == .orderedAscending)
        #expect(UpdateChecker.compareVersions("1.0.10", "1.0.9") == .orderedDescending)
    }

    @Test func stripsVersionPrefix() {
        #expect(UpdateChecker.compareVersions("v0.2.1", "0.2") == .orderedDescending)
        #expect(UpdateChecker.compareVersions("V1.0", "1.0.0") == .orderedSame)
    }

    @Test func handlesUnparsableVersions() {
        #expect(UpdateChecker.compareVersions("unknown", "unknown") == .orderedSame)
        #expect(UpdateChecker.compareVersions("unknown", "0.1") == .orderedAscending)
        #expect(UpdateChecker.compareVersions("0.1", "unknown") == .orderedDescending)
    }
}

struct UpdateReleaseDecodingTests {

    private func json(assets: String) -> Data {
        """
        {
          "tag_name": "v0.3.0",
          "name": "myleaf 0.3",
          "body": "Search improvements",
          "html_url": "https://github.com/65zlui/Myleaf/releases/tag/v0.3.0",
          "assets": [\(assets)]
        }
        """.data(using: .utf8)!
    }

    @Test func decodesReleaseAndSelectsInstallerPackage() throws {
        let data = json(assets: """
            {"name": "myleaf-uninstaller-0.3.pkg", "browser_download_url": "https://example.com/uninstaller.pkg"},
            {"name": "myleaf-0.3.dmg", "browser_download_url": "https://example.com/myleaf-0.3.dmg"},
            {"name": "myleaf-0.3.pkg", "browser_download_url": "https://example.com/myleaf-0.3.pkg"},
            {"name": "SHA256SUMS.txt", "browser_download_url": "https://example.com/SHA256SUMS.txt"}
        """)

        let release = try UpdateChecker.decodeRelease(data)
        #expect(release.version == "0.3.0")
        #expect(release.displayName == "myleaf 0.3")
        #expect(release.notes == "Search improvements")
        #expect(release.packageName == "myleaf-0.3.pkg")
        #expect(release.packageURL.absoluteString == "https://example.com/myleaf-0.3.pkg")
        #expect(release.pageURL.absoluteString.hasSuffix("/v0.3.0"))
    }

    @Test func rejectsReleaseWithoutInstallerPackage() {
        let data = json(assets: """
            {"name": "myleaf-uninstaller-0.3.pkg", "browser_download_url": "https://example.com/uninstaller.pkg"},
            {"name": "myleaf-0.3.zip", "browser_download_url": "https://example.com/myleaf-0.3.zip"}
        """)

        #expect(throws: UpdateError.self) {
            try UpdateChecker.decodeRelease(data)
        }
    }
}
