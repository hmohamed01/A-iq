import CoreGraphics
import Foundation

// MARK: - Face Swap Result

/// Result from face-swap/deepfake detection analysis
/// Implements face boundary forensics to detect manipulation artifacts
struct FaceSwapResult: DetectionResult, Codable, Sendable {
    // MARK: DetectionResult Protocol

    let detectorName: String = "Face-Swap Detection"
    let score: Double
    let confidence: ResultConfidence
    let evidence: [Evidence]
    let error: DetectionError?

    // MARK: Face-Swap Specific Properties

    /// Number of faces detected in the image
    let faceCount: Int

    /// Individual analysis for each detected face
    let faceAnalyses: [FaceAnalysis]

    /// Whether faces were detected (determines if analysis was performed)
    let facesDetected: Bool

    /// Processing time in milliseconds
    let processingTimeMs: Int

    /// Detected artifacts across all faces
    let artifacts: [FaceSwapArtifact]

    // MARK: Constants

    /// Maximum processing time before timeout
    static let maxProcessingTimeSeconds: TimeInterval = 2.5

    /// Minimum face size as percentage of image area
    static let minFaceSizePercent: Double = 0.03

    /// Boundary analysis band width as percentage of face width
    static let boundaryBandPercent: Double = 0.10

    // MARK: Initializers

    /// Create a result when faces were analyzed
    init(faceAnalyses: [FaceAnalysis], processingTimeMs: Int) {
        self.faceAnalyses = faceAnalyses
        faceCount = faceAnalyses.count
        facesDetected = !faceAnalyses.isEmpty
        self.processingTimeMs = processingTimeMs
        error = nil

        // Aggregate artifacts from all faces
        artifacts = faceAnalyses.flatMap(\.artifacts)

        // Score: weighted by face size (larger faces more reliable)
        if faceAnalyses.isEmpty {
            score = 0.5
            confidence = .unavailable
        } else {
            // Average scores, weighted by face area
            let totalArea = faceAnalyses.reduce(0.0) { $0 + $1.faceBounds.width * $1.faceBounds.height }
            let weightedScore = faceAnalyses.reduce(0.0) {
                $0 + $1.score * ($1.faceBounds.width * $1.faceBounds.height / max(totalArea, 1))
            }
            score = weightedScore.clamped(to: 0 ... 1)

            // Confidence based on face count and artifact detection
            if artifacts.isEmpty {
                confidence = .low // No artifacts found - could be authentic or missed detection
            } else if artifacts.contains(where: { $0.severity == .high }) {
                confidence = .high
            } else {
                confidence = .medium
            }
        }

        // Build evidence
        var evidenceList: [Evidence] = []

        if facesDetected {
            evidenceList.append(Evidence(
                type: .faceSwapFaceDetected,
                description: "\(faceCount) face(s) detected and analyzed",
                details: ["face_count": String(faceCount)],
                isPositiveIndicator: false
            ))

            for artifact in artifacts {
                evidenceList.append(Evidence(
                    type: artifact.type.toEvidenceType(),
                    description: artifact.description,
                    details: ["severity": artifact.severity.rawValue],
                    isPositiveIndicator: true
                ))
            }

            // Add summary evidence if no artifacts found
            if artifacts.isEmpty {
                evidenceList.append(Evidence(
                    type: .faceSwapFaceDetected,
                    description: "No face-swap artifacts detected",
                    details: ["analysis": "clean"],
                    isPositiveIndicator: false
                ))
            }
        }

        evidence = evidenceList
    }

    /// Create a result when no faces were detected
    static func noFaces(processingTimeMs: Int) -> FaceSwapResult {
        FaceSwapResult(
            faceCount: 0,
            faceAnalyses: [],
            facesDetected: false,
            processingTimeMs: processingTimeMs,
            artifacts: [],
            score: 0.5,
            confidence: .unavailable,
            evidence: [Evidence(
                type: .faceSwapNoFaces,
                description: "No faces detected in image",
                isPositiveIndicator: false
            )],
            error: nil
        )
    }

