//
//  myleafTests.swift
//  myleafTests
//
//  Created by 张锐 on 2026/4/23.
//

import Testing
import Foundation
@testable import myleaf

// MARK: - Template Tests (read-only, no mutable state)

struct TemplateTests {

    @Test func templateCategories() {
        #expect(TemplateCategory.allCases.count == 3)
    }

    @Test func templateFileAccess() {
        let templatesDir = URL(fileURLWithPath: "/Users/zhangrui/Desktop/Project/macos/myleaf/myleaf/myleaf/Resources/Templates")
        let jsonURL = templatesDir.appendingPathComponent("templates.json")
        let dirExists = FileManager.default.fileExists(atPath: templatesDir.path)
        let jsonExists = FileManager.default.fileExists(atPath: jsonURL.path)
        let dataSize = (try? Data(contentsOf: jsonURL))?.count ?? 0
        #expect(dirExists)
        #expect(jsonExists)
        #expect(dataSize > 0, "JSON data size: \(dataSize)")
    }

    @Test func totalTemplateCount() {
        let mgr = TemplateManager()
        let count = mgr.allTemplates.count
        let conf = mgr.allTemplates.filter { $0.category == .conference }.count
        let jour = mgr.allTemplates.filter { $0.category == .journal }.count
        let thes = mgr.allTemplates.filter { $0.category == .thesis }.count

        if count != 19 {
            let ids = mgr.allTemplates.map { $0.id }.joined(separator: ", ")
            Issue.record("Total: \(count) (exp 19), conf: \(conf), jour: \(jour), thes: \(thes), dir: \(mgr.templatesDir.path), ids: [\(ids)]")
        }
        #expect(count == 19)
    }

    @Test func conferenceTemplates() {
        let mgr = TemplateManager()
        let count = mgr.allTemplates.filter { $0.category == .conference }.count
        #expect(count == 8)
    }

    @Test func journalTemplates() {
        let mgr = TemplateManager()
        let count = mgr.allTemplates.filter { $0.category == .journal }.count
        #expect(count == 3)
    }

    @Test func thesisTemplates() {
        let mgr = TemplateManager()
        let count = mgr.allTemplates.filter { $0.category == .thesis }.count
        #expect(count == 8)
    }

    @Test func thesisBilingualTitles() {
        let theses = TemplateManager.shared.allTemplates.filter { $0.category == .thesis }
        for t in theses {
            // Templates use \newcommand{\thesistitle}{...} format
            #expect(t.content.contains("\\thesistitle}"))
            #expect(t.content.contains("\\thesistitleEN}"))
        }
    }

    @Test func thesisBilingualAbstracts() {
        let theses = TemplateManager.shared.allTemplates.filter { $0.category == .thesis }
        for t in theses {
            #expect(t.content.contains("摘"))
            #expect(t.content.contains("\\textbf{Abstract}"))
        }
    }

    @Test func thesisBilingualAcknowledgments() {
        let theses = TemplateManager.shared.allTemplates.filter { $0.category == .thesis }
        for t in theses {
            #expect(t.content.contains("致谢"))
            #expect(t.content.contains("Acknowledgments"))
        }
    }
}

// MARK: - LaTeXDocument Tests

struct LaTeXDocumentTests {

    @Test func defaultTemplateNotEmpty() {
        let doc = LaTeXDocument()
        #expect(!doc.sourceText.isEmpty)
    }

    @Test func defaultHasDocumentStructure() {
        let doc = LaTeXDocument()
        #expect(doc.sourceText.contains("\\documentclass"))
        #expect(doc.sourceText.contains("\\begin{document}"))
        #expect(doc.sourceText.contains("\\end{document}"))
    }

    @Test func customContent() {
        let doc = LaTeXDocument(sourceText: "custom")
        #expect(doc.sourceText == "custom")
        #expect(doc.fileURL == nil)
    }

    @Test func fileURL() {
        let url = URL(fileURLWithPath: "/tmp/test.tex")
        let doc = LaTeXDocument(fileURL: url)
        #expect(doc.fileURL?.path == url.path)
    }
}

// MARK: - ProjectHistoryManager Tests

@MainActor
@Suite(.serialized)
struct ProjectHistoryManagerTests {

