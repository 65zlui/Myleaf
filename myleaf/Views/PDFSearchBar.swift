import SwiftUI
import PDFKit

/// Search state for the PDF preview. It owns the query and the match list and
/// drives the hosted `PDFView` (highlight all matches, jump to the current one).
@Observable
@MainActor
final class PDFSearchState {
    /// Whether the find bar is visible.
    var isPresented = false

    /// Query text. Changing it re-runs the search immediately.
    var query = "" {
        didSet { if query != oldValue { refresh() } }
    }

    /// When true only exact-case matches are returned.
    var matchesCaseSensitively = false {
        didSet { if matchesCaseSensitively != oldValue { refresh() } }
    }

    private(set) var matchCount = 0
    /// 1-based index of the current match for display; 0 when there is none.
    private(set) var currentMatchNumber = 0

    /// Bumped whenever the bar should put focus back into its text field.
    private(set) var focusRequest = 0

    private weak var pdfView: PDFView?
    private var document: PDFDocument?
    private var matches: [PDFSelection] = []
    private var currentIndex = 0

    // MARK: - Presentation

    func present(for document: PDFDocument?) {
        self.document = document
        isPresented = true
        focusRequest += 1
        refresh()
    }

    func dismiss() {
        isPresented = false
        query = ""
        clearResults()
    }

    /// Drops the document as well; used when the editor switches files.
    func reset() {
        document = nil
        dismiss()
    }

    /// Called when the preview gets a new document (e.g. after recompilation).
    /// An open search re-runs on the new PDF so highlights stay in sync.
    func syncDocument(_ document: PDFDocument?) {
        guard document !== self.document else { return }
        self.document = document
        if isPresented {
            refresh()
        } else {
            clearResults()
        }
    }

    /// Called by `PDFPreviewView` when it creates (or reuses) its PDFView.
    func attach(_ view: PDFView) {
        guard pdfView !== view else { return }
        pdfView = view
        applyHighlights()
    }

    // MARK: - Navigation

    func next() {
        guard !matches.isEmpty else { return }
        currentIndex = (currentIndex + 1) % matches.count
        selectCurrentMatch(animate: true)
    }

    func previous() {
        guard !matches.isEmpty else { return }
        currentIndex = (currentIndex - 1 + matches.count) % matches.count
        selectCurrentMatch(animate: true)
    }

    // MARK: - Searching

    private func refresh() {
        guard isPresented, let document, !query.isEmpty else {
            clearResults()
            return
        }

        let options: NSString.CompareOptions = matchesCaseSensitively ? [] : [.caseInsensitive]
        matches = document.findString(query, withOptions: options)
        matchCount = matches.count
        currentIndex = 0
        // Kept independent of the PDFView: the bar must show a correct count
        // even before the preview has attached its view.
        currentMatchNumber = matches.isEmpty ? 0 : 1
        applyHighlights()
    }

    private func clearResults() {
        matches = []
        matchCount = 0
        currentIndex = 0
        currentMatchNumber = 0
        pdfView?.highlightedSelections = nil
        pdfView?.setCurrentSelection(nil, animate: false)
    }

    private func applyHighlights() {
        guard let pdfView else { return }
        pdfView.highlightedSelections = matches.isEmpty ? nil : matches
        guard !matches.isEmpty else {
            currentMatchNumber = 0
            pdfView.setCurrentSelection(nil, animate: false)
            return
        }
        selectCurrentMatch(animate: false)
    }

    private func selectCurrentMatch(animate: Bool) {
        guard matches.indices.contains(currentIndex) else { return }
        currentMatchNumber = currentIndex + 1
        let match = matches[currentIndex]
        pdfView?.go(to: match)
        pdfView?.setCurrentSelection(match, animate: animate)
    }
}

/// Floating find bar shown over the PDF pane.
struct PDFSearchBar: View {
    @Bindable var state: PDFSearchState

    @FocusState private var queryFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Find in PDF", text: $state.query)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 120, idealWidth: 170, maxWidth: 190)
                .focused($queryFocused)
                .onSubmit { state.next() }

            Text(resultLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 42, alignment: .trailing)

            Button(action: state.previous) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(state.matchCount == 0)
            .help("Previous match")

            Button(action: state.next) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(state.matchCount == 0)
            .help("Next match (Return)")

            Toggle(isOn: $state.matchesCaseSensitively) {
                Text("Aa")
                    .font(.caption)
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help("Match case")

            Button(action: state.dismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Close (Esc)")
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .onAppear { queryFocused = true }
        .onChange(of: state.focusRequest) { _, _ in
            queryFocused = true
        }
        .onExitCommand { state.dismiss() }
    }

    private var resultLabel: String {
        if state.query.isEmpty { return "" }
        if state.matchCount == 0 { return "0" }
        return "\(state.currentMatchNumber)/\(state.matchCount)"
    }
}

#Preview {
    PDFSearchBar(state: PDFSearchState())
        .padding()
}
