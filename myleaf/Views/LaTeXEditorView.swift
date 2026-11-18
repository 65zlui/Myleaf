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
        private var isUpdatingProgrammatically = false

        init(_ parent: LaTeXEditorView) {
            self.parent = parent
        }

        deinit {
            print("[Deinit] LaTeXEditorView.Coordinator")
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdatingProgrammatically, let textView = textView else { return }
            parent.text = textView.string
            // Apply highlighting synchronously to prevent a visible frame
            // of un-highlighted text before the next run-loop tick.
            applyHighlighting()
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

            let storage = textView.textStorage!
            let fullRange = NSRange(location: 0, length: storage.length)
            let baseFont = NSFont.monospacedSystemFont(ofSize: parent.fontSize, weight: .regular)

            storage.beginEditing()

            // 1. Reset foregroundColor only — never touch font globally, which
            //    would cause NSLayoutManager to recalculate every glyph metric.
            storage.removeAttribute(.foregroundColor, range: fullRange)

            // 2. Apply foregroundColor from the highlighted attributed string.
            attributed.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: attributed.length), options: []) { value, range, _ in
                if let color = value {
                    storage.addAttribute(.foregroundColor, value: color, range: range)
                }
            }

            // 3. Apply font ONLY where it differs from the base monospaced font
            //    (i.e. bold for \commands and \begin/\end). This avoids touching
            //    the majority of ranges and prevents layout thrashing.
            attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length), options: []) { value, range, _ in
                guard let attrFont = value as? NSFont else { return }
                if !attrFont.isEqual(baseFont) {
                    storage.addAttribute(.font, value: attrFont, range: range)
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

    override var isAutomaticQuoteSubstitutionEnabled: Bool {
        get { false }
        set { }
    }
    override var isAutomaticDashSubstitutionEnabled: Bool {
        get { false }
        set { }
    }
}