    private func createTempFile(_ name: String) -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data())
        return url
    }

    @Test func autoSaveDefaultOn() {
        UserDefaults.standard.removeObject(forKey: "autoSaveEnabled")
        let mgr = ProjectHistoryManager.shared
        #expect(mgr.isAutoSaveEnabled == true)
    }

    @Test func recordHistory() {
        let mgr = ProjectHistoryManager.shared
        mgr.clearHistory()

        let url = createTempFile("test.tex")
        mgr.recordProject(url)
        #expect(mgr.hasHistory)
        #expect(mgr.recentProjects.count == 1)

        mgr.clearHistory()
        try? FileManager.default.removeItem(at: url)
    }

    @Test func historyOrder() {
        let mgr = ProjectHistoryManager.shared
        mgr.clearHistory()

        let a = createTempFile("a.tex")
        let b = createTempFile("b.tex")
        let c = createTempFile("c.tex")

        mgr.recordProject(a)
        mgr.recordProject(b)
        mgr.recordProject(c)

        let r = mgr.recentProjects
        #expect(r.count == 3)
        #expect(r[0].lastPathComponent == "c.tex")

        mgr.clearHistory()
        [a, b, c].forEach { try? FileManager.default.removeItem(at: $0) }
    }

    @Test func maxHistory() {
        let mgr = ProjectHistoryManager.shared
        mgr.clearHistory()

        var urls: [URL] = []
        for i in 0..<15 {
            let url = createTempFile("p\(i).tex")
            urls.append(url)
            mgr.recordProject(url)
        }

        #expect(mgr.recentProjects.count == 10)

        mgr.clearHistory()
        urls.forEach { try? FileManager.default.removeItem(at: $0) }
    }
}

// MARK: - ToolManager Tests

@MainActor
@Suite(.serialized)
struct ToolManagerTests {

    @Test func sharedSameInstance() {
        #expect(ToolManager.shared === ToolManager.shared)
    }

    @Test func twoTools() {
        #expect(ManagedTool.allCases.count == 2)
    }

    @Test func uniqueIDs() {
        let ids = ManagedTool.allCases.map { $0.id }
        #expect(Set(ids).count == ids.count)
    }

    @Test func nonNegativeDiskUsage() {
        #expect(ToolManager.shared.totalDiskUsage() >= 0)
    }
}

// MARK: - BibTeXParser Tests

@MainActor
@Suite(.serialized)
struct BibTeXParserTests {

    private func createTempBibFile(_ content: String, name: String = "test.bib") -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Parsing Valid Input

    @Test func parseSingleArticleEntry() throws {
        let bib = """
        @article{smith2023ai,
            author = {John Smith},
            title = {A Study of Artificial Intelligence},
            year = {2023},
            journal = {AI Journal}
        }
        """
        let entries = try BibTeXParser.parse(bib)
        #expect(entries.count == 1)
        #expect(entries[0].id == "smith2023ai")
        #expect(entries[0].type == "article")
        #expect(entries[0].author == "John Smith")
        #expect(entries[0].title == "A Study of Artificial Intelligence")
        #expect(entries[0].year == "2023")
    }

    @Test func parseMultipleEntries() throws {
        let bib = """
        @article{smith2023ai,
            author = {John Smith},
            title = {AI Study},
            year = {2023}
        }

        @book{jones2022ml,
            author = {Jane Jones},
            title = {Machine Learning Basics},
            year = {2022}
        }
        """
        let entries = try BibTeXParser.parse(bib)
        #expect(entries.count == 2)
        #expect(entries[0].id == "smith2023ai")
        #expect(entries[1].id == "jones2022ml")
        #expect(entries[1].type == "book")
    }

    @Test func parseDifferentEntryTypes() throws {
        let bib = """
        @inproceedings{conf2023,
            author = {Author One},
            title = {Conference Paper},
            year = {2023}
        }

        @misc{web2024,
            author = {Web Author},
            title = {Website Reference},
            year = {2024}
        }
        """
        let entries = try BibTeXParser.parse(bib)
        #expect(entries.count == 2)
        #expect(entries[0].type == "inproceedings")
        #expect(entries[1].type == "misc")
    }

    // MARK: - Field Value Formats

    @Test func parseBracedFieldValue() throws {
        let bib = """
        @article{test1,
            title = {Braced Title},
            year = {2023}
        }
        """
        let entries = try BibTeXParser.parse(bib)
        #expect(entries[0].fields["title"] == "Braced Title")
    }

    @Test func parseQuotedFieldValue() throws {
        let bib = """
        @article{test2,
            title = "Quoted Title",
            year = "2023"
        }
        """
        let entries = try BibTeXParser.parse(bib)
        #expect(entries[0].fields["title"] == "Quoted Title")
        #expect(entries[0].fields["year"] == "2023")
    }

    @Test func parseBareWordFieldValue() throws {
        let bib = """
        @article{test3,
            year = 2023
        }
        """
        let entries = try BibTeXParser.parse(bib)
        #expect(entries[0].fields["year"] == "2023")
    }

    @Test func parseNestedBracesInValue() throws {
        let bib = """
        @article{test4,
            title = {A {Nested} Title},
            year = {2023}
        }
        """
        let entries = try BibTeXParser.parse(bib)
        #expect(entries[0].fields["title"] == "A {Nested} Title")
    }

    // MARK: - Comments and Edge Cases

