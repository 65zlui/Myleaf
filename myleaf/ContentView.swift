import SwiftUI
import PDFKit

struct ContentView: View {
    @State var viewModel = EditorViewModel()

    var body: some View {
        Group {
            if viewModel.showWelcome {
                WelcomeView(
                    onBlankDocument: {
                        viewModel.newDocument()
                    },
                    onSelectTemplate: {
                        viewModel.showWelcome = false
                        viewModel.showTemplatePicker = true
                    },
                    onOpenFile: {
                        viewModel.openDocument()
                    }
                )
            } else {
                editorContent
            }
        }
        .focusedValue(\.editorViewModel, viewModel)
        .sheet(isPresented: $viewModel.showTemplatePicker) {
            TemplatePicker { template in
                viewModel.applyTemplate(template)
                viewModel.showWelcome = false
            }
        }
        .sheet(isPresented: $viewModel.showSettings) {
            SettingsView(
                toolManager: viewModel.toolManager,
                historyManager: viewModel.historyManager,
                onAutoSaveToggled: { viewModel.startAutoSaveIfNeeded() },
                onTectonicInstall: { viewModel.installTectonic() },
                onPandocInstall: { viewModel.installPandoc() },
                onUninstallComplete: { viewModel.onToolUninstalled() }
            )
        }
        .sheet(isPresented: $viewModel.showBibTeXImport) {
            BibTeXImportView(onInsertCitation: { entries in
                viewModel.insertCitations(entries)
            })
        }
    }

    // MARK: - Editor Content

    private var editorContent: some View {
        VStack(spacing: 0) {
            // Compiler not found banner with install option
            if case .notFound = viewModel.compilerStatus {
                compilerNotFoundBanner
            }

            // Tectonic installing progress
            if viewModel.installer.isInstalling {
                installProgressBanner(
                    progress: viewModel.installer.progress,
                    message: viewModel.installer.statusMessage
                )
            }

            // Pandoc installing progress
            if viewModel.isInstallingPandoc {
                installProgressBanner(
                    progress: viewModel.pandocInstallProgress,
                    message: viewModel.pandocInstallStatus
                )
            }

            // Main split view
            HSplitView {
                // Left: LaTeX editor with syntax highlighting
                LaTeXEditorView(text: $viewModel.document.sourceText)
                    .frame(minWidth: 300)

                // Right: PDF preview
                ZStack {
                    if let pdf = viewModel.pdfDocument {
                        PDFPreviewView(pdfDocument: pdf)
                    } else {
                        placeholderView
                    }

                    if viewModel.isCompiling {
                        ProgressView("Compiling...")
                            .padding()
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .frame(minWidth: 300)
            }

            // Error panel
            if let error = viewModel.errorMessage {
                errorPanel(error)
            }
        }
        .toolbar {
            toolbarContent
        }
        .navigationTitle(viewModel.windowTitle)
        .frame(minWidth: 800, minHeight: 500)
    }

    // MARK: - Subviews

    private var placeholderView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Press \u{2318}B to compile")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var compilerNotFoundBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("No LaTeX engine found.")
                .font(.callout)

            Button("Install Tectonic") {
                viewModel.installTectonic()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Spacer()

            Text("Or install MacTeX manually")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
    }

    private func installProgressBanner(progress: Double, message: String) -> some View {
        HStack(spacing: 12) {
            ProgressView(value: progress)
                .frame(width: 120)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.08))
    }

    private func errorPanel(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text("Error")
                    .font(.headline)
                Spacer()

                // If pandoc not found, show install button
                if error.contains("Pandoc") && !viewModel.exportService.isPandocInstalled {
                    Button("Install Pandoc") {
                        viewModel.errorMessage = nil
                        viewModel.installPandoc()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                Button("Dismiss") {
                    viewModel.errorMessage = nil
                }
                .buttonStyle(.borderless)
            }
            ScrollView {
                Text(error)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)
        }
        .padding(8)
        .background(Color.red.opacity(0.08))
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: { viewModel.compile() }) {
                Label("Compile", systemImage: "hammer.fill")
            }
            .disabled(viewModel.isCompiling || viewModel.compilerStatus == .notFound)
            .help("Compile LaTeX (\u{2318}B)")

            Menu {
                Button(action: { viewModel.exportPDF() }) {
                    Label("Export PDF...", systemImage: "doc.fill")
                }
                .disabled(viewModel.pdfDocument == nil)

                Button(action: { viewModel.exportWord() }) {
                    Label("Export Word...", systemImage: "doc.richtext.fill")
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help("Export document")

            Button(action: { viewModel.showBibTeXImportSheet() }) {
                Label("Import BibTeX", systemImage: "book.fill")
            }
            .help("Import BibTeX citations")

            statusIndicator
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch viewModel.compilerStatus {
        case .checking:
            ProgressView()
                .controlSize(.small)
        case .ready(let engine):
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help("\(engine.displayName) ready")
        case .notFound:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .help("No LaTeX engine found")
        }
    }
}

#Preview {
    ContentView()
}
