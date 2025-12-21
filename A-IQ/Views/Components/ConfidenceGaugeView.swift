import SwiftUI

// MARK: - Confidence Gauge View

/// Visual confidence indicator with color gradient
/// Implements: Req 7.2
struct ConfidenceGaugeView: View {
    let score: Double

    @State private var animatedScore: Double = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.2))

                // Gradient fill
                RoundedRectangle(cornerRadius: 8)
                    .fill(gradientFill)
                    .frame(width: geometry.size.width * animatedScore)

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
                Color.green,
                Color.yellow,
                Color.orange,
                Color.red,
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
                .fill(Color.primary.opacity(0.3))
                .frame(width: 2)
                .offset(x: width * 0.30 - 1)

            // 70% threshold
            Rectangle()
                .fill(Color.primary.opacity(0.3))
                .frame(width: 2)
                .offset(x: width * 0.70 - 1)
        }
    }

    // MARK: Score Indicator

    private func scoreIndicator(width: CGFloat) -> some View {
        VStack(spacing: 2) {
            // Percentage label
            Text("\(Int(animatedScore * 100))%")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(Capsule())
                .shadow(radius: 2)

            // Pointer
            Image(systemName: "arrowtriangle.down.fill")
                .font(.caption2)
                .foregroundStyle(scoreColor)
        }
        .offset(x: width * animatedScore - 20)
    }

    private var scoreColor: Color {
        if score < 0.30 {
            return .green
        } else if score < 0.70 {
            return .yellow
        } else {
            return .red
        }
    }
}

// MARK: - Mini Gauge (for lists)

struct MiniConfidenceGauge: View {
    let score: Double

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(scoreColor)
                .frame(width: 8, height: 8)

            Text("\(Int(score * 100))%")
                .font(.caption)
                .monospacedDigit()
        }
    }

    private var scoreColor: Color {
        if score < 0.30 {
            return .green
        } else if score < 0.70 {
            return .yellow
        } else {
            return .red
        }
    }
}

// MARK: - Preview

#Preview("Full Gauge") {
    VStack(spacing: 20) {
        ConfidenceGaugeView(score: 0.15)
            .frame(height: 40)

        ConfidenceGaugeView(score: 0.50)
            .frame(height: 40)

        ConfidenceGaugeView(score: 0.85)
            .frame(height: 40)
    }
    .padding()
    .frame(width: 400)
}

#Preview("Mini Gauge") {
    HStack(spacing: 20) {
        MiniConfidenceGauge(score: 0.15)
        MiniConfidenceGauge(score: 0.50)
        MiniConfidenceGauge(score: 0.85)
    }
    .padding()
}
