import SwiftUI
import UniformTypeIdentifiers

// MARK: - Drop Zone View

/// Drag-and-drop target area for images (A-IQ design system)
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
            // Clean card background with subtle shadow
            RoundedRectangle(cornerRadius: AIQRadius.xl, style: .continuous)
                .fill(AIQColors.cardBackground)
                .shadow(
                    color: AIQColors.dropShadow,
                    radius: isTargeted ? 16 : 8,
                    x: 0,
                    y: isTargeted ? 4 : 2
                )

            // Subtle inner border
            RoundedRectangle(cornerRadius: AIQRadius.xl - 2, style: .continuous)
                .strokeBorder(
                    isTargeted ? AIQColors.accent.opacity(0.5) : AIQColors.subtleBorder,
                    lineWidth: isTargeted ? 2 : 1
                )
                .padding(4)

            // Content
            VStack(spacing: AIQSpacing.lg) {
                // Icon with background circle
                ZStack {
                    Circle()
                        .fill(AIQColors.accent.opacity(isTargeted ? 0.15 : 0.08))
                        .frame(width: 88, height: 88)

                    Image(systemName: isTargeted ? "arrow.down.circle.fill" : "photo.badge.plus")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(AIQColors.accent)
                        .symbolEffect(.bounce, value: isTargeted)
                }

                VStack(spacing: AIQSpacing.sm) {
                    Text(isTargeted ? "Drop to Analyze" : "Drop Image Here")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(AIQColors.primaryText)

                    Text("or click to browse")
                        .font(.subheadline)
                        .foregroundStyle(AIQColors.tertiaryText)
                }

                // Supported formats (pill-shaped tags)
                HStack(spacing: AIQSpacing.sm) {
                    ForEach(["JPEG", "PNG", "HEIC", "WebP"], id: \.self) { format in
                        Text(format)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AIQColors.secondaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(white: 0.95))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(AIQSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: supportedTypes, isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
        .animation(.easeOut(duration: 0.2), value: isTargeted)
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
    .frame(width: 400, height: 350)
    .padding(AIQSpacing.xl)
    .background(AIQColors.paperWhite)
}
