import SwiftUI
import AppKit

/// Shows the structured build log of the most recent LaTeX compilation:
/// engine, input, command, engine output, exit status, and duration.
struct BuildLogView: View {
    @Environment(\.dismiss) private var dismiss

    let log: String
    let logFile: URL?

    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label("Build Log", systemImage: "doc.text.magnifyingglass")
                    .font(.title2.bold())

                Spacer()

                if let logFile {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([logFile])
                    }
                }

                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(log, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copied = false
                    }
                }

                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            ScrollView(.vertical) {
                Text(log.isEmpty ? "No log available." : log)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(Color(nsColor: .textBackgroundColor))

            Divider()

            HStack(spacing: 12) {
                if let logFile {
                    Text(logFile.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("Log file unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Logs Folder") {
                    try? FileManager.default.createDirectory(
                        at: BuildLogStore.directory,
                        withIntermediateDirectories: true
                    )
                    NSWorkspace.shared.open(BuildLogStore.directory)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 780, height: 560)
    }
}
