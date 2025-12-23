import CoreGraphics
import Foundation

// MARK: - Aggregated Result

/// Final aggregated analysis result combining all detection signals
/// Implements: Req 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7
struct AggregatedResult: Identifiable, Sendable {
    // MARK: Identification

    let id: UUID
    let imageSource: ImageSource
    let timestamp: Date

    // MARK: Visual Data

    /// Thumbnail of the analyzed image
    let imageThumbnail: CGImage?

    /// Original image dimensions
    let imageSize: CGSize?

    /// File size in bytes (if available)
    let fileSizeBytes: Int?

    // MARK: Overall Assessment

    /// Combined confidence score (0.0 to 1.0)
    let overallScore: Double

    /// Final classification based on score
    let classification: OverallClassification

    /// Whether the result is definitive (e.g., C2PA proves AI origin)
    let isDefinitive: Bool

    /// Human-readable summary of the result
    let summary: String

    // MARK: Individual Results

    let mlResult: MLDetectionResult?
    let provenanceResult: ProvenanceResult?
    let metadataResult: MetadataResult?
    let forensicResult: ForensicResult?
    let faceSwapResult: FaceSwapResult?

    // MARK: Signal Breakdown

    let signalBreakdown: SignalBreakdown

    // MARK: Timing

    let totalAnalysisTimeMs: Int

    // MARK: Initializers

    init(
        id: UUID = UUID(),
        imageSource: ImageSource,
        timestamp: Date = Date(),
        imageThumbnail: CGImage? = nil,
        imageSize: CGSize? = nil,
        fileSizeBytes: Int? = nil,
        overallScore: Double,
        classification: OverallClassification,
        isDefinitive: Bool,
        summary: String,
        mlResult: MLDetectionResult? = nil,
        provenanceResult: ProvenanceResult? = nil,
        metadataResult: MetadataResult? = nil,
        forensicResult: ForensicResult? = nil,
        faceSwapResult: FaceSwapResult? = nil,
        signalBreakdown: SignalBreakdown,
        totalAnalysisTimeMs: Int
    ) {
        self.id = id
        self.imageSource = imageSource
        self.timestamp = timestamp
        self.imageThumbnail = imageThumbnail
        self.imageSize = imageSize
        self.fileSizeBytes = fileSizeBytes
        self.overallScore = overallScore.clamped(to: 0 ... 1)
        self.classification = classification
        self.isDefinitive = isDefinitive
        self.summary = summary
        self.mlResult = mlResult
        self.provenanceResult = provenanceResult
        self.metadataResult = metadataResult
        self.forensicResult = forensicResult
        self.faceSwapResult = faceSwapResult
        self.signalBreakdown = signalBreakdown
        self.totalAnalysisTimeMs = totalAnalysisTimeMs
    }

    // MARK: Copy Methods

    /// Create a copy with the thumbnail restored (used when loading from history)
    func withThumbnail(_ thumbnail: CGImage) -> AggregatedResult {
        AggregatedResult(
            id: id,
            imageSource: imageSource,
            timestamp: timestamp,
            imageThumbnail: thumbnail,
            imageSize: imageSize,
            fileSizeBytes: fileSizeBytes,
            overallScore: overallScore,
            classification: classification,
            isDefinitive: isDefinitive,
            summary: summary,
            mlResult: mlResult,
            provenanceResult: provenanceResult,
            metadataResult: metadataResult,
            forensicResult: forensicResult,
            faceSwapResult: faceSwapResult,
            signalBreakdown: signalBreakdown,
            totalAnalysisTimeMs: totalAnalysisTimeMs
        )
    }

    // MARK: Computed Properties

    /// Percentage display of overall score
    var scorePercentage: Int {
        Int(overallScore * 100)
    }

    /// All evidence from all detectors
    var allEvidence: [Evidence] {
        var evidence: [Evidence] = []
        if let ml = mlResult { evidence.append(contentsOf: ml.evidence) }
        if let prov = provenanceResult { evidence.append(contentsOf: prov.evidence) }
        if let meta = metadataResult { evidence.append(contentsOf: meta.evidence) }
        if let forensic = forensicResult { evidence.append(contentsOf: forensic.evidence) }
        if let faceSwap = faceSwapResult { evidence.append(contentsOf: faceSwap.evidence) }
        return evidence
    }

    /// Evidence indicating AI generation
    var aiIndicators: [Evidence] {
        allEvidence.filter { $0.isPositiveIndicator }
    }

    /// Evidence indicating authenticity
    var authenticityIndicators: [Evidence] {
        allEvidence.filter { !$0.isPositiveIndicator }
    }

    /// Count of successful detectors
    var successfulDetectorCount: Int {
        [mlResult?.isSuccessful, provenanceResult?.isSuccessful,
         metadataResult?.isSuccessful, forensicResult?.isSuccessful,
         faceSwapResult?.isSuccessful]
            .compactMap { $0 }
            .filter { $0 }
            .count
    }

    /// ELA image if available
    var elaImage: CGImage? {
        forensicResult?.elaImage
    }
}

// MARK: - Overall Classification

