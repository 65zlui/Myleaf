import SwiftUI
import PDFKit
import UniformTypeIdentifiers

@Observable
@MainActor
final class EditorViewModel {

    var document = LaTeXDocument()
    var pdfDocument: PDFDocument?
    var isCompiling = false
    var errorMessage: String?
    var compilerStatus: CompilerStatus = .checking
    var showTemplatePicker = false
    var showSettings = false
    var showWelcome = false
    var showBibTeXImport = false
    var isInstallingPandoc = false
    var pandocInstallProgress: Double = 0
    var pandocInstallStatus = ""

    let installer = TectonicInstaller()
    let exportService = ExportService()
    let toolManager = ToolManager.shared
    let historyManager = ProjectHistoryManager.shared
    private let compiler = LaTeXCompiler()
    private var savedText: String = ""
    private var autoSaveTask: Task<Void, Never>?

    var windowTitle: String {
        let name = document.fileURL?.lastPathComponent ?? "Untitled"
        let modified = document.sourceText != savedText ? " - Edited" : ""
        return "\(name)\(modified)"
    }

    private var suggestedFileName: String {
        document.fileURL?.lastPathComponent ?? "document.tex"
    }

    init() {
        savedText = document.sourceText
        Task { [weak self] in
            await self?.detectCompiler()
        }
        // Launch behavior: check project history
        if historyManager.hasHistory, let lastURL = historyManager.lastProject {
            loadFile(url: lastURL)
        } else {
            showWelcome = true
        }
        // Start auto-save if enabled
        startAutoSaveIfNeeded()
    }

    deinit {
        print("[Deinit] EditorViewModel")
    }

    // MARK: - Compiler Detection

    func detectCompiler() async {
        compilerStatus = .checking
        let result = await Task.detached { [compiler] in
            compiler.detectEngine()
        }.value

        if let engine = result {
            compilerStatus = .ready(engine: engine)
        } else {
            compilerStatus = .notFound
        }
    }

    // MARK: - Install Tectonic

    func installTectonic() {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.installer.install()
                self.toolManager.refreshAll()
                await self.detectCompiler()
            } catch {
                self.errorMessage = "Installation failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Templates

    func applyTemplate(_ template: Template) {
        document = LaTeXDocument(sourceText: template.content)
        pdfDocument = nil
        errorMessage = nil
        savedText = ""
        showWelcome = false
    }

    // MARK: - Tool Management

    func onToolUninstalled() {
        toolManager.refreshAll()
        Task { [weak self] in
            await self?.detectCompiler()
        }
    }

    // MARK: - BibTeX Import

    func showBibTeXImportSheet() {
        showBibTeXImport = true
    }

    func insertCitations(_ entries: [BibTeXEntry]) {
        guard !entries.isEmpty else { return }
        let citeKeys = entries.map { $0.id }.joined(separator: ", ")
        let citeText = "\\cite{\(citeKeys)}"

        // Try to insert before \end{document}, otherwise append
        let endDocPattern = "\\end{document}"
        if let range = document.sourceText.range(of: endDocPattern) {
            let insertionPoint = document.sourceText.distance(from: document.sourceText.startIndex, to: range.lowerBound)
            // Insert on a new line before \end{document}
            var newText = document.sourceText
            let prefix = newText[..<range.lowerBound]
            let suffix = newText[range.lowerBound...]
            // Add newline if the line before isn't empty
            let needsNewline = !prefix.hasSuffix("\n")
            newText = String(prefix) + (needsNewline ? "\n" : "") + citeText + "\n" + String(suffix)
            document.sourceText = newText
        } else {
            // Append to end
            let needsNewline = !document.sourceText.hasSuffix("\n")
            document.sourceText += (needsNewline ? "\n" : "") + citeText + "\n"
        }

        showBibTeXImport = false
    }

    // MARK: - File Operations

    /// Load a file from URL (used by history auto-open and open panel)
    func loadFile(url: URL) {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            document = LaTeXDocument(sourceText: content, fileURL: url)
            savedText = content
            pdfDocument = nil
            errorMessage = nil
            historyManager.recordProject(url)
        } catch {
            // File no longer accessible, remove from history
            historyManager.removeProject(url)
            showWelcome = true
        }
    }

