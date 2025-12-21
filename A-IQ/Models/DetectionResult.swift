import CoreGraphics
import Foundation

// MARK: - Detection Result Protocol

/// Protocol for all detection results
/// Implements: Req 2.2, 3.2, 4.1, 5.2
protocol DetectionResult: Sendable {
    /// Name of the detector that produced this result
    var detectorName: String { get }

    /// Score from 0.0 (authentic) to 1.0 (AI-generated)
    var score: Double { get }

    /// Confidence level in the result
    var confidence: ResultConfidence { get }

    /// Evidence supporting the result
    var evidence: [Evidence] { get }

    /// Error if detection failed
    var error: DetectionError? { get }

    /// Whether the detection completed successfully
    var isSuccessful: Bool { get }
}

extension DetectionResult {
    var isSuccessful: Bool {
        error == nil
    }
}

// MARK: - Result Confidence

/// Confidence level in a detection result
enum ResultConfidence: String, Sendable, Codable, CaseIterable {
    /// High confidence in the result
    case high

    /// Medium confidence - result is likely correct
    case medium

    /// Low confidence - result should be treated cautiously
    case low

    /// Detection could not be performed
    case unavailable

    var displayName: String {
        switch self {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        case .unavailable: return "Unavailable"
        }
    }

    var weight: Double {
        switch self {
        case .high: return 1.0
        case .medium: return 0.7
        case .low: return 0.4
        case .unavailable: return 0.0
        }
    }
}

// MARK: - Evidence

/// Evidence supporting a detection result
struct Evidence: Sendable, Codable, Identifiable {
    let id: UUID
    let type: EvidenceType
    let description: String
    let details: [String: String]
    let isPositiveIndicator: Bool // True if indicates AI generation

    init(
        id: UUID = UUID(),
        type: EvidenceType,
        description: String,
        details: [String: String] = [:],
        isPositiveIndicator: Bool = true
    ) {
        self.id = id
        self.type = type
        self.description = description
        self.details = details
        self.isPositiveIndicator = isPositiveIndicator
    }
}

// MARK: - Evidence Type

/// Types of evidence that can be collected
enum EvidenceType: String, Sendable, Codable, CaseIterable {
    // ML Detection
    case mlClassification = "ml_classification"
    case mlConfidenceScore = "ml_confidence_score"

    // Provenance
    case provenanceCredentialFound = "provenance_credential_found"
    case provenanceCredentialValid = "provenance_credential_valid"
    case provenanceCredentialInvalid = "provenance_credential_invalid"
    case provenanceAIToolDetected = "provenance_ai_tool_detected"
    case provenanceNoCredentials = "provenance_no_credentials"
    case provenanceUntrustedSigner = "provenance_untrusted_signer"

    // Metadata
    case metadataPresent = "metadata_present"
    case metadataAbsent = "metadata_absent"
    case metadataCameraInfo = "metadata_camera_info"
    case metadataGPSLocation = "metadata_gps_location"
    case metadataAISoftware = "metadata_ai_software"
    case metadataAnomaly = "metadata_anomaly"
    case metadataDateAnomaly = "metadata_date_anomaly"

    // Forensic
    case forensicELAInconsistency = "forensic_ela_inconsistency"
    case forensicNoiseAnomaly = "forensic_noise_anomaly"
    case forensicCompressionArtifact = "forensic_compression_artifact"
    case forensicClean = "forensic_clean"
    case forensicFrequencyAnomaly = "forensic_frequency_anomaly"
    case forensicSpectralSignature = "forensic_spectral_signature"

    var category: String {
        switch self {
        case .mlClassification, .mlConfidenceScore:
            return "ML Detection"
        case .provenanceCredentialFound, .provenanceCredentialValid,
             .provenanceCredentialInvalid, .provenanceAIToolDetected,
             .provenanceNoCredentials, .provenanceUntrustedSigner:
            return "Provenance"
        case .metadataPresent, .metadataAbsent, .metadataCameraInfo,
             .metadataGPSLocation, .metadataAISoftware, .metadataAnomaly,
             .metadataDateAnomaly:
            return "Metadata"
        case .forensicELAInconsistency, .forensicNoiseAnomaly,
             .forensicCompressionArtifact, .forensicClean,
             .forensicFrequencyAnomaly, .forensicSpectralSignature:
            return "Forensics"
        }
    }
}

// MARK: - Detection Error

