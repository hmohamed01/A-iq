import SwiftUI
import UniformTypeIdentifiers

// MARK: - Analysis View

/// Main analysis interface with drop zone
/// Implements: Req 1.1, 7.1, 7.2, 7.3
struct AnalysisView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedResultID: UUID?

    var body: some View {
        HSplitView {
            // Left panel: Drop zone and controls
            dropZonePanel
                .frame(minWidth: 300, idealWidth: 400)

            // Right panel: Results
            resultsPanel
                .frame(minWidth: 400)
        }
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Button(action: openFile) {
                    Label("Open", systemImage: "doc.badge.plus")
                }
                .help("Open image file (⌘O)")
            }
            ToolbarItem(placement: .secondaryAction) {
                Button(action: openFolder) {
                    Label("Folder", systemImage: "folder.badge.plus")
                }
                .help("Open folder for batch analysis (⇧⌘O)")
            }
        }
        .alert("Error", isPresented: .constant(appState.errorMessage != nil)) {
            Button("OK") {
                appState.errorMessage = nil
            }
        } message: {
            Text(appState.errorMessage ?? "")
        }
    }

    // MARK: Drop Zone Panel

    private var dropZonePanel: some View {
        VStack(spacing: 20) {
            if appState.isAnalyzing {
                analysisProgressView
            } else {
                DropZoneView { urls in
                    handleDroppedFiles(urls)
                }
            }

            controlButtons

            // Status message
            Text(appState.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var analysisProgressView: some View {
        VStack(spacing: 16) {
            ProgressView(value: appState.analysisProgress)
                .progressViewStyle(.linear)

            Text("Analyzing... \(Int(appState.analysisProgress * 100))%")
                .foregroundStyle(.secondary)

            if !appState.batchQueue.isEmpty {
                Text("\(appState.batchResults.count) of \(appState.batchQueue.count) complete")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Button("Cancel") {
                appState.cancelAnalysis()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var controlButtons: some View {
        HStack(spacing: 12) {
            Button(action: openFile) {
                Label("Open File", systemImage: "doc")
            }
            .buttonStyle(.bordered)

            Button(action: openFolder) {
                Label("Open Folder", systemImage: "folder")
            }
            .buttonStyle(.bordered)

            Button(action: pasteFromClipboard) {
                Label("Paste", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("v", modifiers: .command)
        }
    }

    // MARK: Results Panel

    private var resultsPanel: some View {
        Group {
            if !appState.batchResults.isEmpty && appState.batchResults.count > 1 {
                batchResultsList
            } else if let result = appState.currentAnalysis {
                ResultsDetailView(result: result)
            } else {
                emptyResultsView
            }
        }
    }

    private var batchResultsList: some View {
        NavigationSplitView {
            List(appState.batchResults, selection: $selectedResultID) { result in
                HStack {
                    // Thumbnail
                    if let thumbnail = result.imageThumbnail {
                        Image(thumbnail, scale: 1.0, label: Text("Thumbnail"))
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.2))
                            .frame(width: 40, height: 40)
                    }

                    VStack(alignment: .leading) {
                        Text(result.imageSource.displayName)
                            .lineLimit(1)

                        Text(result.classification.shortName)
                            .font(.caption)
                            .foregroundStyle(classificationColor(result.classification))
                    }

                    Spacer()

                    Text("\(result.scorePercentage)%")
                        .font(.caption)
                        .monospacedDigit()
                }
                .tag(result.id)
            }
            .navigationTitle("Batch Results (\(appState.batchResults.count))")
            .onAppear {
                // Select first result by default
                if selectedResultID == nil, let first = appState.batchResults.first {
                    selectedResultID = first.id
                }
            }
        } detail: {
            if let selectedID = selectedResultID,
               let selectedResult = appState.batchResults.first(where: { $0.id == selectedID })
            {
                ResultsDetailView(result: selectedResult)
            } else if let firstResult = appState.batchResults.first {
                ResultsDetailView(result: firstResult)
            } else {
                Text("Select a result")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("No Analysis Results")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text("Drop an image or use the buttons to analyze")
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

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

    private func handleDroppedFiles(_ urls: [URL]) {
        appState.handleDroppedFiles(urls)
    }

    // MARK: Helpers

    private func classificationColor(_ classification: OverallClassification) -> Color {
        switch classification {
        case .likelyAuthentic: return .green
        case .uncertain: return .yellow
        case .likelyAIGenerated, .confirmedAIGenerated: return .red
        }
    }
}

// MARK: - Preview

#Preview {
    AnalysisView()
        .environmentObject(AppState())
        .frame(width: 900, height: 600)
}
