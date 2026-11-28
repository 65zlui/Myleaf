import SwiftUI
import PDFKit

struct PDFPreviewView: NSViewRepresentable {
    let pdfDocument: PDFDocument?
    var searchState: PDFSearchState?

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        searchState?.attach(pdfView)
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        // Only touch the document when it actually changed. Re-assigning the
        // same document on unrelated SwiftUI updates would drop search
        // highlights and reset the scroll position while typing.
        if pdfView.document !== pdfDocument {
            pdfView.document = pdfDocument
            // Re-run an open search against the new document *after* it is
            // installed, so highlights attach to the PDF the user sees.
            searchState?.syncDocument(pdfDocument)
        }
        // Keeps the search state pointing at the live PDFView so highlights and
        // navigation land in the view the user actually sees.
        searchState?.attach(pdfView)
    }
}