/// Errors that can occur during detection
enum DetectionError: Error, Sendable, Codable {
    case modelNotLoaded
    case modelInferenceFailed(String)
    case inferenceTimeout
    case imageLoadFailed
    case imageFormatUnsupported
    case fileNotFound
    case fileReadError(String)
    case c2paToolNotFound
    case c2paToolExecutionFailed(String)
    case c2paToolTimeout
    case metadataExtractionFailed
    case forensicAnalysisFailed(String)
    case cancelled
    case unknown(String)

    var localizedDescription: String {
        switch self {
        case .modelNotLoaded:
            return "ML model could not be loaded"
        case let .modelInferenceFailed(reason):
            return "ML inference failed: \(reason)"
        case .inferenceTimeout:
            return "ML inference timed out"
        case .imageLoadFailed:
            return "Failed to load image data"
        case .imageFormatUnsupported:
            return "Image format is not supported"
        case .fileNotFound:
            return "Image file not found"
        case let .fileReadError(reason):
            return "Failed to read file: \(reason)"
        case .c2paToolNotFound:
            return "C2PA verification tool not found"
        case let .c2paToolExecutionFailed(reason):
            return "C2PA verification failed: \(reason)"
        case .c2paToolTimeout:
            return "C2PA verification timed out"
        case .metadataExtractionFailed:
            return "Failed to extract image metadata"
        case let .forensicAnalysisFailed(reason):
            return "Forensic analysis failed: \(reason)"
        case .cancelled:
            return "Analysis was cancelled"
        case let .unknown(reason):
            return "Unknown error: \(reason)"
        }
    }

    var isRecoverable: Bool {
        switch self {
        case .inferenceTimeout, .c2paToolTimeout, .cancelled:
            return true
        default:
            return false
        }
    }
}

// MARK: - Codable Conformance for DetectionError

extension DetectionError {
    enum CodingKeys: String, CodingKey {
        case type, message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""

        switch type {
        case "modelNotLoaded": self = .modelNotLoaded
        case "modelInferenceFailed": self = .modelInferenceFailed(message)
        case "inferenceTimeout": self = .inferenceTimeout
        case "imageLoadFailed": self = .imageLoadFailed
        case "imageFormatUnsupported": self = .imageFormatUnsupported
        case "fileNotFound": self = .fileNotFound
        case "fileReadError": self = .fileReadError(message)
        case "c2paToolNotFound": self = .c2paToolNotFound
        case "c2paToolExecutionFailed": self = .c2paToolExecutionFailed(message)
        case "c2paToolTimeout": self = .c2paToolTimeout
        case "metadataExtractionFailed": self = .metadataExtractionFailed
        case "forensicAnalysisFailed": self = .forensicAnalysisFailed(message)
        case "cancelled": self = .cancelled
        default: self = .unknown(message)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .modelNotLoaded:
            try container.encode("modelNotLoaded", forKey: .type)
        case let .modelInferenceFailed(msg):
            try container.encode("modelInferenceFailed", forKey: .type)
            try container.encode(msg, forKey: .message)
        case .inferenceTimeout:
            try container.encode("inferenceTimeout", forKey: .type)
        case .imageLoadFailed:
            try container.encode("imageLoadFailed", forKey: .type)
        case .imageFormatUnsupported:
            try container.encode("imageFormatUnsupported", forKey: .type)
        case .fileNotFound:
            try container.encode("fileNotFound", forKey: .type)
        case let .fileReadError(msg):
            try container.encode("fileReadError", forKey: .type)
            try container.encode(msg, forKey: .message)
        case .c2paToolNotFound:
            try container.encode("c2paToolNotFound", forKey: .type)
        case let .c2paToolExecutionFailed(msg):
            try container.encode("c2paToolExecutionFailed", forKey: .type)
            try container.encode(msg, forKey: .message)
        case .c2paToolTimeout:
            try container.encode("c2paToolTimeout", forKey: .type)
        case .metadataExtractionFailed:
            try container.encode("metadataExtractionFailed", forKey: .type)
        case let .forensicAnalysisFailed(msg):
            try container.encode("forensicAnalysisFailed", forKey: .type)
            try container.encode(msg, forKey: .message)
        case .cancelled:
            try container.encode("cancelled", forKey: .type)
        case let .unknown(msg):
            try container.encode("unknown", forKey: .type)
            try container.encode(msg, forKey: .message)
        }
    }
}
