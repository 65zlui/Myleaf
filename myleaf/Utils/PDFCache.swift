import Foundation

/// Stores the latest compiled PDFs on disk so PDFKit can open them file-backed
/// instead of keeping a full `Data` copy in memory. Keeps only a few files.
enum PDFCache {

    static let maxFiles = 3

    static var directory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches
            .appendingPathComponent("myleaf", isDirectory: true)
            .appendingPathComponent("pdfs", isDirectory: true)
    }

    /// Copies a freshly compiled PDF into the cache and returns its URL.
    static func store(_ source: URL) -> URL? {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent("preview-\(UUID().uuidString).pdf")

            do {
                try fm.moveItem(at: source, to: destination)
            } catch {
                try fm.copyItem(at: source, to: destination)
            }

            prune()
            return destination
        } catch {
            return nil
        }
    }

    static func remove(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Keeps the most recently modified `keeping` PDFs.
    static func prune(keeping: Int = maxFiles) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let pdfs = files
            .filter { $0.pathExtension == "pdf" }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left < right
            }

        for url in pdfs.dropLast(keeping) {
            try? fm.removeItem(at: url)
        }
    }

    static func byteCount(of url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
    }
}
