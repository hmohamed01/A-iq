import SwiftUI

// MARK: - Settings View

/// Preferences interface
/// Implements: Req 10.1, 10.2, 10.3, 10.4, 10.5
struct SettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var showingResetConfirmation: Bool = false

    var body: some View {
        Form {
            // Detection Settings
            Section("Detection") {
                sensitivitySlider
                autoAnalyzeToggle
            }

            // Display Settings
            Section("Display") {
                elaToggle
            }

            // Export Settings
            Section("Export") {
                exportFormatPicker
                timestampToggle
            }

            // Data Management
            Section("Data") {
                historyRetentionPicker
            }

            // Reset
            Section {
                resetButton
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 400)
        .alert("Reset Settings?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                settingsManager.resetToDefaults()
            }
        } message: {
            Text("All settings will be restored to their default values.")
        }
    }

    // MARK: Detection Settings

    private var sensitivitySlider: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Detection Sensitivity")
                Spacer()
                Text(sensitivityLabel)
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: $settingsManager.sensitivityThreshold,
                in: 0 ... 1,
                step: 0.1
            )

            Text("Higher sensitivity is more likely to flag images as AI-generated")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var sensitivityLabel: String {
        let value = settingsManager.sensitivityThreshold
        if value < 0.3 {
            return "Low"
        } else if value < 0.7 {
            return "Normal"
        } else {
            return "High"
        }
    }

    private var autoAnalyzeToggle: some View {
        Toggle("Automatically analyze dropped images", isOn: $settingsManager.autoAnalyzeOnDrop)
    }

    // MARK: Display Settings

    private var elaToggle: some View {
        Toggle("Show ELA overlay by default", isOn: $settingsManager.showELAByDefault)
    }

    // MARK: Export Settings

    private var exportFormatPicker: some View {
        Picker("Default Export Format", selection: $settingsManager.defaultExportFormat) {
            ForEach(ExportFormat.allCases) { format in
                Text(format.displayName).tag(format)
            }
        }
    }

    private var timestampToggle: some View {
        Toggle("Include timestamps in reports", isOn: $settingsManager.includeTimestampsInReports)
    }

    // MARK: Data Settings

    private var historyRetentionPicker: some View {
        Picker("Keep history for", selection: $settingsManager.historyRetentionDays) {
            Text("Forever").tag(0)
            Text("30 days").tag(30)
            Text("90 days").tag(90)
            Text("1 year").tag(365)
        }
    }

    // MARK: Reset

    private var resetButton: some View {
        HStack {
            Spacer()
            Button("Reset to Defaults") {
                showingResetConfirmation = true
            }
            .disabled(!settingsManager.hasCustomSettings)
            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(SettingsManager())
}