    @Test func parseWithComments() throws {
        let bib = """
        % This is a comment
        @article{test5,
            author = {Comment Author},
            title = {After Comment},
            year = {2023}
        }
        % Another comment
        """
        let entries = try BibTeXParser.parse(bib)
        #expect(entries.count == 1)
        #expect(entries[0].id == "test5")
    }

    @Test func parseEmptyInput() throws {
        let result = Result { try BibTeXParser.parse("") }
        switch result {
        case .success(let entries):
            #expect(entries.isEmpty)
        case .failure(let error):
            #expect(error is BibTeXError)
        }
    }

    @Test func parseWhitespaceOnly() throws {
        let entries = try BibTeXParser.parse("   \n\n  \t  ")
        #expect(entries.isEmpty)
    }

    // MARK: - File Parsing

    @Test func parseFileAtURL() throws {
        let bib = """
        @article{filetest,
            author = {File Author},
            title = {File Title},
            year = {2023}
        }
        """
        let url = createTempBibFile(bib)
        let entries = try BibTeXParser.parseFile(at: url)
        #expect(entries.count == 1)
        #expect(entries[0].id == "filetest")
        try? FileManager.default.removeItem(at: url)
    }

    @Test func parseNonexistentFile() {
        let url = URL(fileURLWithPath: "/tmp/nonexistent_file_12345.bib")
        #expect(throws: Error.self) {
            try BibTeXParser.parseFile(at: url)
        }
    }

    // MARK: - BibTeXEntry Model

    @Test func entryCiteCommand() {
        let entry = BibTeXEntry(id: "smith2023", type: "article", fields: [:])
        #expect(entry.citeCommand == "\\cite{smith2023}")
    }

    @Test func entryDisplayStringWithAuthorYear() {
        let entry = BibTeXEntry(id: "test1", type: "article", fields: [
            "author": "John Smith",
            "year": "2023",
            "title": "Test Title"
        ])
        let display = entry.displayString
        #expect(display.contains("John Smith"))
        #expect(display.contains("2023"))
        #expect(display.contains("Test Title"))
    }

    @Test func entryDisplayStringWithManyAuthors() {
        let entry = BibTeXEntry(id: "test2", type: "article", fields: [
            "author": "A and B and C and D",
            "year": "2023",
            "title": "Many Authors"
        ])
        let display = entry.displayString
        #expect(display.contains("et al."))
    }

    @Test func entryDisplayStringNoTitle() {
        let entry = BibTeXEntry(id: "test3", type: "article", fields: [
            "author": "Author",
            "year": "2023"
        ])
        #expect(entry.title.isEmpty)
        let display = entry.displayString
        #expect(display.contains("Author"))
        #expect(display.contains("2023"))
    }

    @Test func entryEquatable() {
        let a = BibTeXEntry(id: "x", type: "article", fields: ["year": "2023"])
        let b = BibTeXEntry(id: "x", type: "article", fields: ["year": "2023"])
        let c = BibTeXEntry(id: "y", type: "article", fields: ["year": "2023"])
        #expect(a == b)
        #expect(a != c)
    }

    @Test func entryStringFormat() {
        let entry = BibTeXEntry(id: "test", type: "article", fields: [
            "author": "Author",
            "title": "Title",
            "year": "2023"
        ])
        let str = entry.entryString
        #expect(str.hasPrefix("@article{test,"))
        #expect(str.contains("author = {Author}"))
        #expect(str.hasSuffix("}"))
    }

    // MARK: - Integration: insertCitations

    @Test func insertCitationsBeforeEndDocument() {
        let vm = EditorViewModel()
        vm.document.sourceText = "\\begin{document}\nSome text\n\\end{document}"
        let entry = BibTeXEntry(id: "smith2023", type: "article", fields: ["title": "Test"])
        vm.insertCitations([entry])
        #expect(vm.document.sourceText.contains("\\cite{smith2023}"))
        #expect(vm.document.sourceText.contains("\\end{document}"))
    }

    @Test func insertCitationsMultipleEntries() {
        let vm = EditorViewModel()
        vm.document.sourceText = "\\begin{document}\nContent\n\\end{document}"
        let entries = [
            BibTeXEntry(id: "a", type: "article", fields: [:]),
            BibTeXEntry(id: "b", type: "article", fields: [:])
        ]
        vm.insertCitations(entries)
        #expect(vm.document.sourceText.contains("\\cite{a, b}"))
    }

    @Test func insertCitationsAppendsIfNoEndDocument() {
        let vm = EditorViewModel()
        vm.document.sourceText = "Some content without end document"
        let entry = BibTeXEntry(id: "test", type: "article", fields: [:])
        vm.insertCitations([entry])
        #expect(vm.document.sourceText.hasSuffix("\\cite{test}\n"))
    }

    @Test func insertEmptyCitationsDoesNothing() {
        let vm = EditorViewModel()
        let original = vm.document.sourceText
        vm.insertCitations([])
        #expect(vm.document.sourceText == original)
    }
}
