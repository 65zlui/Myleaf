import Foundation

/// Represents a single parsed BibTeX entry.
struct BibTeXEntry: Identifiable, Equatable {
    let id: String          // e.g. "smith2023ai"
    let type: String        // e.g. "article", "book", "inproceedings"
    let fields: [String: String]

    var title: String {
        fields["title"]?.cleanBraces ?? ""
    }

    var author: String {
        fields["author"]?.cleanBraces ?? ""
    }

    var year: String {
        fields["year"] ?? ""
    }

    /// Display string for the import list
    var displayString: String {
        var parts: [String] = []
        if !author.isEmpty {
            // Shorten author list
            let names = author.split(separator: " and ")
            if names.count > 3 {
                parts.append("\(names[0]) et al.")
            } else {
                parts.append(author)
            }
        }
        if !year.isEmpty {
            parts.append("(\(year))")
        }
        let citation = parts.joined(separator: " ")
        if !title.isEmpty {
            return "\(citation) \u{2014} \(title)"
        }
        return citation.isEmpty ? id : "\(citation): \(id)"
    }

    /// LaTeX \cite{} command for this entry
    var citeCommand: String {
        "\\cite{\(id)}"
    }

    /// Full BibTeX entry as a string
    var entryString: String {
        let header = "@\(type){\(id),"
        var lines = [header]
        for (key, value) in fields {
            lines.append("  \(key) = {\(value)},")
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    static func == (lhs: BibTeXEntry, rhs: BibTeXEntry) -> Bool {
        lhs.id == rhs.id && lhs.type == rhs.type && lhs.fields == rhs.fields
    }
}

extension String {
    /// Remove LaTeX brace formatting like {A Study of AI} -> A Study of AI
    var cleanBraces: String {
        var result = self
        if result.hasPrefix("{") && result.hasSuffix("}") {
            result = String(result.dropFirst().dropLast())
        }
        return result
    }
}
