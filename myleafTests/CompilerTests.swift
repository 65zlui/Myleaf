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
            #expect(output.pdfData.count > 0)
            #expect(output.pdfData.prefix(4) == Data("%PDF".utf8))
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
            #expect(output.pdfData.count > 0)
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
        }
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
    }
}
