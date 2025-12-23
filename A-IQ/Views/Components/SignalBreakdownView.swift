import SwiftUI

// MARK: - Signal Breakdown View

/// Signal breakdown with horizontal progress bars
/// Implements: Req 7.3
struct SignalBreakdownView: View {
    let breakdown: SignalBreakdown

    var body: some View {
        VStack(alignment: .leading, spacing: AIQSpacing.md) {
            ForEach(breakdown.allContributions, id: \.name) { item in
                signalRow(
                    name: item.name,
                    contribution: item.contribution,
                    weight: item.weight
                )
            }
        }
    }

    // MARK: Signal Row

    private func signalRow(name: String, contribution: SignalContribution, weight: Double) -> some View {
        VStack(alignment: .leading, spacing: AIQSpacing.xs) {
            // Header row with name, score, and weight
            HStack {
                Text(name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(contribution.isAvailable ? AIQColors.primaryText : AIQColors.tertiaryText)

                Spacer()

                if contribution.isAvailable {
                    Text("\(Int(contribution.rawScore * 100))%")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(scoreColor(for: contribution.rawScore))
                } else {
                    Text("N/A")
                        .font(.subheadline)
                        .foregroundStyle(AIQColors.tertiaryText)
                }

                Text("(\(Int(weight * 100))%)")
                    .font(.caption)
                    .foregroundStyle(AIQColors.tertiaryText)
            }

            // Horizontal progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AIQColors.subtleBorder)

                    if contribution.isAvailable {
                        // Score fill
                        RoundedRectangle(cornerRadius: 4)
                            .fill(scoreColor(for: contribution.rawScore))
                            .frame(width: geometry.size.width * contribution.rawScore)
                    }
                }
            }
            .frame(height: 6)

            // Classification label
            if contribution.isAvailable {
                Text(classificationLabel(for: contribution.rawScore, signalName: name))
                    .font(.caption)
                    .foregroundStyle(scoreColor(for: contribution.rawScore))
            } else {
                Text("Not available")
                    .font(.caption)
                    .foregroundStyle(AIQColors.tertiaryText)
            }
        }
        .padding(.vertical, AIQSpacing.xs)
    }

    private func scoreColor(for score: Double) -> Color {
        if score < 0.30 {
            return AIQColors.authentic
        } else if score < 0.70 {
            return AIQColors.uncertain
        } else {
            return AIQColors.aiGenerated
        }
    }

    private func classificationLabel(for score: Double, signalName: String) -> String {
        // Face-Swap uses Low/Medium/High instead of Authentic/Uncertain/AI-Generated
        // because "Authentic" doesn't apply to fully AI-generated images
        if signalName == "Face-Swap" {
            if score < 0.30 {
                return "Low"
            } else if score < 0.70 {
                return "Medium"
            } else {
                return "High"
            }
        }

        // Default labels for other signals
        if score < 0.30 {
            return "Authentic"
        } else if score < 0.70 {
            return "Uncertain"
        } else {
            return "AI-Generated"
        }
    }
}

// MARK: - Preview

#Preview("Without Face-Swap") {
    let breakdown = SignalBreakdown(
        mlContribution: SignalContribution(rawScore: 0.75, weight: 0.4, isAvailable: true, confidence: .high),
        provenanceContribution: SignalContribution(rawScore: 0.5, weight: 0.3, isAvailable: false, confidence: .unavailable),
        metadataContribution: SignalContribution(rawScore: 0.3, weight: 0.15, isAvailable: true, confidence: .medium),
        forensicContribution: SignalContribution(rawScore: 0.6, weight: 0.15, isAvailable: true, confidence: .medium)
    )

    SignalBreakdownView(breakdown: breakdown)
        .aiqCard()
        .frame(width: 400)
        .padding()
        .background(AIQColors.paperWhite)
}

#Preview("With Face-Swap") {
    let breakdown = SignalBreakdown(
        mlContribution: SignalContribution(rawScore: 0.75, weight: 0.35, isAvailable: true, confidence: .high),
        provenanceContribution: SignalContribution(rawScore: 0.5, weight: 0.25, isAvailable: true, confidence: .medium),
        metadataContribution: SignalContribution(rawScore: 0.3, weight: 0.10, isAvailable: true, confidence: .medium),
        forensicContribution: SignalContribution(rawScore: 0.6, weight: 0.10, isAvailable: true, confidence: .medium),
        faceSwapContribution: SignalContribution(rawScore: 0.85, weight: 0.20, isAvailable: true, confidence: .high)
    )

    SignalBreakdownView(breakdown: breakdown)
        .aiqCard()
        .frame(width: 400)
        .padding()
        .background(AIQColors.paperWhite)
}
