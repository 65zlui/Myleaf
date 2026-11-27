import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import OSLog

private let compileLogger = Logger(subsystem: "com.65zlui.myleaf", category: "build")

@Observable
@MainActor
final class EditorViewModel {

    var document = LaTeXDocument()
    var pdfDocument: PDFDocument?
    private(set) var pdfCacheURL: URL?
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

    // Build log for the most recent compilation (success or failure).
    var lastBuildLog: String?
    var lastBuildLogFile: URL?
    var lastCompilationDuration: TimeInterval?
    var compilationPhase = ""
    var showBuildLog = false

    /// Recent compile runs for the Performance panel (newest last).
    private(set) var compilationHistory: [CompilationRecord] = []

    let installer = TectonicInstaller()
    let exportService = ExportService()
    /// Lazy: ToolManager probes installed tool versions. Do not initialize it
    /// during app launch; Settings or an install action will access it later.
    var toolManager: ToolManager { ToolManager.shared }
    let historyManager = ProjectHistoryManager.shared
    private let compiler: any LaTeXCompiling
    private var savedText: String = ""
    private var autoSaveTask: Task<Void, Never>?

    /// Identifies the compile that is still allowed to update the UI. Replaced
    /// when a compile starts and cleared when the document changes, so a slow
    /// build of a previous document cannot overwrite the new document's state.
    private var activeCompileID: UUID?

    var windowTitle: String {
        let name = document.fileURL?.lastPathComponent ?? "Untitled"
        let modified = document.sourceText != savedText ? " - Edited" : ""
        return "\(name)\(modified)"
    }

    private var suggestedFileName: String {
        document.fileURL?.lastPathComponent ?? "document.tex"
    }

    private var hasStarted = false

    init(compiler: any LaTeXCompiling = LaTeXCompiler()) {
        self.compiler = compiler
        LaunchMetrics.mark("viewModel.init.begin")
        savedText = document.sourceText
        // Side effects (engine detection, history restore, cache pruning) are
        // deferred to start(), called from ContentView.task. SwiftUI can evaluate
        // the @State initializer more than once; running side effects here would
        // launch duplicate engine probes and auto-save tasks.
        showWelcome = true
        LaunchMetrics.mark("viewModel.init.end")
    }

    /// Called once from the live ContentView. Discarded initializer instances
    /// never reach this method.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        LaunchMetrics.mark("viewModel.start")

        Task.detached(priority: .utility) {
            PDFCache.prune()
        }

        Task { [weak self] in
            await self?.detectCompiler()
        }

