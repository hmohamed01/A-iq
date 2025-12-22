import SwiftUI
import UniformTypeIdentifiers

// MARK: - Settings Manager

/// User preferences management
/// Implements: Req 10.1, 10.2, 10.3, 10.4, 10.5
@MainActor
final class SettingsManager: ObservableObject {
    // MARK: Stored Settings

    /// Sensitivity threshold (0.0 to 1.0, default 0.5)
    /// Higher values make detection more sensitive (more likely to flag as AI)
    /// Implements: Req 10.2
    @AppStorage("sensitivityThreshold")
    var sensitivityThreshold: Double = 0.5

    /// Default export format
    /// Implements: Req 10.3
    @AppStorage("defaultExportFormat")
    var defaultExportFormat: ExportFormat = .pdf

    /// Whether to automatically analyze images when dropped
    /// Implements: Req 10.4
    @AppStorage("autoAnalyzeOnDrop")
    var autoAnalyzeOnDrop: Bool = true

    /// Whether to show ELA overlay by default
    @AppStorage("showELAByDefault")
    var showELAByDefault: Bool = false

    /// Whether to include timestamps in exported reports
    @AppStorage("includeTimestampsInReports")
    var includeTimestampsInReports: Bool = true

    /// History retention days (0 = keep forever)
    @AppStorage("historyRetentionDays")
    var historyRetentionDays: Int = 0

    /// Whether to store thumbnails in history (disable for privacy)
    /// Implements: Req 8.7
    @AppStorage("storeThumbnailsInHistory")
    var storeThumbnailsInHistory: Bool = true

    // MARK: Computed Properties

    /// Sensitivity adjustment for ResultAggregator (-0.1 to +0.1)
    /// Implements: Req 10.2
    var sensitivityAdjustment: Double {
        (sensitivityThreshold - 0.5) * 0.2
    }

    /// Whether any non-default settings are active
    var hasCustomSettings: Bool {
        sensitivityThreshold != 0.5 ||
            defaultExportFormat != .pdf ||
            !autoAnalyzeOnDrop ||
            showELAByDefault ||
            !includeTimestampsInReports ||
            historyRetentionDays != 0 ||
            !storeThumbnailsInHistory
    }

    // MARK: Methods

    /// Reset all settings to defaults
    /// Implements: Req 10.5
    func resetToDefaults() {
        sensitivityThreshold = 0.5
        defaultExportFormat = .pdf
        autoAnalyzeOnDrop = true
        showELAByDefault = false
        includeTimestampsInReports = true
        historyRetentionDays = 0
        storeThumbnailsInHistory = true
    }
}

// MARK: - Export Format

/// Available export formats for reports
enum ExportFormat: String, CaseIterable, Identifiable {
    case pdf = "PDF"
    case json = "JSON"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .pdf: return "pdf"
        case .json: return "json"
        }
    }

    var displayName: String {
        rawValue
    }

    var utType: UTType {
        switch self {
        case .json: return .json
        case .pdf: return .pdf
        }
    }
}

// MARK: - RawRepresentable for AppStorage

extension ExportFormat: RawRepresentable {
    init?(rawValue: String) {
        switch rawValue.uppercased() {
        case "PDF": self = .pdf
        case "JSON": self = .json
        default: return nil
        }
    }
}
