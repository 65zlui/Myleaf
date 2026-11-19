import Testing
import Foundation
@testable import myleaf

/// Integration tests for the LaTeX compilation pipeline. They need a real TeX
/// engine (Tectonic or pdflatex) and are skipped automatically when none is
/// installed, so CI machines without a TeX distribution stay green.
@Suite(.serialized)
struct LaTeXCompilerTests {

    private func makeCompiler() -> LaTeXCompiler? {
        let compiler = LaTeXCompiler()
        return compiler.detectEngine() == nil ? nil : compiler
    }

    @Test func compileSimpleDocument() async throws {
        guard let compiler = makeCompiler() else { return }

        let source = """
        \\documentclass{article}
        \\begin{document}
        Hello, myleaf!
        \\end{document}
        """

        let result = await compiler.compile(source: source)
        switch result {
        case .success(let output):
            let pdfData = try Data(contentsOf: output.pdfFileURL)
            #expect(pdfData.count > 0)
            #expect(pdfData.prefix(4) == Data("%PDF".utf8))
            #expect(output.pdfByteCount > 0)
            #expect(output.log.contains("myleaf build log"))
            #expect(output.log.contains("Exit status: 0"))
            #expect(output.log.contains("Engine: Tectonic") || output.log.contains("Engine: pdflatex"))
            #expect(output.log.contains("Engine version:"))
            #expect(output.log.contains("--- timings ---"))
            #expect(output.log.contains("Engine run:"))
            #expect(output.timings.total >= output.timings.engine)
            #expect(output.timings.engine > 0)
            #expect(output.duration == output.timings.total)
            #expect(output.logFileURL != nil)
            if let logURL = output.logFileURL {
                #expect(FileManager.default.fileExists(atPath: logURL.path))
                try? FileManager.default.removeItem(at: logURL)
            }
            PDFCache.remove(output.pdfFileURL)
        case .failure(let error):
            Issue.record("Expected success, got \(error.localizedDescription)")
        }
    }

    @Test func compileResolvesSiblingInputFiles() async throws {
        guard let compiler = makeCompiler() else { return }

        let project = FileManager.default.temporaryDirectory
            .appendingPathComponent("myleaf-compiler-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: project) }

        try "Included section content.".write(
            to: project.appendingPathComponent("section.tex"),
            atomically: true,
            encoding: .utf8
        )

        let source = """
        \\documentclass{article}
        \\begin{document}
        \\input{section.tex}
        \\end{document}
        """
        let mainFile = project.appendingPathComponent("main.tex")
        try source.write(to: mainFile, atomically: true, encoding: .utf8)

        let result = await compiler.compile(source: source, documentURL: mainFile)
        switch result {
        case .success(let output):
            let pdfData = try Data(contentsOf: output.pdfFileURL)
            #expect(pdfData.count > 0)
            PDFCache.remove(output.pdfFileURL)
        case .failure(let error):
            Issue.record("Expected success, got \(error.localizedDescription)")
        }

        // The temporary sibling file used for compilation must be cleaned up.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: project.path)
        #expect(!leftovers.contains { $0.hasPrefix("myleaf-compile-") })
    }

    @Test func compileFailureReturnsLog() async throws {
        guard let compiler = makeCompiler() else { return }

        let source = """
        \\documentclass{article}
        \\begin{document}
        \\thiscommanddoesnotexist
        \\end{document}
        """

        let result = await compiler.compile(source: source)
        switch result {
        case .success:
            Issue.record("Expected compilation to fail")
        case .failure(let error):
            guard case .compilationFailed = error else {
                Issue.record("Expected .compilationFailed, got \(error)")
                return
            }
            #expect(error.errorDescription?.isEmpty == false)
            #expect(error.buildLog?.contains("Exit status") == true)
            #expect(error.buildLog?.contains("--- timings ---") == true)
            if let logURL = error.buildLogFile {
                #expect(FileManager.default.fileExists(atPath: logURL.path))
                try? FileManager.default.removeItem(at: logURL)
            }
        }
    }
}

@Suite(.serialized)
struct TexEngineVersionTests {

    @Test func newerPatchWins() {
        #expect(TeXEngine.compareVersions("0.17.0", "0.16.9") == .orderedDescending)
        #expect(TeXEngine.compareVersions("1.0.10", "1.0.9") == .orderedDescending)
        #expect(TeXEngine.compareVersions("1.0", "1.0.0") == .orderedSame)
        #expect(TeXEngine.compareVersions(nil, "0.1.0") == .orderedAscending)
        #expect(TeXEngine.compareVersions("0.1.0", nil) == .orderedDescending)
        #expect(TeXEngine.compareVersions(nil, nil) == .orderedSame)
    }

    @Test func detectionReportsVersion() {
        let compiler = LaTeXCompiler()
        guard let engine = compiler.detectEngine() else { return }
        #expect(engine.version?.isEmpty == false)
        #expect(engine.url.isFileURL)
    }
}

@Suite(.serialized)
struct BuildLogStoreTests {

    @Test func savesLogFile() throws {
        let marker = UUID().uuidString
        let url = try #require(BuildLogStore.save("myleaf test log \(marker)"))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(FileManager.default.fileExists(atPath: url.path))
        let contents = try String(contentsOf: url, encoding: .utf8)
        #expect(contents.contains(marker))
        #expect(BuildLogStore.recentLogs().contains(url))
    }
}

/// Verifies the view-model wiring around compilation: engine detection,
/// the isCompiling flag, error propagation, and the PDF preview document.
@MainActor
@Suite(.serialized)
struct EditorViewModelCompileTests {

    @Test func compileUpdatesPDFPreview() async throws {
        guard LaTeXCompiler().detectEngine() != nil else { return }

        let viewModel = EditorViewModel()
        viewModel.newDocument()
        viewModel.document.sourceText = """
        \\documentclass{article}
        \\begin{document}
        View model integration test.
        \\end{document}
        """

        viewModel.compile()

        let deadline = Date().addingTimeInterval(180)
        while viewModel.isCompiling && Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        #expect(viewModel.isCompiling == false)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.pdfDocument != nil)
        #expect(viewModel.lastBuildLog?.isEmpty == false)
        #expect(viewModel.lastCompilationDuration != nil)
        #expect(viewModel.compilationHistory.count == 1)
        #expect(viewModel.compilationHistory.last?.success == true)
        if let pdfURL = viewModel.pdfCacheURL {
            #expect(FileManager.default.fileExists(atPath: pdfURL.path))
        }
        PDFCache.remove(viewModel.pdfCacheURL)

        if let logURL = viewModel.lastBuildLogFile {
            #expect(FileManager.default.fileExists(atPath: logURL.path))
            try? FileManager.default.removeItem(at: logURL)
        }
    }
}
