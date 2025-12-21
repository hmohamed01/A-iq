import SwiftUI

// MARK: - ELA Overlay View

/// Toggle between original image and ELA visualization
/// Implements: Req 7.5
struct ELAOverlayView: View {
    let originalImage: CGImage?
    let elaImage: CGImage?
    @Binding var showOverlay: Bool

    @State private var overlayOpacity: Double = 0.5

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Controls
            HStack {
                Toggle("Show ELA Overlay", isOn: $showOverlay)
                    .toggleStyle(.switch)

                Spacer()

                if showOverlay {
                    HStack(spacing: 8) {
                        Text("Opacity")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Slider(value: $overlayOpacity, in: 0 ... 1)
                            .frame(width: 100)

                        Text("\(Int(overlayOpacity * 100))%")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }

            // Image display
            imageView
                .frame(maxHeight: 300)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // Legend
            if showOverlay {
                legendView
            }
        }
    }

    // MARK: Image View

    @ViewBuilder
    private var imageView: some View {
        if let original = originalImage {
            ZStack {
                // Original image
                Image(original, scale: 1.0, label: Text("Original"))
                    .resizable()
                    .aspectRatio(contentMode: .fit)

                // ELA overlay
                if showOverlay, let ela = elaImage {
                    Image(ela, scale: 1.0, label: Text("ELA"))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .opacity(overlayOpacity)
                        .blendMode(.multiply)
                }
            }
        } else {
            placeholderView
        }
    }

    private var placeholderView: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.secondary.opacity(0.1))
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)

                    Text("No ELA visualization available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
    }

    // MARK: Legend

    private var legendView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How to Read ELA")
                .font(.caption)
                .fontWeight(.semibold)

            HStack(spacing: 16) {
                legendItem(
                    color: .white,
                    label: "Bright areas",
                    description: "Recently edited or different compression"
                )

                legendItem(
                    color: .gray,
                    label: "Dark areas",
                    description: "Consistent compression level"
                )
            }

            Text("Uniform brightness across the image suggests it hasn't been manipulated. Patches of different brightness may indicate editing.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func legendItem(color: Color, label: String, description: String) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 16, height: 16)
                .overlay {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.secondary, lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var showOverlay = true

    return ELAOverlayView(
        originalImage: nil,
        elaImage: nil,
        showOverlay: $showOverlay
    )
    .padding()
    .frame(width: 500, height: 500)
}