        if historyManager.hasHistory, let lastURL = historyManager.lastProject {
            loadFile(url: lastURL)
        }

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
        LaunchMetrics.mark("engine.ready")
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
        prepareForDocumentChange()
        document = LaTeXDocument(sourceText: template.content)
        clearPDFPreview()
        errorMessage = nil
        savedText = document.sourceText
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
            let content = try Self.readText(from: url)
            prepareForDocumentChange()
            document = LaTeXDocument(sourceText: content, fileURL: url)
            savedText = content
            clearPDFPreview()
            errorMessage = nil
            showWelcome = false
            historyManager.recordProject(url)
        } catch {
            // File no longer accessible, remove from history
            historyManager.removeProject(url)
            showWelcome = true
        }
    }

    func newDocument() {
        prepareForDocumentChange()
        document = LaTeXDocument()
        clearPDFPreview()
        errorMessage = nil
        savedText = document.sourceText
        showWelcome = false
    }

    private func clearPDFPreview() {
        pdfDocument = nil
        pdfCacheURL = nil
        // Cached PDFs are pruned by PDFCache (max 3) rather than deleted here:
        // the old PDFDocument may still be referenced by PDFView until its next
        // SwiftUI update. Keeping the file briefly avoids a deleted-file race.
    }

    /// Invalidates any in-flight compile and drops build state that belongs to
    /// the previous document. Compilation history is intentionally kept — the
    /// Performance panel shows timing history across documents.
    private func prepareForDocumentChange() {
        activeCompileID = nil
        isCompiling = false
        compilationPhase = ""
        lastBuildLog = nil
        lastBuildLogFile = nil
        lastCompilationDuration = nil
        showBuildLog = false
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
        guard !showWelcome else { return }
        if let url = document.fileURL {
            writeToFile(url: url)
        } else {
            saveDocumentAs()
        }
    }

    func saveDocumentAs() {
        guard !showWelcome else { return }
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

    /// Reads a .tex file as UTF-8 when possible and falls back to the
    /// encoding detected by Foundation (older documents are often Latin-1).
    private static func readText(from url: URL) throws -> String {
        var detected: String.Encoding = .utf8
        if let text = try? String(contentsOf: url, usedEncoding: &detected) {
            return text
        }
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        return try String(contentsOf: url, encoding: .isoLatin1)
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
                self?.performAutoSave()
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
        guard !isCompiling, !showWelcome else { return }

        let compileID = UUID()
        activeCompileID = compileID
        isCompiling = true
        errorMessage = nil
        compilationPhase = "Preparing…"

        // Snapshot the document: if the user switches files while the engine is
        // running, the result below belongs to this snapshot only.
        let source = document.sourceText
        let documentURL = document.fileURL
        compileLogger.info("Compile requested for \(documentURL?.lastPathComponent ?? "untitled", privacy: .public)")

        Task { [weak self] in
            guard let self else { return }
            defer {
                // A superseded compile must not clear the state of a newer one.
                if self.activeCompileID == compileID {
                    self.isCompiling = false
                    self.compilationPhase = ""
                    self.activeCompileID = nil
                }
            }

            // Engine detection runs at launch; make sure it has finished (or
            // retry) before giving up with "engine not found".
            if self.compilerStatus == .checking {
                self.compilationPhase = "Detecting LaTeX engine…"
                await self.detectCompiler()
            }
            guard self.activeCompileID == compileID else { return }
            if case .notFound = self.compilerStatus {
                self.errorMessage = CompilationError.engineNotFound.errorDescription
                self.recordCompilation(CompilationRecord(
                    date: Date(),
                    duration: 0,
                    preparation: 0,
                    engine: 0,
                    pdfCache: 0,
                    success: false,
                    engineVersion: "No engine",
                    pdfBytes: 0
                ))
                return
            }

            var engineVersion = "Unknown"
            if case .ready(let engine) = self.compilerStatus {
                engineVersion = engine.versionDescription
            }

            self.compilationPhase = "Running LaTeX engine…"
            let compileStartedAt = Date()
            let result = await self.compiler.compile(
                source: source,
                documentURL: documentURL
            )
            let wallDuration = Date().timeIntervalSince(compileStartedAt)

            // The document changed (new/open/template) while the engine ran:
            // this output no longer describes what the user is looking at.
            guard self.activeCompileID == compileID else { return }

            self.compilationPhase = "Loading PDF…"

            switch result {
            case .success(let output):
                self.lastBuildLog = output.log
                self.lastBuildLogFile = output.logFileURL
                self.lastCompilationDuration = output.duration
                self.recordCompilation(CompilationRecord(
                    date: compileStartedAt,
                    duration: output.timings.total,
                    preparation: output.timings.preparation,
                    engine: output.timings.engine,
                    pdfCache: output.timings.pdfLoad,
                    success: true,
                    engineVersion: engineVersion,
                    pdfBytes: output.pdfByteCount
                ))
                if let pdf = PDFDocument(url: output.pdfFileURL) {
                    self.pdfDocument = pdf
                    self.pdfCacheURL = output.pdfFileURL
                    // The previous cache file is retained until PDFCache.prune
                    // keeps the newest 3, avoiding a race with the old PDFView.
                } else {
                    PDFCache.remove(output.pdfFileURL)
                    self.errorMessage = "Failed to load generated PDF."
                }
            case .failure(let error):
                self.lastBuildLog = error.buildLog
                self.lastBuildLogFile = error.buildLogFile
                self.lastCompilationDuration = nil
                self.errorMessage = error.errorDescription
                self.recordCompilation(CompilationRecord(
                    date: compileStartedAt,
                    duration: wallDuration,
                    preparation: 0,
                    engine: wallDuration,
                    pdfCache: 0,
                    success: false,
                    engineVersion: engineVersion,
                    pdfBytes: 0
                ))
            }
        }
    }

    func showBuildLogPanel() {
        guard lastBuildLog != nil else { return }
        showBuildLog = true
    }

    func clearCompilationHistory() {
        compilationHistory.removeAll()
    }

    private func recordCompilation(_ record: CompilationRecord) {
        compilationHistory.append(record)
        if compilationHistory.count > 20 {
            compilationHistory.removeFirst(compilationHistory.count - 20)
        }
    }
}