    func newDocument() {
        document = LaTeXDocument()
        pdfDocument = nil
        errorMessage = nil
        savedText = document.sourceText
        showWelcome = false
    }

    func newFromTemplate() {
        showTemplatePicker = true
    }

    func openDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "tex")].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        loadFile(url: url)
        showWelcome = false
    }

    func saveDocument() {
        if let url = document.fileURL {
            writeToFile(url: url)
        } else {
            saveDocumentAs()
        }
    }

    func saveDocumentAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "tex")].compactMap { $0 }
        panel.nameFieldStringValue = document.fileURL?.lastPathComponent ?? "document.tex"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        document.fileURL = url
        writeToFile(url: url)
    }

    private func writeToFile(url: URL) {
        do {
            try document.sourceText.write(to: url, atomically: true, encoding: .utf8)
            savedText = document.sourceText
            historyManager.recordProject(url)
        } catch {
            errorMessage = "Failed to save file: \(error.localizedDescription)"
        }
    }

    // MARK: - Auto-Save
    // Auto-save writes to the document's current fileURL (shown in window title bar).
    // If the document has never been saved (no fileURL), auto-save will not trigger.
    // Interval: 30 seconds. Toggle available in Settings (default: ON).
    // Preference stored in: UserDefaults key "autoSaveEnabled"

    func startAutoSaveIfNeeded() {
        autoSaveTask?.cancel()
        guard historyManager.isAutoSaveEnabled else { return }

        autoSaveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                guard !Task.isCancelled else { break }
                await self?.performAutoSave()
            }
        }
    }

    func stopAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = nil
    }

    private func performAutoSave() {
        guard historyManager.isAutoSaveEnabled,
              let url = document.fileURL,
              document.sourceText != savedText else { return }
        writeToFile(url: url)
    }

    // MARK: - Export

    func exportPDF() {
        do {
            try exportService.exportPDF(pdfDocument: pdfDocument, suggestedName: suggestedFileName)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportWord() {
        if !exportService.isPandocInstalled {
            errorMessage = ExportError.pandocNotFound.errorDescription
            return
        }
        Task { [weak self] in
            do {
                try await self?.exportService.exportWord(source: self?.document.sourceText ?? "", suggestedName: self?.suggestedFileName ?? "document.tex")
            } catch {
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    func installPandoc() {
        isInstallingPandoc = true
        pandocInstallProgress = 0
        pandocInstallStatus = ""

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.exportService.installPandoc { [weak self] progress, status in
                    Task { @MainActor in
                        self?.pandocInstallProgress = progress
                        self?.pandocInstallStatus = status
                    }
                }
                self.isInstallingPandoc = false
                self.pandocInstallStatus = "Pandoc installed!"
                self.toolManager.refreshAll()
            } catch {
                self.isInstallingPandoc = false
                self.errorMessage = "Pandoc install failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Compilation

    func compile() {
        guard !isCompiling else { return }

        if case .notFound = compilerStatus {
            errorMessage = CompilationError.engineNotFound.errorDescription
            return
        }

        isCompiling = true
        errorMessage = nil

        Task { [weak self] in
            guard let self else { return }
            let result = await self.compiler.compile(source: self.document.sourceText)

            switch result {
            case .success(let pdfURL):
                if let pdf = PDFDocument(url: pdfURL) {
                    self.pdfDocument = pdf
                } else {
                    self.errorMessage = "Failed to load generated PDF."
                }
            case .failure(let error):
                self.errorMessage = error.errorDescription
            }

            self.isCompiling = false
        }
    }
}