    /// Create a failed result
    init(error: DetectionError) {
        faceCount = 0
        faceAnalyses = []
        facesDetected = false
        processingTimeMs = 0
        artifacts = []
        score = 0.5
        confidence = .unavailable
        evidence = []
        self.error = error
    }

    // Private init for factory methods
    private init(
        faceCount: Int,
        faceAnalyses: [FaceAnalysis],
        facesDetected: Bool,
        processingTimeMs: Int,
        artifacts: [FaceSwapArtifact],
        score: Double,
        confidence: ResultConfidence,
        evidence: [Evidence],
        error: DetectionError?
    ) {
        self.faceCount = faceCount
        self.faceAnalyses = faceAnalyses
        self.facesDetected = facesDetected
        self.processingTimeMs = processingTimeMs
        self.artifacts = artifacts
        self.score = score
        self.confidence = confidence
        self.evidence = evidence
        self.error = error
    }
}

// MARK: - Face Analysis

/// Analysis result for a single detected face
struct FaceAnalysis: Sendable, Codable, Identifiable {
    let id: UUID

    /// Bounding box of the face in image coordinates
    let faceBounds: CGRect

    /// Detected artifacts for this face
    let artifacts: [FaceSwapArtifact]

    /// Score for this face (0 = authentic, 1 = likely swapped)
    let score: Double

    /// Individual analysis scores
    let boundaryELAScore: Double
    let noiseDiscontinuityScore: Double
    let lightingConsistencyScore: Double

    init(
        id: UUID = UUID(),
        faceBounds: CGRect,
        artifacts: [FaceSwapArtifact],
        score: Double,
        boundaryELAScore: Double = 0.5,
        noiseDiscontinuityScore: Double = 0.5,
        lightingConsistencyScore: Double = 0.5
    ) {
        self.id = id
        self.faceBounds = faceBounds
        self.artifacts = artifacts
        self.score = score.clamped(to: 0 ... 1)
        self.boundaryELAScore = boundaryELAScore
        self.noiseDiscontinuityScore = noiseDiscontinuityScore
        self.lightingConsistencyScore = lightingConsistencyScore
    }
}

// MARK: - Face Swap Artifact

/// A detected artifact indicating potential face-swap manipulation
struct FaceSwapArtifact: Sendable, Codable, Identifiable {
    let id: UUID
    let type: ArtifactType
    let description: String
    let location: CGRect
    let severity: Severity

    init(
        id: UUID = UUID(),
        type: ArtifactType,
        description: String,
        location: CGRect,
        severity: Severity
    ) {
        self.id = id
        self.type = type
        self.description = description
        self.location = location
        self.severity = severity
    }

    enum ArtifactType: String, Sendable, Codable {
        case boundaryInconsistency = "boundary_inconsistency"
        case noiseDiscontinuity = "noise_discontinuity"
        case lightingInconsistency = "lighting_inconsistency"
        case textureAnomaly = "texture_anomaly"
        case blendingArtifact = "blending_artifact"

        func toEvidenceType() -> EvidenceType {
            switch self {
            case .boundaryInconsistency: return .faceSwapBoundaryInconsistency
            case .noiseDiscontinuity: return .faceSwapNoiseDiscontinuity
            case .lightingInconsistency: return .faceSwapLightingInconsistency
            case .textureAnomaly: return .faceSwapTextureAnomaly
            case .blendingArtifact: return .faceSwapBlendingArtifact
            }
        }

        var displayName: String {
            switch self {
            case .boundaryInconsistency: return "Boundary Inconsistency"
            case .noiseDiscontinuity: return "Noise Discontinuity"
            case .lightingInconsistency: return "Lighting Inconsistency"
            case .textureAnomaly: return "Texture Anomaly"
            case .blendingArtifact: return "Blending Artifact"
            }
        }
    }

    enum Severity: String, Sendable, Codable {
        case low
        case medium
        case high

        var displayName: String {
            rawValue.capitalized
        }
    }
}
