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

    /// Regex patterns for LaTeX tokens.
    private static let patterns: [(NSRegularExpression, LaTeXTokenType)] = {
        func makeRegex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
            try! NSRegularExpression(pattern: pattern, options: options)
        }
        return [
            (makeRegex(#"%.*"#), .comment),                           // Comments
            (makeRegex(#"\\(?:begin|end)\b"#), .environmentKeyword),  // \begin, \end
            (makeRegex(#"\\[a-zA-Z]+\*?"#), .command),               // \command
            (makeRegex(#"\\[^a-zA-Z]"#), .command),                   // \{, \[, etc.
            (makeRegex(#"\\\[|\\\]|\\\(|\\\)|\$\$?"#), .mathDelimiter), // Math delimiters
            (makeRegex(#"\{"#), .argumentBrace),                      // {
            (makeRegex(#"\}"#), .argumentBrace),                      // }
            (makeRegex(#"\["#), .optionalBrace),                      // [
            (makeRegex(#"\]"#), .optionalBrace),                      // ]
        ]
    }()

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

        // First pass: mark all tokens with their type
        var tokenRanges: [(NSRange, LaTeXTokenType)] = []

        for (regex, tokenType) in Self.patterns {
            let matches = regex.matches(in: source, options: [], range: fullRange)
            for match in matches {
                tokenRanges.append((match.range, tokenType))
            }
        }

        // Sort by location and apply non-overlapping tokens (comments take priority)
        tokenRanges.sort { $0.0.location < $1.0.location }

        var lastEnd = 0
        for (range, tokenType) in tokenRanges {
            // Skip overlapping ranges (give priority to earlier tokens, especially comments)
            if range.location < lastEnd { continue }

            let color = tokenType.color(isDark: isDark)
            attributed.addAttribute(.foregroundColor, value: color, range: range)

            // Add subtle bold for commands and environment keywords
            if tokenType == .command || tokenType == .environmentKeyword {
                if let boldFont = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(.bold), size: font.pointSize) {
                    attributed.addAttribute(.font, value: boldFont, range: range)
                }
            }

            lastEnd = max(lastEnd, NSMaxRange(range))
        }

        // Second pass: detect math content between delimiters
        applyMathContentHighlighting(to: attributed, source: source)

        return attributed
    }

    /// Applies highlighting to content inside math environments ($...$, $$...$$, \[...\], \(...\)).
    private func applyMathContentHighlighting(to attributed: NSMutableAttributedString, source: String) {
        let mathPatterns: [(String, NSRegularExpression.Options)] = [
            (#"(?<!\$)\$\$(?!\$)(.+?)(?<!\$)\$\$(?!\$)"#, .dotMatchesLineSeparators), // $$...$$
            (#"(?<!\$)\$(?!\$)(.+?)(?<!\$)\$(?!\$)"#, .dotMatchesLineSeparators),     // $...$
            (#"\\\[(.+?)\\\]"#, .dotMatchesLineSeparators),                           // \[...\]
            (#"\\\((.+?)\\\)"#, .dotMatchesLineSeparators),                           // \(...\)
        ]

        for (pattern, options) in mathPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { continue }
            let matches = regex.matches(in: source, options: [], range: NSRange(location: 0, length: source.utf16.count))
            let mathColor = LaTeXTokenType.mathContent.color(isDark: isDark)

            for match in matches {
                // The math content is in capture group 1
                if match.numberOfRanges > 1 {
                    let contentRange = match.range(at: 1)
                    if contentRange.location != NSNotFound {
                        attributed.addAttribute(.foregroundColor, value: mathColor, range: contentRange)
                    }
                }
            }
        }
    }
}
