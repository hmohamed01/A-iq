import SwiftUI

// MARK: - Welcome View

/// First-launch welcome walkthrough explaining app usage
struct WelcomeView: View {
    @Binding var isPresented: Bool
    @AppStorage("showWelcomeOnLaunch") private var showWelcomeOnLaunch = true

    @State private var currentStep = 0

    private let totalSteps = 3

    var body: some View {
        VStack(spacing: 0) {
            // Content area
            TabView(selection: $currentStep) {
                StepOne()
                    .tag(0)

                StepTwo()
                    .tag(1)

                StepThree()
                    .tag(2)
            }
            .tabViewStyle(.automatic)
            .animation(.easeInOut(duration: 0.3), value: currentStep)

            Divider()

            // Footer
            HStack {
                // Checkbox
                Toggle("Show at startup", isOn: $showWelcomeOnLaunch)
                    .toggleStyle(.checkbox)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Spacer()

                // Page indicator
                HStack(spacing: 6) {
                    ForEach(0..<totalSteps, id: \.self) { step in
                        Circle()
                            .fill(step == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }

                Spacer()

                // Navigation buttons
                HStack(spacing: 12) {
                    if currentStep > 0 {
                        Button("Back") {
                            withAnimation {
                                currentStep -= 1
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    if currentStep < totalSteps - 1 {
                        Button("Next") {
                            withAnimation {
                                currentStep += 1
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                    } else {
                        Button("Get Started") {
                            isPresented = false
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .padding(16)
        }
        .frame(width: 480, height: 400)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Step One: Welcome

private struct StepOne: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "photo.badge.checkmark")
                .font(.system(size: 56))
                .foregroundStyle(.accent)

            Text("Welcome to A-IQ")
                .font(.title)
                .fontWeight(.semibold)

            Text("AI Image Detection for macOS")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Analyze images to detect signs of AI generation\nusing metadata, provenance, and visual patterns.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
        }
        .padding()
    }
}

// MARK: - Step Two: How to Use

private struct StepTwo: View {
    var body: some View {
        VStack(spacing: 24) {
            Text("How to Analyze Images")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.top, 24)

            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(
                    icon: "arrow.down.doc.fill",
                    iconColor: .blue,
                    title: "Drag & Drop",
                    description: "Drop any image directly onto the window"
                )

                FeatureRow(
                    icon: "folder.fill",
                    iconColor: .orange,
                    title: "Open File",
                    description: "Use File → Open or press ⌘O"
                )

                FeatureRow(
                    icon: "doc.on.clipboard.fill",
                    iconColor: .green,
                    title: "Paste",
                    description: "Paste from clipboard with ⌘V"
                )
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }
}

// MARK: - Step Three: Understanding Scores

private struct StepThree: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Understanding Scores")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.top, 24)

            Text("A-IQ combines multiple signals into\na single confidence score.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                ScoreExplanation(
                    range: "0 – 30%",
                    label: "Likely Authentic",
                    description: "Strong indicators of a real photograph",
                    color: .green
                )

                ScoreExplanation(
                    range: "30 – 70%",
                    label: "Uncertain",
                    description: "Mixed signals, manual review advised",
                    color: .orange
                )

                ScoreExplanation(
                    range: "70 – 100%",
                    label: "Likely AI-Generated",
                    description: "High probability of AI involvement",
                    color: .red
                )
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }
}

// MARK: - Supporting Views

private struct FeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)

                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

private struct ScoreExplanation: View {
    let range: String
    let label: String
    let description: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color.gradient)
                .frame(width: 8, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(range)
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)

                    Text("—")
                        .foregroundStyle(.tertiary)

                    Text(label)
                        .fontWeight(.medium)
                }

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    WelcomeView(isPresented: .constant(true))
}
