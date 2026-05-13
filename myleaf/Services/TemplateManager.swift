import Foundation

// MARK: - Template Metadata (decoded from templates.json)

private struct TemplateMetadata: Decodable {
    let id: String
    let name: String
    let subtitle: String
    let category: String
    let file: String
}

// MARK: - TemplateManager

final class TemplateManager {

    static let shared = TemplateManager()

    /// Whether templates are loaded from the source directory (dev) or app bundle (production).
    private let isDevelopmentMode: Bool

    /// The base URL for loading templates (source dir or bundle resources).
    private let templatesBaseURL: URL

    var templatesDir: URL { templatesBaseURL }

    /// All templates loaded from bundle resources.
    private(set) var allTemplates: [Template] = []

    internal init() {
        let sourceURL = URL(fileURLWithPath: "/Users/zhangrui/Desktop/Project/macos/myleaf/myleaf/myleaf/Resources/Templates")
        if FileManager.default.fileExists(atPath: sourceURL.path) {
            isDevelopmentMode = true
            templatesBaseURL = sourceURL
        } else {
            isDevelopmentMode = false
            templatesBaseURL = Bundle.main.resourceURL ?? sourceURL
        }
        allTemplates = loadTemplates()
    }

    func templates(for category: TemplateCategory) -> [Template] {
        allTemplates.filter { $0.category == category }
    }

    // MARK: - Loading

    private func loadTemplates() -> [Template] {
        let jsonURL = templatesBaseURL.appendingPathComponent("templates.json")

        // Try to load JSON data
        let jsonData: Data
        do {
            jsonData = try Data(contentsOf: jsonURL)
        } catch {
            return []
        }

        // Decode manifest
        let manifest: TemplateManifest
        do {
            manifest = try JSONDecoder().decode(TemplateManifest.self, from: jsonData)
        } catch {
            return []
        }

        var templates: [Template] = []
        for meta in manifest.templates {
            let fileURL: URL
            if isDevelopmentMode {
                // Dev mode: files are in Templates/subdir/file.tex
                fileURL = templatesBaseURL.appendingPathComponent(meta.file)
            } else {
                // Production mode: files are at bundle root as file.tex (strip directory)
                let fileName = (meta.file as NSString).lastPathComponent
                fileURL = templatesBaseURL.appendingPathComponent(fileName)
            }

            guard let category = TemplateCategory(rawValue: meta.category) else {
                continue
            }
            do {
                let content = try String(contentsOf: fileURL, encoding: .utf8)
                let template = Template(
                    id: meta.id,
                    name: meta.name,
                    subtitle: meta.subtitle,
                    category: category,
                    content: content
                )
                templates.append(template)
            } catch {
                continue
            }
        }
        return templates
    }
}

// MARK: - Manifest (top-level JSON object)

private struct TemplateManifest: Decodable {
    let templates: [TemplateMetadata]
}
