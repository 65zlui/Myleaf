import Foundation
import AppKit

/// Token types for LaTeX syntax highlighting.
enum LaTeXTokenType {
    case comment
    case command
    case environmentKeyword
    case argumentBrace
    case optionalBrace
    case mathDelimiter
    case mathContent
    case text
}

extension LaTeXTokenType {
    /// Syntax color for each token type, adapted for both light and dark modes.
    func color(isDark: Bool) -> NSColor {
        switch self {
        case .comment:
            return NSColor(hex: isDark ? 0x6A9955 : 0x008000)
        case .command:
            return NSColor(hex: isDark ? 0x569CD6 : 0x0000FF)
        case .environmentKeyword:
            return NSColor(hex: isDark ? 0xC586C0 : 0xAF00DB)
        case .argumentBrace:
            return NSColor(hex: isDark ? 0xD4D4D4 : 0xA31515)
        case .optionalBrace:
            return NSColor(hex: isDark ? 0xD4D4D4 : 0xA31515)
        case .mathDelimiter:
            return NSColor(hex: isDark ? 0xCE9178 : 0xCD3131)
        case .mathContent:
            return NSColor(hex: isDark ? 0xCE9178 : 0xCD3131)
        case .text:
            return isDark ? .white : .black
        }
    }
}

extension NSColor {
    convenience init(hex: Int) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }
}

/// Parses LaTeX source into attributed tokens for syntax highlighting.
struct LaTeXSyntaxHighlighter {

    /// The default font for the editor.
    let font: NSFont

    /// Whether the current appearance is dark mode.
    let isDark: Bool

    private struct Rule {
        let regex: NSRegularExpression
        let type: LaTeXTokenType
        /// Lower values win when two rules match at the same position
        /// (e.g. \begin should be an environment keyword, not a command).
        let priority: Int
        let bold: Bool
    }

    private static func makeRegex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static let rules: [Rule] = [
        Rule(regex: makeRegex(#"\\(?:begin|end)\b"#), type: .environmentKeyword, priority: 0, bold: true),
        Rule(regex: makeRegex(#"\\\[|\\\]|\\\(|\\\)|\$\$?"#), type: .mathDelimiter, priority: 1, bold: false),
        Rule(regex: makeRegex(#"\\[a-zA-Z]+\*?"#), type: .command, priority: 2, bold: true),
        Rule(regex: makeRegex(#"\\[^a-zA-Z]"#), type: .command, priority: 3, bold: true),
        Rule(regex: makeRegex(#"\{"#), type: .argumentBrace, priority: 4, bold: false),
        Rule(regex: makeRegex(#"\}"#), type: .argumentBrace, priority: 4, bold: false),
        Rule(regex: makeRegex(#"\["#), type: .optionalBrace, priority: 4, bold: false),
        Rule(regex: makeRegex(#"\]"#), type: .optionalBrace, priority: 4, bold: false),
    ]

    /// A comment starts at an unescaped `%` and runs to the end of the line.
    private static let commentRegex = makeRegex(#"(?<!\\)%.*"#)

    private static let mathPatterns: [NSRegularExpression] = [
        makeRegex(#"(?<!\$)\$\$(?!\$)(.+?)(?<!\$)\$\$(?!\$)"#, .dotMatchesLineSeparators), // $$...$$
        makeRegex(#"(?<!\$)\$(?!\$)(.+?)(?<!\$)\$(?!\$)"#, .dotMatchesLineSeparators),     // $...$
        makeRegex(#"\\\[(.+?)\\\]"#, .dotMatchesLineSeparators),                           // \[...\]
        makeRegex(#"\\\((.+?)\\\)"#, .dotMatchesLineSeparators),                           // \(...\)
    ]

    init(font: NSFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), isDark: Bool = false) {
        self.font = font
        self.isDark = isDark
    }

    /// Returns an attributed string with syntax highlighting applied.
    func highlightedString(from source: String) -> NSAttributedString {
        let textColor = LaTeXTokenType.text.color(isDark: isDark)
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]

        let attributed = NSMutableAttributedString(string: source, attributes: baseAttributes)
        let fullRange = NSRange(location: 0, length: source.utf16.count)

        let commentRanges = Self.commentRegex
            .matches(in: source, options: [], range: fullRange)
            .map(\.range)

        // Mark all tokens, skipping anything that lives inside a comment.
        var tokens: [(range: NSRange, type: LaTeXTokenType, priority: Int, bold: Bool)] = []
        for rule in Self.rules {
            for match in rule.regex.matches(in: source, options: [], range: fullRange) {
                guard !Self.intersectsAny(match.range, commentRanges) else { continue }
                tokens.append((match.range, rule.type, rule.priority, rule.bold))
            }
        }

        tokens.sort {
            if $0.range.location != $1.range.location {
                return $0.range.location < $1.range.location
            }
            return $0.priority < $1.priority
        }

        var lastEnd = 0
        for token in tokens {
            if token.range.location < lastEnd { continue }

            let color = token.type.color(isDark: isDark)
            attributed.addAttribute(.foregroundColor, value: color, range: token.range)

            if token.bold,
               let boldFont = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(.bold), size: font.pointSize) {
                attributed.addAttribute(.font, value: boldFont, range: token.range)
            }

            lastEnd = max(lastEnd, NSMaxRange(token.range))
        }

        // Math content is colored after ordinary tokens, but never inside comments.
        applyMathContentHighlighting(to: attributed, source: source, commentRanges: commentRanges)

        // Comments have the final word, regardless of what they contain.
        let commentColor = LaTeXTokenType.comment.color(isDark: isDark)
        for range in commentRanges {
            attributed.addAttribute(.foregroundColor, value: commentColor, range: range)
        }

        return attributed
    }

    /// Applies highlighting to content inside math environments ($...$, $$...$$, \[...\], \(...\)).
    private func applyMathContentHighlighting(
        to attributed: NSMutableAttributedString,
        source: String,
        commentRanges: [NSRange]
    ) {
        let fullRange = NSRange(location: 0, length: source.utf16.count)
        let mathColor = LaTeXTokenType.mathContent.color(isDark: isDark)

        for regex in Self.mathPatterns {
            for match in regex.matches(in: source, options: [], range: fullRange) {
                guard match.numberOfRanges > 1 else { continue }
                let contentRange = match.range(at: 1)
                guard contentRange.location != NSNotFound,
                      !Self.intersectsAny(contentRange, commentRanges) else { continue }
                attributed.addAttribute(.foregroundColor, value: mathColor, range: contentRange)
            }
        }
    }

    private static func intersectsAny(_ range: NSRange, _ ranges: [NSRange]) -> Bool {
        for other in ranges where range.location < NSMaxRange(other) && other.location < NSMaxRange(range) {
            return true
        }
        return false
    }
}
