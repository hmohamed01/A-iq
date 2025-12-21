import SwiftData
import SwiftUI

// MARK: - Content View

/// Root view with tab navigation
/// Implements: Req 7.1, 8.2
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: AppState.Tab = .analyze

    /// Whether to show welcome dialog on launch (user preference)
    @AppStorage("showWelcomeOnLaunch") private var showWelcomeOnLaunch = true
    @State private var showWelcome = false

    var body: some View {
        TabView(selection: $selectedTab) {
            AnalysisView()
                .tabItem {
                    Label(AppState.Tab.analyze.rawValue, systemImage: AppState.Tab.analyze.systemImage)
                }
                .tag(AppState.Tab.analyze)

            HistoryView()
                .tabItem {
                    Label(AppState.Tab.history.rawValue, systemImage: AppState.Tab.history.systemImage)
                }
                .tag(AppState.Tab.history)
        }
        .frame(minWidth: 800, minHeight: 600)
        .sheet(isPresented: $showWelcome) {
            WelcomeView(isPresented: $showWelcome)
        }
        .onAppear {
            // Inject SwiftData ModelContext into AppState for history persistence
            appState.modelContext = modelContext

            if showWelcomeOnLaunch {
                showWelcome = true
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(AppState())
}
