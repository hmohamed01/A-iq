import Foundation

// MARK: - Analysis Request

/// Represents a request to analyze one or more images
/// Implements: Req 1.1, 1.3, 1.4, 1.5, 1.6
struct AnalysisRequest: Identifiable, Sendable {
    let id: UUID
    let images: [ImageSource]
    let options: AnalysisOptions
    let timestamp: Date

    init(
        id: UUID = UUID(),
        images: [ImageSource],
        options: AnalysisOptions = AnalysisOptions(),
        timestamp: Date = Date()
    ) {
        self.id = id
        self.images = images
        self.options = options
        self.timestamp = timestamp
    }

    /// Convenience initializer for single image
    init(image: ImageSource, options: AnalysisOptions = AnalysisOptions()) {
        self.init(images: [image], options: options)
    }
}

// MARK: - Image Source

/// Represents the source of an image to be analyzed
/// Implements: Req 1.1, 1.5
enum ImageSource: Sendable, Identifiable {
    case fileURL(URL)
    case imageData(Data, suggestedName: String)
    case clipboard(Data)

    var id: String {
        switch self {
        case let .fileURL(url):
            return url.absoluteString
        case let .imageData(_, name):
            return "data:\(name)"
        case let .clipboard(data):
            return "clipboard:\(data.hashValue)"
        }
    }

    /// Get a display name for the image source
    var displayName: String {
        switch self {
        case let .fileURL(url):
            return url.lastPathComponent
        case let .imageData(_, name):
            return name
        case .clipboard:
            return "Clipboard Image"
        }
    }

    /// Get the file URL if available
    var fileURL: URL? {
        if case let .fileURL(url) = self {
            return url
        }
        return nil
    }

    /// Check if the source is from a file
    var isFile: Bool {
        if case .fileURL = self {
            return true
        }
        return false
    }
}

// MARK: - Analysis Options

/// Configuration options for the analysis pipeline
/// Implements: Req 2.1, 3.1, 4.1, 5.1
struct AnalysisOptions: Sendable {
    /// Whether to run ML-based detection
    var runMLDetection: Bool

    /// Whether to check C2PA provenance credentials
    var runProvenanceCheck: Bool

    /// Whether to analyze image metadata
    var runMetadataAnalysis: Bool

    /// Whether to perform forensic analysis (ELA)
    var runForensicAnalysis: Bool

    /// Whether to run face-swap detection (always runs, returns neutral if no faces)
    var runFaceSwapDetection: Bool

    /// Sensitivity threshold adjustment (-0.1 to +0.1)
    /// Positive values make detection more sensitive (more likely to flag as AI)
    var sensitivityAdjustment: Double

    init(
        runMLDetection: Bool = true,
        runProvenanceCheck: Bool = true,
        runMetadataAnalysis: Bool = true,
        runForensicAnalysis: Bool = true,
        runFaceSwapDetection: Bool = true,
        sensitivityAdjustment: Double = 0.0
    ) {
        self.runMLDetection = runMLDetection
        self.runProvenanceCheck = runProvenanceCheck
        self.runMetadataAnalysis = runMetadataAnalysis
        self.runForensicAnalysis = runForensicAnalysis
        self.runFaceSwapDetection = runFaceSwapDetection
        self.sensitivityAdjustment = sensitivityAdjustment.clamped(to: -0.1 ... 0.1)
    }

    /// Check if any detector is enabled
    var hasAnyDetectorEnabled: Bool {
        runMLDetection || runProvenanceCheck || runMetadataAnalysis || runForensicAnalysis || runFaceSwapDetection
    }

    /// Default options with all detectors enabled
    static let `default` = AnalysisOptions()

    /// Quick analysis (ML only)
    static let quick = AnalysisOptions(
        runMLDetection: true,
        runProvenanceCheck: false,
        runMetadataAnalysis: false,
        runForensicAnalysis: false,
        runFaceSwapDetection: false
    )
}

// MARK: - Helpers

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
