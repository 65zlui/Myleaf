import SwiftUI

struct TemplatePicker: View {
    let onSelect: (Template) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: TemplateCategory = .conference
    @State private var searchText = ""

    private let manager = TemplateManager.shared

    private var filteredTemplates: [Template] {
        let templates = manager.templates(for: selectedCategory)
        if searchText.isEmpty { return templates }
        let query = searchText.lowercased()
        return templates.filter {
            $0.name.lowercased().contains(query) ||
            $0.subtitle.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Choose a Template")
                    .font(.title2.bold())
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            HStack(spacing: 0) {
                // Category sidebar
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(TemplateCategory.allCases) { cat in
                        Button(action: { selectedCategory = cat }) {
                            Label(cat.displayName, systemImage: cat.icon)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .background(
                                    selectedCategory == cat
                                    ? Color.accentColor.opacity(0.15)
                                    : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .frame(width: 180)
                .padding(8)

                Divider()

                // Template grid
                VStack(spacing: 0) {
                    // Search
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search templates...", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                            ForEach(filteredTemplates) { template in
                                templateCard(template)
                            }
                        }
                        .padding(12)
                    }
                }
            }
        }
        .frame(width: 650, height: 450)
    }

    private func templateCard(_ template: Template) -> some View {
        Button(action: {
            onSelect(template)
            dismiss()
        }) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "doc.text.fill")
                    .font(.title)
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)

                Text(template.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(template.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
        }
        .buttonStyle(.plain)
    }
}
