import SwiftUI
import AppKit

// MARK: - SwiftUI Bridge

/// A syntax-highlighted LaTeX editor backed by NSTextView inside NSScrollView.
struct LaTeXEditorView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 13

    func makeNSView(context: Context) -> NSScrollView {
        // Create scroll view
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        // Create text view
        let textView = LaTeXTextView()
        textView.delegate = context.coordinator
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.string = text
        textView.isRichText = false
        textView.allowsUndo = true
        textView.typingAttributes = [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: NSColor.textColor
        ]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.usesRuler = false
        textView.usesInspectorBar = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.backgroundColor = .clear

        scrollView.documentView = textView

        context.coordinator.textView = textView
        context.coordinator.parent = self

        context.coordinator.applyHighlighting()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? LaTeXTextView else { return }
        guard textView.string != text else { return }
        context.coordinator.updateTextWithoutResettingCursor(text)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LaTeXEditorView
        weak var textView: LaTeXTextView?
        fileprivate var highlightWorkItem: DispatchWorkItem?
        private var isUpdatingProgrammatically = false

        init(_ parent: LaTeXEditorView) {
            self.parent = parent
        }

        deinit {
            print("[Deinit] LaTeXEditorView.Coordinator")
            highlightWorkItem?.cancel()
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdatingProgrammatically, let textView = textView else { return }
            parent.text = textView.string
            scheduleHighlight()
        }

        func updateTextWithoutResettingCursor(_ newText: String) {
            guard let textView = textView else { return }
            isUpdatingProgrammatically = true
            defer { isUpdatingProgrammatically = false }

            let selectedRange = textView.selectedRange()
            textView.string = newText
            let clampedLocation = min(selectedRange.location, newText.utf16.count)
            let clampedLength = min(selectedRange.length, newText.utf16.count - clampedLocation)
            textView.setSelectedRange(NSRange(location: clampedLocation, length: clampedLength))
            applyHighlighting()
        }

        func scheduleHighlight() {
            highlightWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.applyHighlighting()
            }
            highlightWorkItem = workItem
            DispatchQueue.main.async(execute: workItem)
        }

        func applyHighlighting() {
            guard let textView = textView else { return }
            let source = textView.string
            let isDark = textView.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let highlighter = LaTeXSyntaxHighlighter(
                font: NSFont.monospacedSystemFont(ofSize: parent.fontSize, weight: .regular),
                isDark: isDark
            )

            let selectedRange = textView.selectedRange()
            let attributed = highlighter.highlightedString(from: source)

            // Only apply color attribute — avoid removing/re-adding font which
            // would cause NSLayoutManager to recalculate all glyph metrics and
            // trigger scroll view content size jumps.
            let storage = textView.textStorage!
            storage.beginEditing()
            storage.removeAttribute(.foregroundColor, range: NSRange(location: 0, length: storage.length))
            attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length), options: []) { attrs, range, _ in
                for (key, value) in attrs where key != .font {
                    storage.addAttribute(key, value: value, range: range)
                }
            }
            // Font is applied separately to avoid redundant layout passes
            attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length), options: []) { attrs, range, _ in
                if let fontValue = attrs[.font] {
                    storage.addAttribute(.font, value: fontValue, range: range)
                }
            }
            storage.endEditing()

            textView.setSelectedRange(selectedRange)
        }
    }
}

// MARK: - Custom NSTextView

class LaTeXTextView: NSTextView {
    deinit {
        print("[Deinit] LaTeXTextView")
    }

    override func paste(_ sender: Any?) {
        super.paste(sender)
        // Immediate highlighting after paste — skip 50ms debounce
        if let coordinator = delegate as? LaTeXEditorView.Coordinator {
            coordinator.highlightWorkItem?.cancel()
            coordinator.applyHighlighting()
        }
    }

    override var isAutomaticQuoteSubstitutionEnabled: Bool {
        get { false }
        set { }
    }
    override var isAutomaticDashSubstitutionEnabled: Bool {
        get { false }
        set { }
    }
}