/// Final classification of the image
/// Implements: Req 6.4, 6.5, 6.6
enum OverallClassification: String, Sendable, Codable, CaseIterable {
    /// Score < 30%: Low probability of AI generation
    case likelyAuthentic = "likely_authentic"

    /// Score 30-70%: Uncertain, manual review recommended
    case uncertain

    /// Score > 70%: High probability of AI generation
    case likelyAIGenerated = "likely_ai_generated"

    /// C2PA or other definitive proof of AI generation
    case confirmedAIGenerated = "confirmed_ai_generated"

    var displayName: String {
        switch self {
        case .likelyAuthentic: return "Likely Authentic"
        case .uncertain: return "Uncertain"
        case .likelyAIGenerated: return "Likely AI-Generated"
        case .confirmedAIGenerated: return "Confirmed AI-Generated"
        }
    }

    var shortName: String {
        switch self {
        case .likelyAuthentic: return "Authentic"
        case .uncertain: return "Uncertain"
        case .likelyAIGenerated: return "AI-Generated"
        case .confirmedAIGenerated: return "AI-Generated"
        }
    }

    /// SwiftUI color name for the classification
    var colorName: String {
        switch self {
        case .likelyAuthentic: return "green"
        case .uncertain: return "yellow"
        case .likelyAIGenerated, .confirmedAIGenerated: return "red"
        }
    }

    var isAIGenerated: Bool {
        self == .likelyAIGenerated || self == .confirmedAIGenerated
    }
}

// MARK: - Signal Breakdown

/// Breakdown of each signal's contribution to the final score
/// Implements: Req 6.7
struct SignalBreakdown: Sendable, Codable {
    /// ML detection contribution (weight: 40% without faces, 35% with faces)
    let mlContribution: SignalContribution

    /// Provenance check contribution (weight: 30% without faces, 25% with faces)
    let provenanceContribution: SignalContribution

    /// Metadata analysis contribution (weight: 15% without faces, 10% with faces)
    let metadataContribution: SignalContribution

    /// Forensic analysis contribution (weight: 15% without faces, 10% with faces)
    let forensicContribution: SignalContribution

    /// Face-swap detection contribution (weight: 0% without faces, 20% with faces)
    let faceSwapContribution: SignalContribution

    /// Default signal weights (no faces detected)
    /// Implements: Req 6.2
    static let weights = SignalWeights(
        ml: 0.40,
        provenance: 0.30,
        metadata: 0.15,
        forensic: 0.15,
        faceSwap: 0.0
    )

    /// Dynamic weights based on whether faces were detected
    static func weights(facesDetected: Bool) -> SignalWeights {
        if facesDetected {
            return SignalWeights(
                ml: 0.35,
                provenance: 0.25,
                metadata: 0.10,
                forensic: 0.10,
                faceSwap: 0.20
            )
        } else {
            return weights
        }
    }

    init(
        mlContribution: SignalContribution,
        provenanceContribution: SignalContribution,
        metadataContribution: SignalContribution,
        forensicContribution: SignalContribution,
        faceSwapContribution: SignalContribution = .unavailable(weight: 0.0)
    ) {
        self.mlContribution = mlContribution
        self.provenanceContribution = provenanceContribution
        self.metadataContribution = metadataContribution
        self.forensicContribution = forensicContribution
        self.faceSwapContribution = faceSwapContribution
    }

    /// Get all contributions as an array for iteration
    /// Face-swap is only included when available (faces detected)
    var allContributions: [(name: String, contribution: SignalContribution, weight: Double)] {
        var contributions = [
            ("ML Detection", mlContribution, Self.weights.ml),
            ("Provenance", provenanceContribution, Self.weights.provenance),
            ("Metadata", metadataContribution, Self.weights.metadata),
            ("Forensics", forensicContribution, Self.weights.forensic),
        ]

        // Only include face-swap when it was actually run (faces detected)
        if faceSwapContribution.isAvailable {
            let faceWeights = Self.weights(facesDetected: true)
            contributions.append(("Face-Swap", faceSwapContribution, faceWeights.faceSwap))
        }

        return contributions
    }
}

// MARK: - Signal Contribution

/// Individual signal's contribution to the score
struct SignalContribution: Sendable, Codable {
    /// Raw score from the detector (0.0 to 1.0)
    let rawScore: Double

    /// Weighted contribution to final score
    let weightedScore: Double

    /// Whether this signal was available
    let isAvailable: Bool

    /// Confidence of this signal
    let confidence: ResultConfidence

    init(rawScore: Double, weight: Double, isAvailable: Bool, confidence: ResultConfidence) {
        self.rawScore = rawScore.clamped(to: 0 ... 1)
        weightedScore = isAvailable ? rawScore * weight : 0
        self.isAvailable = isAvailable
        self.confidence = confidence
    }

    static func unavailable(weight: Double) -> SignalContribution {
        SignalContribution(rawScore: 0.5, weight: weight, isAvailable: false, confidence: .unavailable)
    }
}

// MARK: - Signal Weights

/// Weights for each detection signal
struct SignalWeights: Sendable {
    let ml: Double
    let provenance: Double
    let metadata: Double
    let forensic: Double
    let faceSwap: Double

