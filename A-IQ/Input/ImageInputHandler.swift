import AppKit
import Foundation
import UniformTypeIdentifiers

// MARK: - Image Input Handler

/// Handles image input from multiple sources
/// Implements: Req 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7
actor ImageInputHandler {
    // MARK: Constants

    /// Supported image file extensions
    static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "webp", "tiff", "tif", "avif",
    ]

    /// Supported UTTypes for file picker
    static let supportedUTTypes: [UTType] = [
        .jpeg, .png, .heic, .heif, .webP, .tiff, .image,
    ]

    /// Maximum file size before warning (100MB)
    static let maxFileSizeBytes: Int = 100_000_000

    // MARK: Initialization

    init() {}

    // MARK: File Validation

    /// Validate a file URL and create ImageSource
    /// Implements: Req 1.1, 1.2
    nonisolated func validateFile(at url: URL) throws -> ImageSource {
        // Resolve symlinks to prevent path traversal attacks
        let resolvedURL = url.resolvingSymlinksInPath()
        
        // Check file exists
        guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
            throw ImageInputError.fileNotFound(resolvedURL.path)
        }

        // Check extension
        let ext = resolvedURL.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(ext) else {
            throw ImageInputError.unsupportedFormat(ext)
        }

        // Check readability
        guard FileManager.default.isReadableFile(atPath: resolvedURL.path) else {
            throw ImageInputError.fileNotReadable(resolvedURL.path)
        }

        // Check file size
        if let attrs = try? FileManager.default.attributesOfItem(atPath: resolvedURL.path),
           let size = attrs[.size] as? Int,
           size > Self.maxFileSizeBytes {
            throw ImageInputError.fileTooLarge(size)
        }

        return .fileURL(resolvedURL)
    }

    /// Check if file requires large file confirmation
    /// Implements: Req 1.7
    func requiresLargeFileConfirmation(url: URL) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int
        else {
            return false
        }
        return size > Self.maxFileSizeBytes
    }

    // MARK: File Picker

    /// Present file picker for image selection
    /// Implements: Req 1.3, 1.4
    /// Note: nonisolated to avoid actor-hopping overhead
    nonisolated func presentFilePicker(allowsMultiple: Bool = true) async -> [URL] {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let panel = NSOpenPanel()
                panel.canChooseFiles = true
                panel.canChooseDirectories = false
                panel.allowsMultipleSelection = allowsMultiple
                panel.allowedContentTypes = Self.supportedUTTypes

                panel.begin { response in
                    if response == .OK {
                        continuation.resume(returning: panel.urls)
                    } else {
                        continuation.resume(returning: [])
                    }
                }
            }
        }
    }

    /// Present folder picker for batch analysis
    /// Implements: Req 1.6
    nonisolated func presentFolderPicker() async -> URL? {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false

                panel.begin { response in
                    if response == .OK {
                        continuation.resume(returning: panel.url)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }

    // MARK: Clipboard

    /// Extract image from clipboard
    /// Implements: Req 1.5
    /// Note: Must be called from main thread due to NSPasteboard requirements
    @MainActor
    func extractFromClipboard() throws -> ImageSource {
        let pasteboard = NSPasteboard.general

        // Try to get image data
        if let data = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png) {
            return .clipboard(data)
        }

        // Try to get file URL
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let url = urls.first
        {
            return try validateFile(at: url)
        }

        throw ImageInputError.clipboardEmpty
    }

    // MARK: Folder Scanning

    /// Scan folder recursively for supported images
    /// Implements: Req 1.6
    func scanFolder(at url: URL) async throws -> [ImageSource] {
        var results: [ImageSource] = []

        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            let ext = fileURL.pathExtension.lowercased()
            if Self.supportedExtensions.contains(ext) {
                results.append(.fileURL(fileURL))
            }
        }

        return results
    }
}

// MARK: - Image Input Error

enum ImageInputError: LocalizedError {
    case unsupportedFormat(String)
    case fileTooLarge(Int)
    case fileNotFound(String)
    case fileNotReadable(String)
    case clipboardEmpty
    case invalidImageData

    var errorDescription: String? {
        switch self {
        case let .unsupportedFormat(ext):
            return "Unsupported format: .\(ext). Supported formats: JPEG, PNG, HEIC, WebP, TIFF, AVIF"
        case let .fileTooLarge(size):
            return "File is too large (\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))"
        case let .fileNotFound(path):
            return "File not found: \(path)"
        case let .fileNotReadable(path):
            return "Cannot read file: \(path)"
        case .clipboardEmpty:
            return "No image found in clipboard"
        case .invalidImageData:
            return "Invalid image data"
        }
    }
}
