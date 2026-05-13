import Foundation

enum BibTeXError: LocalizedError {
    case emptyInput
    case invalidFormat(String)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "The BibTeX file is empty or contains no entries."
        case .invalidFormat(let detail):
            return "Failed to parse BibTeX: \(detail)"
        }
    }
}

/// Parses BibTeX format strings into structured entries.
final class BibTeXParser {

    /// Parse raw BibTeX content into a list of entries.
    static func parse(_ content: String) throws -> [BibTeXEntry] {
        let cleaned = stripComments(content)
        return try extractEntries(from: cleaned)
    }

    /// Parse a .bib file at the given URL.
    static func parseFile(at url: URL) throws -> [BibTeXEntry] {
        let content = try String(contentsOf: url, encoding: .utf8)
        return try parse(content)
    }

    // MARK: - Private

    private static func stripComments(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("%") }
            .joined(separator: "\n")
    }

    private static func extractEntries(from text: String) throws -> [BibTeXEntry] {
        var entries: [BibTeXEntry] = []
        var scanner = Scanner(string: text)
        scanner.charactersToBeSkipped = nil

        while !scanner.isAtEnd {
            // Skip whitespace
            scanWhitespace(&scanner)

            if scanner.isAtEnd { break }

            // Look for @ at start of entry
            guard let nextChar = scanner.scanCharacter(), nextChar == "@" else {
                // Skip unknown character and continue
                continue
            }

            // Scan entry type (e.g. "article")
            guard let type = scanWord(&scanner)?.lowercased() else {
                throw BibTeXError.invalidFormat("expected entry type after '@'")
            }

            // Skip whitespace
            scanWhitespace(&scanner)

            // Expect '{'
            guard let openBrace = scanner.scanCharacter(), openBrace == "{" else {
                throw BibTeXError.invalidFormat("expected '{' after entry type")
            }

            // Skip whitespace
            scanWhitespace(&scanner)

            // Scan citation key
            guard let key = scanWord(&scanner) else {
                throw BibTeXError.invalidFormat("expected citation key")
            }

            // Skip whitespace
            scanWhitespace(&scanner)

            // Expect ','
            guard let comma = scanner.scanCharacter(), comma == "," else {
                // Might be closing brace immediately (entry with no fields)
                if scanner.scanCharacter() == "}" {
                    entries.append(BibTeXEntry(id: key, type: type, fields: [:]))
                    continue
                }
                throw BibTeXError.invalidFormat("expected ',' after citation key")
            }

            // Scan fields until closing brace
            let fields = try scanFields(&scanner)

            entries.append(BibTeXEntry(id: key, type: type, fields: fields))
        }

        return entries
    }

    private static func scanFields(_ scanner: inout Scanner) throws -> [String: String] {
        var fields: [String: String] = [:]
        var braceDepth = 0

        while !scanner.isAtEnd {
            scanWhitespace(&scanner)

            if scanner.isAtEnd { break }

            // Check for closing brace
            if let ch = scanner.peek(), ch == "}" {
                _ = scanner.scanCharacter()
                return fields
            }

            // Scan field name
            guard let fieldName = scanWord(&scanner) else {
                // Skip character and continue
                _ = scanner.scanCharacter()
                continue
            }

            scanWhitespace(&scanner)

            // Expect '='
            guard let eq = scanner.scanCharacter(), eq == "=" else {
                continue
            }

            scanWhitespace(&scanner)

            // Scan field value (supports {value}, "value", and bare words)
            let value = try scanFieldValue(&scanner, braceDepth: &braceDepth)
            fields[fieldName.lowercased()] = value
        }

        throw BibTeXError.invalidFormat("unexpected end of entry (missing closing brace)")
    }

    private static func scanFieldValue(_ scanner: inout Scanner, braceDepth: inout Int) throws -> String {
        scanWhitespace(&scanner)

        guard let firstChar = scanner.peek() else {
            throw BibTeXError.invalidFormat("expected field value")
        }

        if firstChar == "{" {
            return try scanBracedValue(&scanner, braceDepth: &braceDepth)
        } else if firstChar == "\"" {
            return scanQuotedValue(&scanner)
        } else {
            // Bare word (e.g., a number or macro)
            return scanWord(&scanner) ?? ""
        }
    }

    private static func scanBracedValue(_ scanner: inout Scanner, braceDepth: inout Int) throws -> String {
        // Consume opening brace
        _ = scanner.scanCharacter()
        braceDepth += 1

        var depth = 1
        var value = ""

        while !scanner.isAtEnd {
            guard let ch = scanner.scanCharacter() else { break }
            if ch == "{" {
                depth += 1
            } else if ch == "}" {
                depth -= 1
                if depth == 0 {
                    braceDepth -= 1
                    return value.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            value.append(ch)
        }

        throw BibTeXError.invalidFormat("unterminated braced field")
    }

    private static func scanQuotedValue(_ scanner: inout Scanner) -> String {
        // Consume opening quote
        _ = scanner.scanCharacter()
        var value = ""

        while !scanner.isAtEnd {
            guard let ch = scanner.scanCharacter() else { break }
            if ch == "\"" {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            value.append(ch)
        }

        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func scanWord(_ scanner: inout Scanner) -> String? {
        var word = ""
        while let ch = scanner.peek(), ch.isLetter || ch.isNumber || ch == "-" || ch == "_" || ch == ":" {
            word.append(scanner.scanCharacter()!)
        }
        return word.isEmpty ? nil : word
    }

    private static func scanWhitespace(_ scanner: inout Scanner) {
        while let ch = scanner.peek(), ch.isWhitespace || ch == "\n" || ch == "\r" {
            _ = scanner.scanCharacter()
        }
    }
}

extension Scanner {
    fileprivate func peek() -> Character? {
        guard !isAtEnd else { return nil }
        // Save current position, scan one character, then restore
        let savedIndex = currentIndex
        guard let char = scanCharacter() else { return nil }
        currentIndex = savedIndex
        return char
    }
}
