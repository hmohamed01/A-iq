import AppKit
import SwiftData
import SwiftUI

/// A-IQ: AI Image Detection Tool for macOS
/// Main application entry point
/// Implements: Req 11.1, 11.2, 11.3, 11.6
@main
struct AIQApp: App {
    /// Shared application state
    @StateObject private var appState = AppState()

    /// SwiftData model container for persistence
    let modelContainer: ModelContainer

    init() {
        // Disable window tabbing (removes tab bar and "Show All Tabs" menu items)
        NSWindow.allowsAutomaticWindowTabbing = false

        // Initialize SwiftData container
        do {
            let schema = Schema([AnalysisRecord.self])
            let configuration = ModelConfiguration(
                "A-IQ",
                schema: schema,
                isStoredInMemoryOnly: false
            )
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to initialize SwiftData: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .modelContainer(modelContainer)
        }
        .commands {
            AppCommands(appState: appState)
        }
        .defaultSize(width: 1200, height: 700)

        #if os(macOS)
            Settings {
                SettingsView()
                    .environmentObject(appState.settingsManager)
            }
        #endif
    }
}
