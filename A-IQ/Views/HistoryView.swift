import SwiftData
import SwiftUI

// MARK: - History View

/// Past analyses list with search and filter
/// Implements: Req 8.2, 8.3, 8.4
struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AnalysisRecord.timestamp, order: .reverse) private var records: [AnalysisRecord]

    @State private var searchText: String = ""
    @State private var selectedClassification: OverallClassification?
    @State private var selectedRecordIDs: Set<AnalysisRecord.ID> = []
    @State private var showingDeleteConfirmation: Bool = false
    @State private var recordsToDelete: [AnalysisRecord] = []

    var body: some View {
        NavigationSplitView {
            // Sidebar with list
            historyList
                .navigationSplitViewColumnWidth(min: 250, ideal: 300)
        } detail: {
            // Detail view - show first selected record
            if let firstSelectedID = selectedRecordIDs.first,
               let record = records.first(where: { $0.id == firstSelectedID })
            {
                recordDetailView(record)
            } else {
                emptyDetailView
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search by filename")
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                filterMenu
            }
            ToolbarItem(placement: .secondaryAction) {
                deleteSelectedButton
            }
        }
        .alert(deleteAlertTitle, isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                recordsToDelete = []
            }
            Button("Delete", role: .destructive) {
                deleteRecords(recordsToDelete)
                recordsToDelete = []
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    /// Title for delete confirmation alert
    private var deleteAlertTitle: String {
        let count = recordsToDelete.count
        if count == 1 {
            return "Delete Analysis?"
        } else {
            return "Delete \(count) Analyses?"
        }
    }

    // MARK: History List

    private var historyList: some View {
        List(filteredRecords, id: \.id, selection: $selectedRecordIDs) { record in
            historyRow(record)
                .tag(record.id)
                .contextMenu {
                    if selectedRecordIDs.contains(record.id), selectedRecordIDs.count > 1 {
                        Button("Delete \(selectedRecordIDs.count) Selected") {
                            recordsToDelete = selectedRecords
                            showingDeleteConfirmation = true
                        }
                    } else {
                        Button("Delete") {
                            recordsToDelete = [record]
                            showingDeleteConfirmation = true
                        }
                    }
                }
        }
        .overlay {
            if filteredRecords.isEmpty {
                emptyListView
            }
        }
    }

    /// Get records for current selection
    private var selectedRecords: [AnalysisRecord] {
        records.filter { selectedRecordIDs.contains($0.id) }
    }

    private func historyRow(_ record: AnalysisRecord) -> some View {
        HStack(spacing: 12) {
            // Thumbnail
            if let thumbnailData = record.thumbnailData,
               let nsImage = NSImage(data: thumbnailData)
            {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(record.filename)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    classificationBadge(record.classificationEnum)

                    Text(record.formattedTimestamp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func classificationBadge(_ classification: OverallClassification) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(classificationColor(classification))
                .frame(width: 8, height: 8)

            Text(classification.shortName)
                .font(.caption)
                .fontWeight(.medium)
        }
    }

    private func classificationColor(_ classification: OverallClassification) -> Color {
        switch classification {
        case .likelyAuthentic: return .green
        case .uncertain: return .yellow
        case .likelyAIGenerated, .confirmedAIGenerated: return .red
        }
    }

    // MARK: Detail View

    private func recordDetailView(_ record: AnalysisRecord) -> some View {
        Group {
            if let result = try? record.decodeResult() {
                ResultsDetailView(result: result)
            } else {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.yellow)

                    Text("Unable to load result details")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var emptyDetailView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Select an analysis to view details")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyListView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(searchText.isEmpty ? "No Analysis History" : "No Results Found")
                .font(.headline)
                .foregroundStyle(.secondary)

            if !searchText.isEmpty {
                Text("Try a different search term")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: Toolbar

    private var filterMenu: some View {
        Menu {
            Button("All") {
                selectedClassification = nil
            }

            Divider()

            ForEach(OverallClassification.allCases, id: \.self) { classification in
                Button(classification.displayName) {
                    selectedClassification = classification
                }
            }
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
        }
    }

    private var deleteSelectedButton: some View {
        Button(role: .destructive) {
            recordsToDelete = selectedRecords
            showingDeleteConfirmation = true
        } label: {
            if selectedRecordIDs.count > 1 {
                Label("Delete (\(selectedRecordIDs.count))", systemImage: "trash")
            } else {
                Label("Delete", systemImage: "trash")
            }
        }
        .disabled(selectedRecordIDs.isEmpty)
        .help(selectedRecordIDs.count > 1
            ? "Delete \(selectedRecordIDs.count) selected analyses"
            : "Delete selected analysis")
    }

    // MARK: Filtering

    private var filteredRecords: [AnalysisRecord] {
        records.filter { record in
            // Search filter
            let matchesSearch = searchText.isEmpty ||
                record.filename.localizedCaseInsensitiveContains(searchText)

            // Classification filter
            let matchesClassification = selectedClassification == nil ||
                record.classificationEnum == selectedClassification

            return matchesSearch && matchesClassification
        }
    }

    // MARK: Actions

    private func deleteRecords(_ records: [AnalysisRecord]) {
        for record in records {
            modelContext.delete(record)
            selectedRecordIDs.remove(record.id)
        }
    }
}

// MARK: - Preview

#Preview {
    HistoryView()
        .modelContainer(for: AnalysisRecord.self, inMemory: true)
        .frame(width: 800, height: 600)
}
