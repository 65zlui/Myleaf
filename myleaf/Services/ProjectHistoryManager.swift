import Foundation

/// Manages recent project history using UserDefaults.
/// File path: ~/Library/Preferences/com.myleaf.app.plist (via UserDefaults.standard)
@Observable
@MainActor
final class ProjectHistoryManager {
    static let shared = ProjectHistoryManager()

    private let maxHistoryCount = 10
    private let historyKey = "recentProjectPaths"
    private let autoSaveKey = "autoSaveEnabled"

    /// Recent project file paths, most recent first
    var recentProjects: [URL] {
        let paths = UserDefaults.standard.stringArray(forKey: historyKey) ?? []
        return paths.compactMap { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Whether the user has any valid project history
    var hasHistory: Bool {
        !recentProjects.isEmpty
    }

    /// The most recently opened project
    var lastProject: URL? {
        recentProjects.first
    }

    /// Auto-save toggle, default ON
    var isAutoSaveEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: autoSaveKey) == nil {
                return true // default ON
            }
            return UserDefaults.standard.bool(forKey: autoSaveKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: autoSaveKey)
        }
    }

    private init() {}

    /// Record a project as recently opened
    func recordProject(_ url: URL) {
        var paths = UserDefaults.standard.stringArray(forKey: historyKey) ?? []
        let path = url.path

        // Remove if already exists (will re-add at top)
        paths.removeAll { $0 == path }

        // Insert at front
        paths.insert(path, at: 0)

        // Limit count
        if paths.count > maxHistoryCount {
            paths = Array(paths.prefix(maxHistoryCount))
        }

        UserDefaults.standard.set(paths, forKey: historyKey)
    }

    /// Remove a project from history
    func removeProject(_ url: URL) {
        var paths = UserDefaults.standard.stringArray(forKey: historyKey) ?? []
        paths.removeAll { $0 == url.path }
        UserDefaults.standard.set(paths, forKey: historyKey)
    }

    /// Clear all history
    func clearHistory() {
        UserDefaults.standard.removeObject(forKey: historyKey)
    }
}
