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

            Divider()

            Button("Delete All History...") {
                appState.showDeleteAllHistoryConfirmation = true
            }
        }

        // View menu
        CommandGroup(after: .sidebar) {
            Divider()

            Button("Show Analysis") {
                appState.selectedTab = .analyze
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("Show History") {
                appState.selectedTab = .history
            }
            .keyboardShortcut("2", modifiers: .command)
        }

        // Help menu
        CommandGroup(replacing: .help) {
            Button("About A-IQ") {
                showAboutWindow()
            }

            Divider()

            Button("Report an Issue...") {
                reportIssue()
            }
        }

        // Remove tab bar menu items (Show All Tabs, Show/Hide Tab Bar)
        // These don't apply to this app
        CommandGroup(replacing: .windowArrangement) {}
    }

    // MARK: Command Actions

    private func openFile() {
        Task {
            await appState.openFilePicker()
        }
    }

    private func openFolder() {
        Task {
            await appState.openFolderPicker()
        }
    }

    private func pasteFromClipboard() {
        appState.startAnalyzeClipboard()
    }

    private func exportReport() {
        Task { @MainActor in
            guard let result = appState.currentAnalysis else {
                // Show error if no result available
                let alert = NSAlert()
                alert.messageText = "No Analysis Result"
                alert.informativeText = "Please analyze an image before exporting a report."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
                return
            }
            
            let generator = ReportGenerator()
            let format = appState.settingsManager.defaultExportFormat
            let filename = result.imageSource.displayName
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "\\", with: "_")
            let suggestedName = "\(filename)_analysis.\(format.fileExtension)"
            
            let success = await generator.exportWithDialog(
                result,
                format: format,
                suggestedFilename: suggestedName
            )
            
            if !success {
                let alert = NSAlert()
                alert.messageText = "Export Failed"
                alert.informativeText = "Could not export the analysis report. Please try again."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    private func showAboutWindow() {
        NSApplication.shared.orderFrontStandardAboutPanel(nil)
    }

    private func reportIssue() {
        if let url = URL(string: "https://agenticstudio.gumroad.com/l/mrxnbp") {
            NSWorkspace.shared.open(url)
        }
    }
}

#if os(macOS)
    import AppKit
#endif
