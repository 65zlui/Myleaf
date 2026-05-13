import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    var toolManager: ToolManager
    var historyManager: ProjectHistoryManager
    var onAutoSaveToggled: () -> Void
    var onTectonicInstall: () -> Void
    var onPandocInstall: () -> Void
    var onUninstallComplete: () -> Void

    @State private var confirmUninstall: ManagedTool?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    autoSaveSection
                    toolManagementSection
                    diskUsageSection
                }
                .padding()
            }
        }
        .frame(width: 520, height: 480)
        .alert("Confirm Uninstall", isPresented: .init(
            get: { confirmUninstall != nil },
            set: { if !$0 { confirmUninstall = nil } }
        )) {
            Button("Cancel", role: .cancel) { confirmUninstall = nil }
            Button("Uninstall", role: .destructive) {
                if let tool = confirmUninstall {
                    performUninstall(tool)
                }
                confirmUninstall = nil
            }
        } message: {
            if let tool = confirmUninstall {
                Text("Remove \(tool.displayName) and all its data? This cannot be undone.")
            }
        }
    }

    // MARK: - Auto-Save Section

    private var autoSaveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Editor", systemImage: "pencil.and.outline")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: Binding(
                    get: { historyManager.isAutoSaveEnabled },
                    set: { newValue in
                        historyManager.isAutoSaveEnabled = newValue
                        onAutoSaveToggled()
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-save")
                            .font(.body)
                        Text("Automatically save changes every 30 seconds")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // File path note
                Text("Auto-save writes to the document's file path (displayed in the title bar). Unsaved new documents will not be auto-saved until saved to a location first.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Tool Management Section

    private var toolManagementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Managed Tools", systemImage: "wrench.and.screwdriver.fill")
                .font(.headline)

            ForEach(ManagedTool.allCases) { tool in
                toolRow(tool)
            }

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
                        .font(.caption)
                }
                .padding(8)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func toolRow(_ tool: ManagedTool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: tool.icon)
                .font(.title2)
                .foregroundStyle(toolManager.isInstalled(tool) ? Color.accentColor : .secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(tool.displayName)
                        .font(.body.bold())

                    if case .installed(let version, _, _) = toolManager.toolStates[tool] {
                        if let v = version {
                            Text(v)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Text(tool.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if case .installed(_, let size, let path) = toolManager.toolStates[tool] {
                    Text("\(size.formattedFileSize) - \(path)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            // Status + action
            if toolManager.isInstalled(tool) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)

                    Button("Uninstall") {
                        confirmUninstall = tool
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                }
            } else if toolManager.isWorking && toolManager.workingTool == tool {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button("Install") {
                    switch tool {
                    case .tectonic: onTectonicInstall()
                    case .pandoc: onPandocInstall()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Disk Usage Section

    private var diskUsageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Disk Usage", systemImage: "internaldrive.fill")
                .font(.headline)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tool binaries")
                        .font(.callout)
                    let cacheSize = toolManager.tectonicCacheSize()
                    if cacheSize > 0 {
                        Text("Tectonic package cache: \(cacheSize.formattedFileSize)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Total: \(toolManager.totalDiskUsage().formattedFileSize)")
                        .font(.callout.bold())
                }
                Spacer()
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

            Text("Tools are stored in ~/Library/Application Support/myleaf/bin/")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Actions

    private func performUninstall(_ tool: ManagedTool) {
        do {
            try toolManager.uninstall(tool)
            onUninstallComplete()
        } catch {
            errorMessage = "Failed to uninstall \(tool.displayName): \(error.localizedDescription)"
        }
    }
}
