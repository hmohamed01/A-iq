import SwiftUI
import UniformTypeIdentifiers

// MARK: - Drop Zone View

/// Drag-and-drop target area for images
/// Implements: Req 1.1
struct DropZoneView: View {
    let onDrop: ([URL]) -> Void

    @State private var isTargeted: Bool = false

    /// Supported image types for drop
    private let supportedTypes: [UTType] = [
        .jpeg,
        .png,
        .heic,
        .heif,
        .webP,
        .tiff,
        .image,
    ]

    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 16)
                .fill(backgroundColor)
                .strokeBorder(
                    borderColor,
                    style: StrokeStyle(lineWidth: 3, dash: [12, 6])
                )

            // Content
            VStack(spacing: 16) {
                Image(systemName: isTargeted ? "arrow.down.doc.fill" : "photo.on.rectangle.angled")
                    .font(.system(size: 56))
                    .foregroundStyle(iconColor)
                    .symbolEffect(.bounce, value: isTargeted)

                Text(isTargeted ? "Drop to Analyze" : "Drop Image Here")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(isTargeted ? .primary : .secondary)

                Text("or use the buttons below")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)

                // Supported formats
                HStack(spacing: 8) {
                    ForEach(["JPEG", "PNG", "HEIC", "WebP", "TIFF"], id: \.self) { format in
                        Text(format)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
                .foregroundStyle(.secondary)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: supportedTypes, isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
        .animation(.easeInOut(duration: 0.2), value: isTargeted)
    }

    // MARK: Styling

    private var backgroundColor: Color {
        if isTargeted {
            return Color.accentColor.opacity(0.1)
        } else {
            return Color(nsColor: .controlBackgroundColor)
        }
    }

    private var borderColor: Color {
        if isTargeted {
            return Color.accentColor
        } else {
            return Color.secondary.opacity(0.3)
        }
    }

    private var iconColor: Color {
        if isTargeted {
            return Color.accentColor
        } else {
            return Color.secondary
        }
    }

    // MARK: Drop Handling

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        Task {
            await loadAndProcessURLs(from: providers)
        }
        return true
    }

    @MainActor
    private func loadAndProcessURLs(from providers: [NSItemProvider]) async {
        var urls: [URL] = []

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                if let url = await loadURL(from: provider) {
                    urls.append(url)
                }
            }
        }

        if !urls.isEmpty {
            onDrop(urls)
        }
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let itemURL = item as? URL {
                    url = itemURL
                }
                continuation.resume(returning: url)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    DropZoneView { urls in
        print("Dropped: \(urls)")
    }
    .frame(width: 400, height: 300)
    .padding()
}