    init(ml: Double, provenance: Double, metadata: Double, forensic: Double, faceSwap: Double = 0.0) {
        self.ml = ml
        self.provenance = provenance
        self.metadata = metadata
        self.forensic = forensic
        self.faceSwap = faceSwap
    }

    var total: Double {
        ml + provenance + metadata + forensic + faceSwap
    }
}

// MARK: - Classification Thresholds

extension OverallClassification {
    /// Thresholds for classification
    /// Implements: Req 6.4, 6.5, 6.6
    enum Thresholds {
        /// Below this score → Likely Authentic
        static let likelyAuthentic: Double = 0.30

        /// Above this score → Likely AI-Generated
        static let likelyAIGenerated: Double = 0.70
    }

    /// Determine classification from score
    static func from(score: Double, isDefinitive: Bool) -> OverallClassification {
        if isDefinitive {
            return .confirmedAIGenerated
        } else if score < Thresholds.likelyAuthentic {
            return .likelyAuthentic
        } else if score > Thresholds.likelyAIGenerated {
            return .likelyAIGenerated
        } else {
            return .uncertain
        }
    }
}

// MARK: - Codable Conformance (excluding CGImage)

extension AggregatedResult: Codable {
    enum CodingKeys: String, CodingKey {
        case id, timestamp, overallScore, classification, isDefinitive, summary
        case mlResult, provenanceResult, metadataResult, forensicResult, faceSwapResult
        case signalBreakdown, totalAnalysisTimeMs
        case imageSourceType, imageSourceValue
        case imageWidth, imageHeight, fileSizeBytes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        overallScore = try container.decode(Double.self, forKey: .overallScore)
        classification = try container.decode(OverallClassification.self, forKey: .classification)
        isDefinitive = try container.decode(Bool.self, forKey: .isDefinitive)
        summary = try container.decode(String.self, forKey: .summary)
        mlResult = try container.decodeIfPresent(MLDetectionResult.self, forKey: .mlResult)
        provenanceResult = try container.decodeIfPresent(ProvenanceResult.self, forKey: .provenanceResult)
        metadataResult = try container.decodeIfPresent(MetadataResult.self, forKey: .metadataResult)
        forensicResult = try container.decodeIfPresent(ForensicResult.self, forKey: .forensicResult)
        faceSwapResult = try container.decodeIfPresent(FaceSwapResult.self, forKey: .faceSwapResult)
        signalBreakdown = try container.decode(SignalBreakdown.self, forKey: .signalBreakdown)
        totalAnalysisTimeMs = try container.decode(Int.self, forKey: .totalAnalysisTimeMs)

        // Decode image source
        let sourceType = try container.decode(String.self, forKey: .imageSourceType)
        let sourceValue = try container.decode(String.self, forKey: .imageSourceValue)
        switch sourceType {
        case "fileURL":
            imageSource = .fileURL(URL(fileURLWithPath: sourceValue))
        default:
            imageSource = .imageData(Data(), suggestedName: sourceValue)
        }

        // Decode optional size
        if let width = try container.decodeIfPresent(CGFloat.self, forKey: .imageWidth),
           let height = try container.decodeIfPresent(CGFloat.self, forKey: .imageHeight)
        {
            imageSize = CGSize(width: width, height: height)
        } else {
            imageSize = nil
        }

        fileSizeBytes = try container.decodeIfPresent(Int.self, forKey: .fileSizeBytes)
        imageThumbnail = nil // CGImage cannot be decoded
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(overallScore, forKey: .overallScore)
        try container.encode(classification, forKey: .classification)
        try container.encode(isDefinitive, forKey: .isDefinitive)
        try container.encode(summary, forKey: .summary)
        try container.encodeIfPresent(mlResult, forKey: .mlResult)
        try container.encodeIfPresent(provenanceResult, forKey: .provenanceResult)
        try container.encodeIfPresent(metadataResult, forKey: .metadataResult)
        try container.encodeIfPresent(forensicResult, forKey: .forensicResult)
        try container.encodeIfPresent(faceSwapResult, forKey: .faceSwapResult)
        try container.encode(signalBreakdown, forKey: .signalBreakdown)
        try container.encode(totalAnalysisTimeMs, forKey: .totalAnalysisTimeMs)

        // Encode image source
        switch imageSource {
        case let .fileURL(url):
            try container.encode("fileURL", forKey: .imageSourceType)
            try container.encode(url.path, forKey: .imageSourceValue)
        case let .imageData(_, name):
            try container.encode("imageData", forKey: .imageSourceType)
            try container.encode(name, forKey: .imageSourceValue)
        case .clipboard:
            try container.encode("clipboard", forKey: .imageSourceType)
            try container.encode("clipboard", forKey: .imageSourceValue)
        }

        // Encode optional size
        if let size = imageSize {
            try container.encode(size.width, forKey: .imageWidth)
            try container.encode(size.height, forKey: .imageHeight)
        }

        try container.encodeIfPresent(fileSizeBytes, forKey: .fileSizeBytes)
        // CGImage is not encoded
    }
}
