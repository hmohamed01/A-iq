import SwiftUI
import UniformTypeIdentifiers

// MARK: - Analysis View

/// Main analysis interface with drop zone (A-IQ design system)
/// Implements: Req 1.1, 7.1, 7.2, 7.3
struct AnalysisView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedResultID: UUID?

    var body: some View {
        HSplitView {
            // Left panel: Drop zone and controls
            dropZonePanel
                .frame(minWidth: 340, maxWidth: 400)

            // Right panel: Results
            resultsPanel
                .frame(minWidth: 620)
        }
        .background(AIQColors.paperWhite)
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
        VStack(spacing: AIQSpacing.lg) {
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
                .foregroundStyle(AIQColors.tertiaryText)
        }
        .padding(AIQSpacing.lg)
        .background(AIQColors.paperWhite)
    }

    private var analysisProgressView: some View {
        VStack(spacing: AIQSpacing.lg) {
            // Circular progress indicator (Circular)
            ZStack {
                Circle()
                    .stroke(AIQColors.subtleBorder, lineWidth: 6)
                    .frame(width: 80, height: 80)

                Circle()
                    .trim(from: 0, to: appState.analysisProgress)
                    .stroke(
                        AIQColors.accent,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.3), value: appState.analysisProgress)

                Text("\(Int(appState.analysisProgress * 100))%")
                    .font(.title3.weight(.medium).monospacedDigit())
                    .foregroundStyle(AIQColors.primaryText)
            }

            Text("Analyzing...")
                .font(.headline.weight(.medium))
                .foregroundStyle(AIQColors.primaryText)

            if !appState.batchQueue.isEmpty {
                Text("\(appState.batchResults.count) of \(appState.batchQueue.count) complete")
                    .font(.subheadline)
                    .foregroundStyle(AIQColors.secondaryText)
            }

            Button("Cancel") {
                appState.cancelAnalysis()
            }
            .buttonStyle(AIQSecondaryButton())
        }
        .padding(AIQSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aiqCard()
    }

    private var controlButtons: some View {
        HStack(spacing: AIQSpacing.md) {
            Button(action: openFile) {
                Label("Open File", systemImage: "doc")
            }
            .buttonStyle(AIQSecondaryButton())

            Button(action: openFolder) {
                Label("Open Folder", systemImage: "folder")
            }
            .buttonStyle(AIQSecondaryButton())

            Button(action: pasteFromClipboard) {
                Label("Paste", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(AIQSecondaryButton())
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
        .background(AIQColors.paperWhite)
    }

    private var batchResultsList: some View {
        HSplitView {
            // Left: Batch results list
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Batch Results")
                        .font(.headline)
                        .foregroundStyle(AIQColors.primaryText)
                    Spacer()
                    Text("\(appState.batchResults.count) images")
                        .font(.subheadline)
                        .foregroundStyle(AIQColors.secondaryText)
                }
                .padding(.horizontal, AIQSpacing.md)
                .padding(.vertical, AIQSpacing.sm)
                .background(AIQColors.subtleBorder.opacity(0.3))

                List(appState.batchResults, selection: $selectedResultID) { result in
                    HStack(spacing: AIQSpacing.md) {
                        // Thumbnail
                        if let thumbnail = result.imageThumbnail {
                            Image(thumbnail, scale: 1.0, label: Text("Thumbnail"))
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: AIQRadius.sm, style: .continuous))
                        } else {
                            RoundedRectangle(cornerRadius: AIQRadius.sm, style: .continuous)
                                .fill(AIQColors.subtleBorder)
                                .frame(width: 44, height: 44)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.imageSource.displayName)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(AIQColors.primaryText)
                                .lineLimit(1)

                            HStack(spacing: 4) {
                                Circle()
                                    .fill(classificationColor(result.classification))
                                    .frame(width: 8, height: 8)

                                Text(result.classification.shortName)
                                    .font(.caption)
                                    .foregroundStyle(classificationColor(result.classification))
                            }
                        }

                        Spacer()

                        Text("\(result.scorePercentage)%")
                            .font(.subheadline.weight(.medium).monospacedDigit())
                            .foregroundStyle(AIQColors.secondaryText)
                    }
                    .padding(.vertical, 4)
                    .tag(result.id)
                }
                .listStyle(.sidebar)
                .onAppear {
                    if selectedResultID == nil, let first = appState.batchResults.first {
                        selectedResultID = first.id
                    }
                }
            }
            .frame(minWidth: 240, idealWidth: 300)

            // Right: Detail view
            Group {
                if let selectedID = selectedResultID,
                   let selectedResult = appState.batchResults.first(where: { $0.id == selectedID })
                {
                    ResultsDetailView(result: selectedResult)
                } else if let firstResult = appState.batchResults.first {
                    ResultsDetailView(result: firstResult)
                } else {
                    Text("Select a result")
                        .foregroundStyle(AIQColors.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 380)
        }
    }

    private var emptyResultsView: some View {
        VStack(spacing: AIQSpacing.lg) {
            ZStack {
                Circle()
                    .fill(AIQColors.accent.opacity(0.08))
                    .frame(width: 100, height: 100)

                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(AIQColors.accent.opacity(0.6))
            }

            VStack(spacing: AIQSpacing.sm) {
                Text("No Analysis Results")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(AIQColors.secondaryText)

                Text("Drop an image or use the buttons to analyze")
                    .font(.subheadline)
                    .foregroundStyle(AIQColors.tertiaryText)
            }
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
        case .likelyAuthentic: return AIQColors.authentic
        case .uncertain: return AIQColors.uncertain
        case .likelyAIGenerated, .confirmedAIGenerated: return AIQColors.aiGenerated
        }
    }
}

// MARK: - Preview

#Preview {
    AnalysisView()
        .environmentObject(AppState())
        .frame(width: 900, height: 600)
}
