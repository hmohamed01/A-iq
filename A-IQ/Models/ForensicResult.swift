import CoreGraphics
import Foundation

// MARK: - Forensic Result

/// Result from forensic analysis (ELA, noise analysis)
/// Implements: Req 5.1, 5.2, 5.3, 5.4
struct ForensicResult: DetectionResult, Sendable {
    // MARK: DetectionResult Protocol

    let detectorName: String = "ForensicAnalyzer"
    let score: Double
    let confidence: ResultConfidence
    let evidence: [Evidence]
    let error: DetectionError?

    // MARK: Forensic-Specific Properties

    /// Error Level Analysis visualization image
    let elaImage: CGImage?

    /// FFT frequency spectrum visualization image
    let fftImage: CGImage?

    /// Regions flagged as suspicious
    let suspiciousRegions: [SuspiciousRegion]

    /// Analysis method used
    let analysisMethod: ForensicMethod

    /// Processing time in milliseconds
    let processingTimeMs: Int

    /// Overall manipulation probability from forensic analysis
    let manipulationProbability: Double

    // MARK: Initializers

    /// Create a successful forensic result
    init(
        elaImage: CGImage?,
        fftImage: CGImage? = nil,
        suspiciousRegions: [SuspiciousRegion],
        analysisMethod: ForensicMethod,
        processingTimeMs: Int,
        manipulationProbability: Double
    ) {
        self.elaImage = elaImage
        self.fftImage = fftImage
        self.suspiciousRegions = suspiciousRegions
        self.analysisMethod = analysisMethod
        self.processingTimeMs = processingTimeMs
        self.manipulationProbability = manipulationProbability.clamped(to: 0 ... 1)
        error = nil

        // Score is based on manipulation probability
        score = manipulationProbability

        // Confidence based on analysis method and findings
        if analysisMethod == .skipped {
            confidence = .unavailable
        } else if !suspiciousRegions.isEmpty {
            confidence = .high
        } else if elaImage != nil {
            confidence = .medium
        } else {
            confidence = .low
        }

        // Build evidence
        var evidenceList: [Evidence] = []

        if !suspiciousRegions.isEmpty {
            let regionCount = suspiciousRegions.count
            let totalArea = suspiciousRegions.reduce(0.0) { $0 + $1.areaPercentage }

            evidenceList.append(Evidence(
                type: .forensicELAInconsistency,
                description: "\(regionCount) suspicious region(s) detected covering \(Int(totalArea))% of image",
                details: [
                    "region_count": String(regionCount),
                    "total_area_percent": String(format: "%.1f", totalArea),
                    "analysis_method": analysisMethod.rawValue,
                ],
                isPositiveIndicator: true
            ))
        } else if analysisMethod != .skipped {
            evidenceList.append(Evidence(
                type: .forensicClean,
                description: "No significant compression artifacts or manipulation detected",
                details: ["analysis_method": analysisMethod.rawValue],
                isPositiveIndicator: false
            ))
        }

        evidence = evidenceList
    }

    /// Create a failed forensic result
    init(error: DetectionError) {
        elaImage = nil
        fftImage = nil
        suspiciousRegions = []
        analysisMethod = .skipped
        processingTimeMs = 0
        manipulationProbability = 0.5
        score = 0.5
        confidence = .unavailable
        self.error = error
        evidence = []
    }

    /// Create a skipped forensic result (e.g., for lossless formats where ELA doesn't apply)
    static func skipped(reason _: String) -> ForensicResult {
        ForensicResult(
            elaImage: nil,
            suspiciousRegions: [],
            analysisMethod: .skipped,
            processingTimeMs: 0,
            manipulationProbability: 0.5
        )
    }
}

// MARK: - Codable Conformance (excluding CGImage)

extension ForensicResult: Codable {
    enum CodingKeys: String, CodingKey {
        case score, confidence, evidence, error
        case suspiciousRegions, analysisMethod, processingTimeMs, manipulationProbability
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        score = try container.decode(Double.self, forKey: .score)
        confidence = try container.decode(ResultConfidence.self, forKey: .confidence)
        evidence = try container.decode([Evidence].self, forKey: .evidence)
        error = try container.decodeIfPresent(DetectionError.self, forKey: .error)
        suspiciousRegions = try container.decode([SuspiciousRegion].self, forKey: .suspiciousRegions)
        analysisMethod = try container.decode(ForensicMethod.self, forKey: .analysisMethod)
        processingTimeMs = try container.decode(Int.self, forKey: .processingTimeMs)
        manipulationProbability = try container.decode(Double.self, forKey: .manipulationProbability)
        elaImage = nil // CGImage cannot be decoded
        fftImage = nil // CGImage cannot be decoded
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(score, forKey: .score)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(evidence, forKey: .evidence)
        try container.encodeIfPresent(error, forKey: .error)
        try container.encode(suspiciousRegions, forKey: .suspiciousRegions)
        try container.encode(analysisMethod, forKey: .analysisMethod)
        try container.encode(processingTimeMs, forKey: .processingTimeMs)
        try container.encode(manipulationProbability, forKey: .manipulationProbability)
        // CGImage is not encoded
    }
}

// MARK: - Suspicious Region

/// A region flagged as potentially manipulated
struct SuspiciousRegion: Sendable, Codable, Identifiable {
    let id: UUID
    let bounds: CGRect
    let intensity: Double // 0.0 to 1.0, how suspicious
    let areaPercentage: Double // Percentage of total image

    init(
        id: UUID = UUID(),
        bounds: CGRect,
        intensity: Double,
        areaPercentage: Double
    ) {
        self.id = id
        self.bounds = bounds
        self.intensity = intensity.clamped(to: 0 ... 1)
        self.areaPercentage = areaPercentage.clamped(to: 0 ... 100)
    }
}

// NOTE: CGRect Codable conformance is provided by CoreGraphics

// MARK: - Forensic Method

/// Analysis method used for forensic examination
enum ForensicMethod: String, Sendable, Codable {
    /// Error Level Analysis (for JPEG)
    case errorLevelAnalysis = "ela"

    /// Noise pattern analysis
    case noiseAnalysis = "noise"

    /// Frequency domain analysis (FFT)
    case frequencyDomain = "frequency"

    /// Combined ELA/noise + FFT analysis
    case combined = "combined"

    /// Analysis was skipped
    case skipped

    var displayName: String {
        switch self {
        case .errorLevelAnalysis: return "Error Level Analysis"
        case .noiseAnalysis: return "Noise Analysis"
        case .frequencyDomain: return "Frequency Domain"
        case .combined: return "Combined Analysis"
        case .skipped: return "Skipped"
        }
    }
}

// MARK: - Forensic Constants

extension ForensicResult {
    /// ELA recompression quality level
    static let elaQuality = 90

    /// Maximum processing time before timeout
    /// Implements: Req 5.5
    static let maxProcessingTimeSeconds: TimeInterval = 3.0

    /// Maximum resolution for full analysis (4K)
    static let maxResolution = CGSize(width: 3840, height: 2160)
}
