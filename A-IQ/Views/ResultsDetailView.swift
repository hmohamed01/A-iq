import SwiftUI

// MARK: - Results Detail View

/// Full results display with signal breakdown
/// Implements: Req 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 7.7
struct ResultsDetailView: View {
    let result: AggregatedResult

    @State private var showELAOverlay: Bool = false
    @State private var expandedSections: Set<String> = ["breakdown"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header with classification
                headerSection

                Divider()

                // Confidence gauge
                confidenceSection

                Divider()

                // Signal breakdown
                signalBreakdownSection

                // C2PA Provenance (if available)
                if result.provenanceResult?.credentialStatus != .notPresent {
                    Divider()
                    provenanceSection
                }

                // Metadata (if available)
                if result.metadataResult?.hasExifData == true {
                    Divider()
                    metadataSection
                }

                // ELA Visualization (if available)
                if result.elaImage != nil {
                    Divider()
                    elaSection
                }

                // Evidence summary
                Divider()
                evidenceSection
            }
            .padding()
        }
    }

    // MARK: Header Section

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 16) {
            // Thumbnail
            if let thumbnail = result.imageThumbnail {
                Image(thumbnail, scale: 1.0, label: Text("Image"))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 8) {
                // Filename
                Text(result.imageSource.displayName)
                    .font(.headline)

                // Classification badge
                classificationBadge

                // Metadata
                if let size = result.imageSize {
                    Text("\(Int(size.width)) × \(Int(size.height))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Analyzed \(result.timestamp.formatted())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var classificationBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(classificationColor)
                .frame(width: 12, height: 12)

            Text(result.classification.displayName)
                .font(.title3)
                .fontWeight(.semibold)

            if result.isDefinitive {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.blue)
                    .help("Verified by C2PA credentials")
            }
        }
    }

    private var classificationColor: Color {
        switch result.classification {
        case .likelyAuthentic: return .green
        case .uncertain: return .yellow
        case .likelyAIGenerated, .confirmedAIGenerated: return .red
        }
    }

    // MARK: Confidence Section

    private var confidenceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Confidence Score")
                .font(.headline)

            ConfidenceGaugeView(score: result.overallScore)
                .frame(height: 60)

            Text("\(result.scorePercentage)% probability of AI generation")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Signal Breakdown Section

    private var signalBreakdownSection: some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { expandedSections.contains("breakdown") },
                set: { if $0 { expandedSections.insert("breakdown") } else { expandedSections.remove("breakdown") }}
            )
        ) {
            SignalBreakdownView(breakdown: result.signalBreakdown)
                .padding(.top, 8)
        } label: {
            Label("Signal Breakdown", systemImage: "chart.bar.fill")
                .font(.headline)
        }
    }

    // MARK: Provenance Section

    private var provenanceSection: some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { expandedSections.contains("provenance") },
                set: { if $0 { expandedSections.insert("provenance") } else { expandedSections.remove("provenance") }}
            )
        ) {
            if let provenance = result.provenanceResult {
                ProvenanceChainView(result: provenance)
                    .padding(.top, 8)
            }
        } label: {
            Label("Content Credentials (C2PA)", systemImage: "checkmark.shield.fill")
                .font(.headline)
        }
    }

    // MARK: Metadata Section

    private var metadataSection: some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { expandedSections.contains("metadata") },
                set: { if $0 { expandedSections.insert("metadata") } else { expandedSections.remove("metadata") }}
            )
        ) {
            if let metadata = result.metadataResult {
                MetadataPanel(result: metadata)
                    .padding(.top, 8)
            }
        } label: {
            Label("Image Metadata", systemImage: "info.circle.fill")
                .font(.headline)
        }
    }

    // MARK: ELA Section

    private var elaSection: some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { expandedSections.contains("ela") },
                set: { if $0 { expandedSections.insert("ela") } else { expandedSections.remove("ela") }}
            )
        ) {
            ELAOverlayView(
                originalImage: result.imageThumbnail,
                elaImage: result.elaImage,
                showOverlay: $showELAOverlay
            )
            .padding(.top, 8)
        } label: {
            Label("Error Level Analysis", systemImage: "waveform.path.ecg")
                .font(.headline)
        }
    }

    // MARK: Evidence Section

    private var evidenceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Evidence Summary")
                .font(.headline)

            if !result.aiIndicators.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("AI Indicators")
                        .font(.subheadline)
                        .foregroundStyle(.red)

                    ForEach(result.aiIndicators) { evidence in
                        Label(evidence.description, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !result.authenticityIndicators.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Authenticity Indicators")
                        .font(.subheadline)
                        .foregroundStyle(.green)

                    ForEach(result.authenticityIndicators) { evidence in
                        Label(evidence.description, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    // Create a mock result for preview
    let breakdown = SignalBreakdown(
        mlContribution: SignalContribution(rawScore: 0.75, weight: 0.4, isAvailable: true, confidence: .high),
        provenanceContribution: SignalContribution(rawScore: 0.5, weight: 0.3, isAvailable: false, confidence: .unavailable),
        metadataContribution: SignalContribution(rawScore: 0.3, weight: 0.15, isAvailable: true, confidence: .medium),
        forensicContribution: SignalContribution(rawScore: 0.6, weight: 0.15, isAvailable: true, confidence: .medium)
    )

    let result = AggregatedResult(
        imageSource: .fileURL(URL(fileURLWithPath: "/test/image.jpg")),
        overallScore: 0.65,
        classification: .uncertain,
        isDefinitive: false,
        summary: "Analysis uncertain - manual review recommended",
        signalBreakdown: breakdown,
        totalAnalysisTimeMs: 2500
    )

    return ResultsDetailView(result: result)
        .frame(width: 500, height: 800)
}
