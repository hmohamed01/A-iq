import SwiftUI

// MARK: - Results Detail View

/// Full results display with signal breakdown (A-IQ design system)
/// Implements: Req 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 7.7
struct ResultsDetailView: View {
    let result: AggregatedResult

    @State private var showELAOverlay: Bool = false
    @State private var expandedSections: Set<String> = ["breakdown"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AIQSpacing.lg) {
                // Header with classification
                headerSection
                    .aiqCard()

                // Confidence gauge
                confidenceSection
                    .aiqCard()

                // Signal breakdown
                signalBreakdownSection
                    .aiqCard()

                // C2PA Provenance (if available)
                if result.provenanceResult?.credentialStatus != .notPresent {
                    provenanceSection
                        .aiqCard()
                }

                // Metadata (if available)
                if result.metadataResult?.hasExifData == true {
                    metadataSection
                        .aiqCard()
                }

                // ELA Visualization (if available)
                if result.elaImage != nil {
                    elaSection
                        .aiqCard()
                }

                // Face-Swap Detection (if faces detected)
                if result.faceSwapResult?.facesDetected == true {
                    faceSwapSection
                        .aiqCard()
                }

                // Evidence summary
                evidenceSection
                    .aiqCard()
            }
            .padding(AIQSpacing.lg)
        }
        .background(AIQColors.paperWhite)
    }

    // MARK: Header Section

    private var headerSection: some View {
        HStack(alignment: .top, spacing: AIQSpacing.md) {
            VStack(alignment: .leading, spacing: AIQSpacing.sm) {
                // Filename
                Text(result.imageSource.displayName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AIQColors.primaryText)

                // Classification badge
                classificationBadge

                // Metadata
                if let size = result.imageSize {
                    Text("\(Int(size.width)) × \(Int(size.height))")
                        .font(.caption)
                        .foregroundStyle(AIQColors.tertiaryText)
                }

                Text("Analyzed \(result.timestamp.formatted())")
                    .font(.caption)
                    .foregroundStyle(AIQColors.tertiaryText)
            }

            Spacer()

            // Large thumbnail preview
            if let thumbnail = result.imageThumbnail {
                Image(thumbnail, scale: 1.0, label: Text("Image"))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 180, maxHeight: 140)
                    .clipShape(RoundedRectangle(cornerRadius: AIQRadius.md, style: .continuous))
                    .shadow(color: AIQColors.dropShadow, radius: 4, x: 0, y: 2)
            }
        }
    }

    private var classificationBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(classificationColor)
                .frame(width: 12, height: 12)

            Text(result.classification.displayName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(classificationColor)

            if result.isDefinitive {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(AIQColors.accent)
                    .help("Verified by C2PA credentials")
            }
        }
    }

    private var classificationColor: Color {
        switch result.classification {
        case .likelyAuthentic: return AIQColors.authentic
        case .uncertain: return AIQColors.uncertain
        case .likelyAIGenerated, .confirmedAIGenerated: return AIQColors.aiGenerated
        }
    }

    // MARK: Confidence Section

    private var confidenceSection: some View {
        VStack(alignment: .leading, spacing: AIQSpacing.md) {
            Text("Confidence Score")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AIQColors.secondaryText)

            ConfidenceGaugeView(score: result.overallScore)
                .frame(height: 50)

            Text("\(result.scorePercentage)% probability of AI generation")
                .font(.subheadline)
                .foregroundStyle(AIQColors.tertiaryText)
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
                .padding(.top, AIQSpacing.sm)
        } label: {
            Label("Signal Breakdown", systemImage: "chart.bar.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AIQColors.primaryText)
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
                    .padding(.top, AIQSpacing.sm)
            }
        } label: {
            Label("Content Credentials (C2PA)", systemImage: "checkmark.shield.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AIQColors.primaryText)
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
                    .padding(.top, AIQSpacing.sm)
            }
        } label: {
            Label("Image Metadata", systemImage: "info.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AIQColors.primaryText)
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
            .padding(.top, AIQSpacing.sm)
        } label: {
            Label("Error Level Analysis", systemImage: "waveform.path.ecg")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AIQColors.primaryText)
        }
    }

    // MARK: Face-Swap Section

    private var faceSwapSection: some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { expandedSections.contains("faceswap") },
                set: { if $0 { expandedSections.insert("faceswap") } else { expandedSections.remove("faceswap") }}
            )
        ) {
            if let faceSwap = result.faceSwapResult {
                FaceSwapDetailView(result: faceSwap)
                    .padding(.top, AIQSpacing.sm)
            }
        } label: {
            Label("Face-Swap Detection", systemImage: "face.smiling")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AIQColors.primaryText)
        }
    }

    // MARK: Evidence Section

    private var evidenceSection: some View {
        VStack(alignment: .leading, spacing: AIQSpacing.md) {
            Text("Evidence Summary")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AIQColors.secondaryText)

            if !result.aiIndicators.isEmpty {
                VStack(alignment: .leading, spacing: AIQSpacing.sm) {
                    Text("AI Indicators")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AIQColors.aiGenerated)

                    ForEach(result.aiIndicators) { evidence in
                        Label(evidence.description, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(AIQColors.secondaryText)
                    }
                }
            }

            if !result.authenticityIndicators.isEmpty {
                VStack(alignment: .leading, spacing: AIQSpacing.sm) {
                    Text("Authenticity Indicators")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AIQColors.authentic)

                    ForEach(result.authenticityIndicators) { evidence in
                        Label(evidence.description, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(AIQColors.secondaryText)
                    }
                }
            }

            if result.aiIndicators.isEmpty && result.authenticityIndicators.isEmpty {
                Text("No strong indicators detected")
                    .font(.caption)
                    .foregroundStyle(AIQColors.tertiaryText)
            }
        }
    }
}

// MARK: - Preview

#Preview {
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
