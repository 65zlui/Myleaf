import SwiftUI

// MARK: - FocusedValue for EditorViewModel

struct FocusedEditorViewModelKey: FocusedValueKey {
    typealias Value = EditorViewModel
}

extension FocusedValues {
    var editorViewModel: EditorViewModel? {
        get { self[FocusedEditorViewModelKey.self] }
        set { self[FocusedEditorViewModelKey.self] = newValue }
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// myleaf restores the last project itself through ProjectHistoryManager.
    /// Disable AppKit's automatic window restoration: otherwise an old
    /// NSTextView buffer can reappear on launch out of sync with the view
    /// model (observed as an "Untitled" window containing a previously used
    /// template after the saved application state was restored).
    func applicationShouldSaveSecureApplicationState(_ app: NSApplication) -> Bool {
        false
    }

    func applicationShouldRestoreSecureApplicationState(_ app: NSApplication) -> Bool {
        false
    }
}

// MARK: - App

@main
struct myleafApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @FocusedValue(\.editorViewModel) var viewModel

    init() {
        AntiDebug.apply()
        MemoryMonitor.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            // File menu
            CommandGroup(replacing: .newItem) {
                Button("New Document") {
                    viewModel?.newDocument()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New from Template...") {
                    viewModel?.newFromTemplate()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Divider()

                Button("Open...") {
                    viewModel?.openDocument()
                }
                .keyboardShortcut("o", modifiers: .command)

                Divider()

                Button("Save") {
                    viewModel?.saveDocument()
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Save As...") {
                    viewModel?.saveDocumentAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Divider()

                Button("Export PDF...") {
                    viewModel?.exportPDF()
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(viewModel?.pdfDocument == nil)

                Button("Export Word...") {
                    viewModel?.exportWord()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }

            // Build menu
            CommandMenu("Build") {
                Button("Compile") {
                    viewModel?.compile()
                }
                .keyboardShortcut("b", modifiers: .command)
                .disabled(viewModel?.isCompiling == true)

                Button("Show Build Log") {
                    viewModel?.showBuildLogPanel()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(viewModel?.lastBuildLog == nil)
            }

            // myleaf menu > Settings
            CommandGroup(after: .appSettings) {
                Button("Settings...") {
                    viewModel?.showSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
