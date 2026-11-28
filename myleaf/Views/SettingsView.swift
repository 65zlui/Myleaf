import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    var toolManager: ToolManager
    var historyManager: ProjectHistoryManager
    var viewModel: EditorViewModel
    var onAutoSaveToggled: () -> Void
    var onTectonicInstall: () -> Void
    var onPandocInstall: () -> Void
    var onUninstallComplete: () -> Void

    @State private var confirmUninstall: ManagedTool?
    @State private var errorMessage: String?
    @State private var selectedTab = 0
    @State private var installedCopies: [InstalledCopy] = []

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

            TabView(selection: $selectedTab) {
                generalTab
                    .tabItem { Label("General", systemImage: "gearshape") }
                    .tag(0)

                toolsTab
                    .tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }
                    .tag(1)

                PerformancePanel(viewModel: viewModel)
                    .tabItem { Label("Performance", systemImage: "chart.xyaxis.line") }
                    .tag(2)
            }
            .padding(8)
        }
        .frame(width: 780, height: 700)
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
            if case .checking = toolManager.toolStates[tool] {
                ProgressView()
                    .controlSize(.small)
            } else if toolManager.isInstalled(tool) {
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
            } else if isInstalling(tool) {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(installStatus(for: tool))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Button("Install") {
                    switch tool {
                    case .tectonic: onTectonicInstall()
                    case .pandoc: onPandocInstall()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isInstalling(.tectonic) || isInstalling(.pandoc))
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

    // MARK: - Tabs

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                autoSaveSection
                updatesSection
                installationSection
            }
            .padding(16)
        }
    }

    private var installationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Installation", systemImage: "shippingbox")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Current version")
                        .font(.callout)
                    Spacer()
                    Text(currentVersion)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Bundle")
                        .font(.callout)
                    Spacer()
                    Text(Bundle.main.bundlePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Divider()

                if installedCopies.count > 1 {
                    Label("\(installedCopies.count) copies found", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)

                    ForEach(installedCopies) { copy in
                        HStack(spacing: 8) {
                            Text(copy.displayVersion)
                                .font(.caption.monospacedDigit())
                                .frame(width: 54, alignment: .leading)

                            Text(copy.url.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer()

                            Button("Reveal") {
                                NSWorkspace.shared.activateFileViewerSelecting([copy.url])
                            }
                            .controlSize(.small)
                        }
                    }

                    Text("Remove older copies to prevent launching a different version.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else if installedCopies.count == 1 {
                    Label("Single installation", systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                } else {
                    Text("Run Refresh to scan installed copies.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                HStack {
                    Spacer()
                    Button("Refresh") {
                        installedCopies = InstallationChecker.copies()
                    }
                    .controlSize(.small)
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }
        .task {
            installedCopies = InstallationChecker.copies()
        }
    }

    // MARK: - Updates

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Updates", systemImage: "arrow.triangle.2.circlepath")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    updateStatus
                    Spacer(minLength: 8)
                    updateActions
                }

                if case .available(let release) = viewModel.updateChecker.state {
                    if !release.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(release.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(5)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Link("Release notes on GitHub", destination: release.pageURL)
                        .font(.caption)
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch viewModel.updateChecker.state {
        case .idle:
            Text("Check GitHub for a newer release.")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking for updates...")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .upToDate(let current):
            Label("You're up to date (myleaf \(current)).", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
        case .available(let release):
            VStack(alignment: .leading, spacing: 2) {
                Text("myleaf \(release.version) is available")
                    .font(.callout.bold())
                Text("You have myleaf \(currentVersion).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .downloading(let version):
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Downloading myleaf \(version)...")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .installerOpened(let version):
            VStack(alignment: .leading, spacing: 2) {
                Text("Installer opened for myleaf \(version).")
                    .font(.callout.bold())
                Text("Complete the installation in the Installer window. myleaf will quit and can be reopened afterwards.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var updateActions: some View {
        switch viewModel.updateChecker.state {
        case .available(let release):
            HStack(spacing: 8) {
                Button("Check Again") { checkForUpdates() }
                    .controlSize(.small)
                Button("Download & Install") { installUpdate(release) }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
            }
        case .checking, .downloading:
            EmptyView()
        default:
            Button("Check for Updates") { checkForUpdates() }
                .controlSize(.small)
        }
    }

    private func checkForUpdates() {
        let version = currentVersion
        Task {
            await viewModel.updateChecker.check(currentVersion: version)
        }
    }

    private func installUpdate(_ release: UpdateRelease) {
        let version = currentVersion
        Task {
            await viewModel.updateChecker.downloadAndOpenInstaller(
                for: release,
                currentVersion: version
            )
        }
    }

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private var toolsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                toolManagementSection
                diskUsageSection
            }
            .padding(16)
        }
    }

    // MARK: - Install State

    /// Installation runs through the view model's installers (the same ones the
    /// in-editor banner shows). Without this, tapping Install inside this sheet
    /// looked like nothing happened: the progress banner lives behind the sheet.
    private func isInstalling(_ tool: ManagedTool) -> Bool {
        switch tool {
        case .tectonic: return viewModel.installer.isInstalling
        case .pandoc: return viewModel.isInstallingPandoc
        }
    }

    private func installStatus(for tool: ManagedTool) -> String {
        let status: String
        switch tool {
        case .tectonic: status = viewModel.installer.statusMessage
        case .pandoc: status = viewModel.pandocInstallStatus
        }
        return status.isEmpty ? "Installing…" : status
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
