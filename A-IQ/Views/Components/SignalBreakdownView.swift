import SwiftUI

// MARK: - Signal Breakdown View

/// Circular signal breakdown with circular progress indicators
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
        HStack(spacing: AIQSpacing.md) {
            // Circular progress indicator (Circular "pie")
            ZStack {
                Circle()
                    .stroke(AIQColors.subtleBorder, lineWidth: 3)

                if contribution.isAvailable {
                    Circle()
                        .trim(from: 0, to: contribution.rawScore)
                        .stroke(
                            scoreColor(for: contribution.rawScore),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(contribution.isAvailable ? AIQColors.primaryText : AIQColors.tertiaryText)

                if contribution.isAvailable {
                    Text(classificationLabel(for: contribution.rawScore))
                        .font(.caption)
                        .foregroundStyle(scoreColor(for: contribution.rawScore))
                } else {
                    Text("Not available")
                        .font(.caption)
                        .foregroundStyle(AIQColors.tertiaryText)
                }
            }

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

    private func classificationLabel(for score: Double) -> String {
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

#Preview {
    let breakdown = SignalBreakdown(
        mlContribution: SignalContribution(rawScore: 0.75, weight: 0.4, isAvailable: true, confidence: .high),
        provenanceContribution: SignalContribution(rawScore: 0.5, weight: 0.3, isAvailable: false, confidence: .unavailable),
        metadataContribution: SignalContribution(rawScore: 0.3, weight: 0.15, isAvailable: true, confidence: .medium),
        forensicContribution: SignalContribution(rawScore: 0.6, weight: 0.15, isAvailable: true, confidence: .medium)
    )

    return SignalBreakdownView(breakdown: breakdown)
        .aiqCard()
        .frame(width: 400)
        .padding()
        .background(AIQColors.paperWhite)
}
