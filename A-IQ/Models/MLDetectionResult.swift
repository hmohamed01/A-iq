import CoreGraphics
import Foundation

// MARK: - ML Detection Result

/// Result from ML-based AI image detection
/// Implements: Req 2.2, 2.3, 2.4
struct MLDetectionResult: DetectionResult, Codable, Sendable {
    // MARK: DetectionResult Protocol

    let detectorName: String = "MLDetector"
    let score: Double
    let confidence: ResultConfidence
    let evidence: [Evidence]
    let error: DetectionError?

    // MARK: ML-Specific Properties

    /// The classification determined by the model
    let classification: ImageClassification

    /// Time taken for inference in milliseconds
    let inferenceTimeMs: Int

    /// Version of the ML model used
    let modelVersion: String

    /// Raw probabilities from the model output
    let rawProbabilities: [String: Double]

    // MARK: Initializers

    /// Create a successful ML detection result
    init(
        score: Double,
        classification: ImageClassification,
        inferenceTimeMs: Int,
        modelVersion: String,
        rawProbabilities: [String: Double] = [:]
    ) {
        self.score = score.clamped(to: 0 ... 1)
        self.classification = classification
        self.inferenceTimeMs = inferenceTimeMs
        self.modelVersion = modelVersion
        self.rawProbabilities = rawProbabilities
        error = nil

        // Determine confidence based on score distance from 0.5
        let certainty = abs(score - 0.5) * 2 // 0 at 0.5, 1 at 0 or 1
        if certainty > 0.6 {
            confidence = .high
        } else if certainty > 0.3 {
            confidence = .medium
        } else {
            confidence = .low
        }

        // Build evidence
        var evidenceList: [Evidence] = []

        evidenceList.append(Evidence(
            type: .mlClassification,
            description: "Model classified image as \(classification.displayName)",
            details: [
                "classification": classification.rawValue,
                "model_version": modelVersion,
                "inference_time_ms": String(inferenceTimeMs),
            ],
            isPositiveIndicator: classification == .aiGenerated || classification == .aiEnhanced
        ))

        evidenceList.append(Evidence(
            type: .mlConfidenceScore,
            description: "AI generation probability: \(Int(score * 100))%",
            details: [
                "score": String(format: "%.4f", score),
                "confidence_level": confidence.rawValue,
            ],
            isPositiveIndicator: score > 0.5
        ))

        evidence = evidenceList
    }

    /// Create a failed ML detection result
    init(error: DetectionError) {
        score = 0.5 // Neutral score on error
        classification = .uncertain
        inferenceTimeMs = 0
        modelVersion = "unknown"
        rawProbabilities = [:]
        confidence = .unavailable
        self.error = error
        evidence = []
    }
}

// MARK: - Image Classification

/// Classification categories from the ML model
enum ImageClassification: String, Sendable, Codable, CaseIterable {
    /// Image appears to be an authentic photograph
    case authentic

    /// Image appears to be fully AI-generated
    case aiGenerated = "ai_generated"

    /// Image appears to be a real photo enhanced/modified with AI
    case aiEnhanced = "ai_enhanced"

    /// Model could not determine classification
    case uncertain

    var displayName: String {
        switch self {
        case .authentic: return "Authentic"
        case .aiGenerated: return "AI-Generated"
        case .aiEnhanced: return "AI-Enhanced"
        case .uncertain: return "Uncertain"
        }
    }

    var isAIInvolved: Bool {
        self == .aiGenerated || self == .aiEnhanced
    }
}

// MARK: - ML Detection Constants

extension MLDetectionResult {
    /// Expected input size for the ML model (SigLIP uses 224x224)
    static let modelInputSize = CGSize(width: 224, height: 224)

    /// Maximum inference time before timeout (in seconds)
    static let maxInferenceTimeSeconds: TimeInterval = 2.0

    /// Default model version string (v2.0 = SigLIP model trained on modern generators)
    static let defaultModelVersion = "2.0.0"
}
