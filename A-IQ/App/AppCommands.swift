import SwiftUI

// MARK: - App Commands

/// Custom menu commands for the application
/// Implements: Req NFR-U1
struct AppCommands: Commands {
    @ObservedObject var appState: AppState

    var body: some Commands {
        // Replace the default New Window command
        CommandGroup(replacing: .newItem) {
            Button("Open Image...") {
                openFile()
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Open Folder...") {
                openFolder()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Divider()

            Button("Paste Image") {
                pasteFromClipboard()
            }
            .keyboardShortcut("v", modifiers: .command)
        }

        // File menu additions
        CommandGroup(after: .newItem) {
            Divider()

            Button("Export Report...") {
                exportReport()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(appState.currentAnalysis == nil)
        }

        // View menu
        CommandGroup(after: .sidebar) {
            Divider()

            Button("Show Analysis") {
                // Navigate to analysis tab
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("Show History") {
                // Navigate to history tab
            }
            .keyboardShortcut("2", modifiers: .command)
        }

        // Help menu addition
        CommandGroup(replacing: .help) {
            Button("A-IQ Help") {
                openHelp()
            }
            .keyboardShortcut("?", modifiers: .command)

            Divider()

            Button("Report an Issue...") {
                reportIssue()
            }
        }
    }

    // MARK: Command Actions

    private func openFile() {
        // TODO: Implement with ImageInputHandler
        // Task {
        //     let urls = await appState.inputHandler.presentFilePicker(allowsMultiple: true)
        //     let sources = urls.compactMap { try? appState.inputHandler.validateFile(at: $0) }
        //     await appState.analyzeImages(sources)
        // }
    }

    private func openFolder() {
        // TODO: Implement with ImageInputHandler
    }

    private func pasteFromClipboard() {
        // TODO: Implement with ImageInputHandler
    }

    private func exportReport() {
        // TODO: Implement with ReportGenerator
    }

    private func openHelp() {
        if let url = URL(string: "https://github.com/yourusername/A-IQ#readme") {
            NSWorkspace.shared.open(url)
        }
    }

    private func reportIssue() {
        if let url = URL(string: "https://github.com/yourusername/A-IQ/issues/new") {
            NSWorkspace.shared.open(url)
        }
    }
}

#if os(macOS)
    import AppKit
#endif
