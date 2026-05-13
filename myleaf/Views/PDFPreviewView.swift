import SwiftUI
import PDFKit

struct PDFPreviewView: NSViewRepresentable {
    let pdfDocument: PDFDocument?

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        pdfView.document = pdfDocument
    }
}
