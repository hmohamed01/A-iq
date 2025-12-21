import SwiftUI

// MARK: - Confidence Gauge View

/// Smooth gradient confidence gauge with smooth gradient
/// Implements: Req 7.2
struct ConfidenceGaugeView: View {
    let score: Double

    @State private var animatedScore: Double = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(AIQColors.subtleBorder)

                // Gradient fill
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(gradientFill)
                    .frame(width: max(0, geometry.size.width * animatedScore))

                // Threshold markers
                thresholdMarkers(width: geometry.size.width)

                // Score indicator
                scoreIndicator(width: geometry.size.width)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                animatedScore = score
            }
        }
        .onChange(of: score) { _, newValue in
            withAnimation(.easeOut(duration: 0.5)) {
                animatedScore = newValue
            }
        }
    }

    // MARK: Gradient

    private var gradientFill: LinearGradient {
        LinearGradient(
            colors: [
                AIQColors.authentic,
                AIQColors.uncertain,
                AIQColors.aiGenerated,
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: Threshold Markers

    private func thresholdMarkers(width: CGFloat) -> some View {
        ZStack {
            // 30% threshold
            Rectangle()
                .fill(Color.white.opacity(0.5))
                .frame(width: 2)
                .offset(x: width * 0.30 - 1)

            // 70% threshold
            Rectangle()
                .fill(Color.white.opacity(0.5))
                .frame(width: 2)
                .offset(x: width * 0.70 - 1)
        }
    }

    // MARK: Score Indicator

    private func scoreIndicator(width: CGFloat) -> some View {
        VStack(spacing: 2) {
            // Percentage label
            Text("\(Int(animatedScore * 100))%")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(AIQColors.primaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(AIQColors.cardBackground)
                .clipShape(Capsule())
                .shadow(color: AIQColors.dropShadow, radius: 4, x: 0, y: 2)

            // Pointer
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 8))
                .foregroundStyle(scoreColor)
        }
        .offset(x: width * animatedScore - 20)
    }

    private var scoreColor: Color {
        if score < 0.30 {
            return AIQColors.authentic
        } else if score < 0.70 {
            return AIQColors.uncertain
        } else {
            return AIQColors.aiGenerated
        }
    }
}

// MARK: - Mini Gauge (for lists)

struct MiniConfidenceGauge: View {
    let score: Double

    var body: some View {
        HStack(spacing: 6) {
            // Small circular indicator
            ZStack {
                Circle()
                    .stroke(AIQColors.subtleBorder, lineWidth: 2)

                Circle()
                    .trim(from: 0, to: score)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 16, height: 16)

            Text("\(Int(score * 100))%")
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(scoreColor)
        }
    }

    private var scoreColor: Color {
        if score < 0.30 {
            return AIQColors.authentic
        } else if score < 0.70 {
            return AIQColors.uncertain
        } else {
            return AIQColors.aiGenerated
        }
    }
}

// MARK: - Preview

#Preview("Full Gauge") {
    VStack(spacing: AIQSpacing.lg) {
        ConfidenceGaugeView(score: 0.15)
            .frame(height: 40)

        ConfidenceGaugeView(score: 0.50)
            .frame(height: 40)

        ConfidenceGaugeView(score: 0.85)
            .frame(height: 40)
    }
    .aiqCard()
    .frame(width: 400)
    .padding()
    .background(AIQColors.paperWhite)
}

#Preview("Mini Gauge") {
    HStack(spacing: AIQSpacing.lg) {
        MiniConfidenceGauge(score: 0.15)
        MiniConfidenceGauge(score: 0.50)
        MiniConfidenceGauge(score: 0.85)
    }
    .padding()
    .background(AIQColors.paperWhite)
}
