import Foundation

enum TemplateCategory: String, CaseIterable, Identifiable {
    case conference = "conference"
    case journal = "journal"
    case thesis = "thesis"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .conference: return "Conference Papers"
        case .journal: return "Journal Papers"
        case .thesis: return "Thesis / Dissertation"
        }
    }

    var icon: String {
        switch self {
        case .conference: return "person.3.fill"
        case .journal: return "text.book.closed.fill"
        case .thesis: return "graduationcap.fill"
        }
    }
}

struct Template: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let category: TemplateCategory
    let content: String
}
