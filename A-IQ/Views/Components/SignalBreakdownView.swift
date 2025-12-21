import SwiftUI

// MARK: - Signal Breakdown View

/// Horizontal bar chart showing signal contributions
/// Implements: Req 7.3
struct SignalBreakdownView: View {
    let breakdown: SignalBreakdown

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(breakdown.allContributions, id: \.name) { item in
                signalRow(
                    name: item.name,
                    contribution: item.contribution,
                    weight: item.weight
                )
            }

            Divider()

            // Legend
            legendView
        }
    }

    // MARK: Signal Row

    private func signalRow(name: String, contribution: SignalContribution, weight: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                if contribution.isAvailable {
                    Text("\(Int(contribution.rawScore * 100))%")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)

                    Text("(\(Int(weight * 100))% weight)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("Unavailable")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.2))

                    if contribution.isAvailable {
                        // Score fill
                        RoundedRectangle(cornerRadius: 4)
                            .fill(barColor(for: contribution.rawScore))
                            .frame(width: geometry.size.width * contribution.rawScore)

                        // Weight indicator
                        Rectangle()
                            .fill(Color.primary.opacity(0.5))
                            .frame(width: 2)
                            .offset(x: geometry.size.width * weight - 1)
                    }
                }
            }
            .frame(height: 8)

            // Classification badge (matches legend)
            if contribution.isAvailable {
                HStack(spacing: 4) {
                    classificationIcon(for: contribution.rawScore)
                    Text(classificationLabel(for: contribution.rawScore))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func barColor(for score: Double) -> Color {
        if score < 0.30 {
            return .green
        } else if score < 0.70 {
            return .yellow
        } else {
            return .red
        }
    }

    private func classificationLabel(for score: Double) -> String {
        if score < 0.30 {
            return "Authentic"
        } else if score < 0.70 {
            return "Uncertain"
        } else {
            return "AI"
        }
    }

    private func classificationIcon(for score: Double) -> some View {
        Group {
            if score < 0.30 {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if score < 0.70 {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(.yellow)
            } else {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
        .font(.caption2)
    }

    // MARK: Legend

    private var legendView: some View {
        HStack(spacing: 16) {
            legendItem(color: .green, label: "< 30% (Authentic)")
            legendItem(color: .yellow, label: "30-70% (Uncertain)")
            legendItem(color: .red, label: "> 70% (AI)")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
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
        .padding()
        .frame(width: 400)
}
