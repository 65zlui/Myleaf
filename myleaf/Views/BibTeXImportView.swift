import SwiftUI
import UniformTypeIdentifiers

struct BibTeXImportView: View {
    @Environment(\.dismiss) private var dismiss

    var onInsertCitation: ([BibTeXEntry]) -> Void

    @State private var entries: [BibTeXEntry] = []
    @State private var selectedEntries: Set<String> = []
    @State private var errorMessage: String?
    @State private var fileName: String = ""
    @State private var searchText = ""

    private var filteredEntries: [BibTeXEntry] {
        if searchText.isEmpty { return entries }
        let query = searchText.lowercased()
        return entries.filter {
            $0.id.lowercased().contains(query) ||
            $0.title.lowercased().contains(query) ||
            $0.author.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Import BibTeX")
                    .font(.title2.bold())
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            // Content
            VStack(alignment: .leading, spacing: 12) {
                // File selection button
                HStack {
                    Button(action: openFile) {
                        Label(fileName.isEmpty ? "Choose .bib file..." : fileName,
                              systemImage: fileName.isEmpty ? "folder" : "doc.text.fill")
                    }

                    Spacer()
                    Text("\(entries.count) entries")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                // Search field
                if !entries.isEmpty {
                    TextField("Search by title, author, or key...", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .overlay(
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary),
                            alignment: .leading
                        )
                }

                // Error message
                if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                        Spacer()
                        Button("Dismiss") { errorMessage = nil }
                            .buttonStyle(.borderless)
                    }
                    .padding(8)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }

                // Entry list
                if entries.isEmpty {
                    emptyState
                } else {
                    entryList
                }
            }
            .padding()

            // Footer actions
            if !selectedEntries.isEmpty {
                Divider()
                HStack {
                    Text("\(selectedEntries.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Insert Citation\(selectedEntries.count > 1 ? "s" : "")") {
                        let selected = entries.filter { selectedEntries.contains($0.id) }
                        onInsertCitation(selected)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
        .frame(width: 520, height: 460)
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "book")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No BibTeX entries loaded")
                .foregroundStyle(.secondary)
            Text("Open a .bib file to import references")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var entryList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(filteredEntries) { entry in
                    entryRow(entry)
                }
            }
        }
    }

    private func entryRow(_ entry: BibTeXEntry) -> some View {
        Button {
            if selectedEntries.contains(entry.id) {
                selectedEntries.remove(entry.id)
            } else {
                selectedEntries.insert(entry.id)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selectedEntries.contains(entry.id)
                      ? "checkmark.circle.fill"
                      : "circle")
                    .foregroundStyle(selectedEntries.contains(entry.id) ? Color.accentColor : .secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title.isEmpty ? entry.id : entry.title)
                        .font(.body)
                        .lineLimit(1)
                    Text(entry.displayString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text("@\(entry.type)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "bib")].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            entries = try BibTeXParser.parseFile(at: url)
            fileName = url.lastPathComponent
            errorMessage = nil
            selectedEntries = []
        } catch {
            errorMessage = error.localizedDescription
            entries = []
            fileName = ""
        }
    }
}
