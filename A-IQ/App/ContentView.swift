import SwiftData
import SwiftUI

// MARK: - Content View

/// Root view with tab navigation
/// Implements: Req 7.1, 8.2
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext

    /// Whether to show welcome dialog on subsequent launches (user preference)
    @AppStorage("showWelcomeOnLaunch") private var showWelcomeOnLaunch = true
    /// Tracks whether the initial welcome has ever been shown (persists across installs)
    @AppStorage("hasShownInitialWelcome") private var hasShownInitialWelcome = false
    @State private var showWelcome = false

    var body: some View {
        Group {
            switch appState.selectedTab {
            case .analyze:
                AnalysisView()
            case .history:
                HistoryView()
            }
        }
        .frame(minWidth: 1020, minHeight: 600)
        .toolbar {
            // Tab picker in principal position (centered, fixed)
            ToolbarItem(placement: .principal) {
                HStack(spacing: 0) {
                    ForEach(AppState.Tab.allCases, id: \.self) { tab in
                        Button {
                            appState.selectedTab = tab
                        } label: {
                            Image(systemName: tab.systemImage)
                                .frame(width: 28, height: 20)
                        }
                        .buttonStyle(TabSegmentButtonStyle(isSelected: appState.selectedTab == tab))
                        .help(tab.rawValue)
                    }
                }
                .padding(2)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .sheet(isPresented: $showWelcome) {
            WelcomeView(isPresented: $showWelcome)
        }
        .alert("Delete All History?", isPresented: $appState.showDeleteAllHistoryConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                appState.deleteAllHistory()
            }
        } message: {
            Text("This will permanently delete all analysis history. This action cannot be undone.")
        }
        .onAppear {
            // Inject SwiftData ModelContext into AppState for history persistence
            appState.modelContext = modelContext

            // Show welcome on first-ever launch, or on subsequent launches if user prefers
            if !hasShownInitialWelcome {
                showWelcome = true
                hasShownInitialWelcome = true
                // Reset to default so checkbox appears checked on first launch
                showWelcomeOnLaunch = true
            } else if showWelcomeOnLaunch {
                showWelcome = true
            }
        }
    }
}

// MARK: - Tab Segment Button Style

/// Custom button style for segmented tab control
private struct TabSegmentButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? Color(nsColor: .controlAccentColor).opacity(0.15) : Color.clear)
            )
            .contentShape(Rectangle())
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(AppState())
}
