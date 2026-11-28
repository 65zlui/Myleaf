import Testing
import PDFKit
import AppKit
@testable import myleaf

/// Exercises the PDF find state machine without a live PDFView: matches are
/// computed from a generated PDF, which is all the UI needs to drive.
@MainActor
@Suite(.serialized)
struct PDFSearchStateTests {

    private func makePDF(text: String) throws -> PDFDocument {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 420, height: 200)
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))

        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 18),
                .foregroundColor: NSColor.black
            ]
        ).draw(at: NSPoint(x: 20, y: 100))
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()

        return try #require(PDFDocument(data: data as Data))
    }

    @Test func findsAllMatchesAndCycles() throws {
        let document = try makePDF(text: "Needle in a haystack. Needle again.")
        let state = PDFSearchState()

        state.present(for: document)
        state.query = "needle"

        #expect(state.matchCount == 2)
        #expect(state.currentMatchNumber == 1)

        state.next()
        #expect(state.currentMatchNumber == 2)
        state.next()
        #expect(state.currentMatchNumber == 1)
        state.previous()
        #expect(state.currentMatchNumber == 2)
    }

    @Test func matchCaseToggleRerunsSearch() throws {
        let document = try makePDF(text: "Needle needle")
        let state = PDFSearchState()
        state.present(for: document)
        state.query = "Needle"
        #expect(state.matchCount == 2)

        state.matchesCaseSensitively = true
        #expect(state.matchCount == 1)
    }

    @Test func attachesToPDFViewAndHighlightsAllMatches() throws {
        let document = try makePDF(text: "alpha beta alpha")
        let pdfView = PDFView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        pdfView.document = document

        let state = PDFSearchState()
        state.attach(pdfView)
        state.present(for: document)
        state.query = "alpha"

        #expect(state.matchCount == 2)
        #expect(pdfView.highlightedSelections?.count == 2)

        state.dismiss()
        #expect(pdfView.highlightedSelections == nil)
    }

    @Test func syncDocumentRerunsOpenSearch() throws {
        let first = try makePDF(text: "one two")
        let second = try makePDF(text: "two two two")
        let state = PDFSearchState()

        state.present(for: first)
        state.query = "two"
        #expect(state.matchCount == 1)

        // Simulates a recompilation producing a new PDFDocument.
        state.syncDocument(second)
        #expect(state.matchCount == 3)
    }

    @Test func emptyQueryAndDismissClearMatches() throws {
        let document = try makePDF(text: "alpha beta")
        let state = PDFSearchState()
        state.present(for: document)
        state.query = "alpha"
        #expect(state.matchCount == 1)

        state.query = ""
        #expect(state.matchCount == 0)

        state.query = "beta"
        state.dismiss()
        #expect(state.isPresented == false)
        #expect(state.matchCount == 0)
    }
}
