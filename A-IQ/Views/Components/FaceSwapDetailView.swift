import SwiftUI

// MARK: - Face-Swap Detail View

/// Displays face-swap detection results with per-face analysis
struct FaceSwapDetailView: View {
    let result: FaceSwapResult

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Summary section
            summarySection

            // Face analyses
            if !result.faceAnalyses.isEmpty {
                facesSection
            }

            // Artifacts
            if !result.artifacts.isEmpty {
                artifactsSection
            }

            // Processing info
            processingInfoSection
        }
    }

    // MARK: Summary Section

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Face Analysis Summary", systemImage: "face.smiling")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(result.faceCount) \(result.faceCount == 1 ? "face" : "faces") detected")
                        .font(.body)
                        .fontWeight(.medium)

                    Text(scoreDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                scoreIndicator
            }
            .padding()
            .background(scoreBackgroundColor.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var scoreDescription: String {
        if !result.facesDetected {
            return "No faces found to analyze"
        } else if result.score > 0.7 {
            return "High probability of face manipulation"
        } else if result.score > 0.4 {
            return "Some suspicious indicators detected"
        } else {
            return "No significant manipulation indicators"
        }
    }

    private var scoreBackgroundColor: Color {
        if !result.facesDetected {
            return .secondary
        } else if result.score > 0.7 {
            return .red
        } else if result.score > 0.4 {
            return .orange
        } else {
            return .green
        }
    }

    private var scoreIndicator: some View {
        Group {
            if !result.facesDetected {
                Image(systemName: "face.dashed")
                    .foregroundStyle(.secondary)
                    .font(.title2)
            } else if result.score > 0.7 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.title2)
            } else if result.score > 0.4 {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.title2)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title2)
            }
        }
    }

    // MARK: Faces Section

    private var facesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Individual Face Analysis", systemImage: "person.crop.rectangle.stack")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(Array(result.faceAnalyses.enumerated()), id: \.element.id) { index, analysis in
                faceAnalysisRow(index: index + 1, analysis: analysis)
            }
        }
    }

    private func faceAnalysisRow(index: Int, analysis: FaceAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Face \(index)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.2))
                    .clipShape(Capsule())

                Spacer()

                scoreChip(score: analysis.score)
            }

            // Analysis details
            VStack(alignment: .leading, spacing: 4) {
                analysisDetailRow("Boundary Analysis", score: analysis.boundaryELAScore)
                analysisDetailRow("Noise Consistency", score: analysis.noiseDiscontinuityScore)
                analysisDetailRow("Lighting Match", score: analysis.lightingConsistencyScore)
            }

            // Artifacts for this face
            if !analysis.artifacts.isEmpty {
                HStack(spacing: 4) {
                    ForEach(analysis.artifacts.prefix(3)) { artifact in
                        artifactChip(artifact)
                    }
                    if analysis.artifacts.count > 3 {
                        Text("+\(analysis.artifacts.count - 3)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(faceBackgroundColor(score: analysis.score).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func analysisDetailRow(_ label: String, score: Double) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 4) {
                // Mini bar indicator
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                        Rectangle()
                            .fill(barColor(score: score))
                            .frame(width: geometry.size.width * score)
                    }
                }
                .frame(width: 40, height: 6)
                .clipShape(Capsule())

                Text("\(Int(score * 100))%")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .trailing)
            }
        }
    }

    private func barColor(score: Double) -> Color {
        if score > 0.7 {
            return .red
        } else if score > 0.4 {
            return .orange
        } else {
            return .green
        }
    }

    private func faceBackgroundColor(score: Double) -> Color {
        if score > 0.7 {
            return .red
        } else if score > 0.4 {
            return .orange
        } else {
            return .green
        }
    }

    private func scoreChip(score: Double) -> some View {
        Text("\(Int(score * 100))%")
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(barColor(score: score))
            .clipShape(Capsule())
    }

    private func artifactChip(_ artifact: FaceSwapArtifact) -> some View {
        HStack(spacing: 4) {
            Image(systemName: artifactIcon(artifact.type))
            Text(artifact.type.shortName)
        }
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(severityColor(artifact.severity).opacity(0.2))
        .clipShape(Capsule())
    }

    // MARK: Artifacts Section

    private var artifactsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Detected Artifacts", systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(result.artifacts) { artifact in
                    HStack {
                        Image(systemName: artifactIcon(artifact.type))
                            .foregroundStyle(severityColor(artifact.severity))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(artifact.type.displayName)
                                .font(.caption)
                                .fontWeight(.medium)

                            Text(artifact.description)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(artifact.severity.rawValue.capitalized)
                            .font(.caption2)
                            .foregroundStyle(severityColor(artifact.severity))
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func artifactIcon(_ type: FaceSwapArtifact.ArtifactType) -> String {
        switch type {
        case .boundaryInconsistency:
            return "square.dashed"
        case .noiseDiscontinuity:
            return "waveform"
        case .lightingInconsistency:
            return "sun.max"
        case .textureAnomaly:
            return "rectangle.3.group"
        case .blendingArtifact:
            return "circle.lefthalf.filled"
        }
    }

    private func severityColor(_ severity: FaceSwapArtifact.Severity) -> Color {
        switch severity {
        case .low:
            return .yellow
        case .medium:
            return .orange
        case .high:
            return .red
        }
    }

    // MARK: Processing Info Section

    private var processingInfoSection: some View {
        HStack {
            Label("Processed in \(result.processingTimeMs)ms", systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text("Confidence: \(result.confidence.displayName)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Artifact Type Extension

extension FaceSwapArtifact.ArtifactType {
    var shortName: String {
        switch self {
        case .boundaryInconsistency:
            return "Boundary"
        case .noiseDiscontinuity:
            return "Noise"
        case .lightingInconsistency:
            return "Lighting"
        case .textureAnomaly:
            return "Texture"
        case .blendingArtifact:
            return "Blend"
        }
    }
}

// MARK: - Preview

#Preview("Face Swap Detected") {
    let artifact1 = FaceSwapArtifact(
        type: .boundaryInconsistency,
        description: "Compression artifacts at face boundary",
        location: CGRect(x: 100, y: 100, width: 200, height: 200),
        severity: .high
    )
    let artifact2 = FaceSwapArtifact(
        type: .noiseDiscontinuity,
        description: "Different noise patterns detected",
        location: CGRect(x: 100, y: 100, width: 200, height: 200),
        severity: .medium
    )

    let faceAnalysis = FaceAnalysis(
        faceBounds: CGRect(x: 100, y: 100, width: 200, height: 200),
        artifacts: [artifact1, artifact2],
        score: 0.75,
        boundaryELAScore: 0.8,
        noiseDiscontinuityScore: 0.7,
        lightingConsistencyScore: 0.5
    )

    let result = FaceSwapResult(faceAnalyses: [faceAnalysis], processingTimeMs: 850)

    FaceSwapDetailView(result: result)
        .padding()
        .frame(width: 400)
}

#Preview("No Faces") {
    let result = FaceSwapResult.noFaces(processingTimeMs: 120)

    FaceSwapDetailView(result: result)
        .padding()
        .frame(width: 400)
}

#Preview("Clean Result") {
    let faceAnalysis = FaceAnalysis(
        faceBounds: CGRect(x: 100, y: 100, width: 200, height: 200),
        artifacts: [],
        score: 0.15,
        boundaryELAScore: 0.1,
        noiseDiscontinuityScore: 0.2,
        lightingConsistencyScore: 0.15
    )

    let result = FaceSwapResult(faceAnalyses: [faceAnalysis], processingTimeMs: 750)

    FaceSwapDetailView(result: result)
        .padding()
        .frame(width: 400)
}
