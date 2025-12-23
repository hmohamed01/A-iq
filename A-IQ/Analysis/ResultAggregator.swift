import CoreGraphics
import Foundation

// MARK: - Result Aggregator

/// Aggregates multiple detection signals into final assessment
/// Implements: Req 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7, 10.2
struct ResultAggregator {
    // MARK: Configuration

    let sensitivityAdjustment: Double

    // MARK: Initialization

    init(sensitivityAdjustment: Double = 0.0) {
        self.sensitivityAdjustment = sensitivityAdjustment.clamped(to: -0.1 ... 0.1)
    }

    // MARK: Aggregation

    /// Aggregate all detection results into final assessment
    /// Implements: Req 6.1, 6.7
    func aggregate(
        imageSource: ImageSource,
        thumbnail: CGImage?,
        imageSize: CGSize?,
        fileSizeBytes: Int?,
        ml: MLDetectionResult?,
        provenance: ProvenanceResult?,
        metadata: MetadataResult?,
        forensic: ForensicResult?,
        faceSwap: FaceSwapResult?,
        analysisTimeMs: Int
    ) -> AggregatedResult {
        // Determine if faces were detected for dynamic weight selection
        let facesDetected = faceSwap?.facesDetected ?? false

        // Check for definitive proof first (C2PA override)
        // Implements: Req 6.3
        let isDefinitive = checkForDefinitiveProof(provenance)

        // Compute weighted score with dynamic weights based on face detection
        // Implements: Req 6.2
        let (score, breakdown) = computeWeightedScore(
            ml: ml,
            provenance: provenance,
            metadata: metadata,
            forensic: forensic,
            faceSwap: faceSwap,
            facesDetected: facesDetected
        )

        // Check for corroborating signals before amplification
        let hasCorroboration = checkForCorroboration(
            mlScore: ml?.score,
            provenance: provenance,
            metadata: metadata,
            forensic: forensic,
            faceSwap: faceSwap
        )

        // Check for contradicting signals (active disagreement, not just neutral)
        let hasContradiction = checkForContradiction(
            mlScore: ml?.score,
            provenance: provenance,
            metadata: metadata,
            forensic: forensic,
            faceSwap: faceSwap
        )

        // Apply high-confidence ML amplification
        // Now distinguishes between "no support" (neutral) and "active contradiction"
        let amplifiedScore = applyMLConfidenceAmplification(
            baseScore: score,
            mlScore: ml?.score,
            mlConfidence: ml?.confidence,
            hasCorroboration: hasCorroboration,
            hasContradiction: hasContradiction
        )

        // Apply sensitivity adjustment
        let adjustedScore = (amplifiedScore + sensitivityAdjustment).clamped(to: 0 ... 1)

        // Determine classification
        // Implements: Req 6.4, 6.5, 6.6
        let classification = OverallClassification.from(score: adjustedScore, isDefinitive: isDefinitive)

        // Generate summary
        let summary = generateSummary(classification: classification, breakdown: breakdown)

        return AggregatedResult(
            imageSource: imageSource,
            imageThumbnail: thumbnail,
            imageSize: imageSize,
            fileSizeBytes: fileSizeBytes,
            overallScore: adjustedScore,
            classification: classification,
            isDefinitive: isDefinitive,
            summary: summary,
            mlResult: ml,
            provenanceResult: provenance,
            metadataResult: metadata,
            forensicResult: forensic,
            faceSwapResult: faceSwap,
            signalBreakdown: breakdown,
            totalAnalysisTimeMs: analysisTimeMs
        )
    }

    // MARK: Definitive Proof Check

    /// Check for C2PA or other definitive proof of AI generation
    /// Implements: Req 6.3
    private func checkForDefinitiveProof(_ provenance: ProvenanceResult?) -> Bool {
        guard let provenance = provenance else { return false }
        return provenance.isDefinitivelyAI
    }

    // MARK: Weighted Score Computation

    /// Compute weighted score from all signals with intelligent redistribution
    /// Implements: Req 6.2
    private func computeWeightedScore(
        ml: MLDetectionResult?,
        provenance: ProvenanceResult?,
        metadata: MetadataResult?,
        forensic: ForensicResult?,
        faceSwap: FaceSwapResult?,
        facesDetected: Bool
    ) -> (score: Double, breakdown: SignalBreakdown) {
        // Use dynamic weights based on whether faces were detected
        let baseWeights = SignalBreakdown.weights(facesDetected: facesDetected)

        // Determine which detectors are "decisive" (have strong signal, not neutral)
        let mlDecisive = isDecisiveResult(score: ml?.score, confidence: ml?.confidence, isSuccessful: ml?.isSuccessful ?? false)
        let provDecisive = isDecisiveResult(score: provenance?.score, confidence: provenance?.confidence, isSuccessful: provenance?.isSuccessful ?? false)
        let metaDecisive = isDecisiveResult(score: metadata?.score, confidence: metadata?.confidence, isSuccessful: metadata?.isSuccessful ?? false)
        let forensicDecisive = isDecisiveResult(score: forensic?.score, confidence: forensic?.confidence, isSuccessful: forensic?.isSuccessful ?? false)
        let faceSwapDecisive = facesDetected && isDecisiveResult(score: faceSwap?.score, confidence: faceSwap?.confidence, isSuccessful: faceSwap?.isSuccessful ?? false)

        // Calculate effective weights with redistribution
        let effectiveWeights = calculateEffectiveWeights(
            baseWeights: baseWeights,
            mlDecisive: mlDecisive,
            provDecisive: provDecisive,
            metaDecisive: metaDecisive,
            forensicDecisive: forensicDecisive,
            faceSwapDecisive: faceSwapDecisive,
            facesDetected: facesDetected,
            mlConfidence: ml?.confidence
        )

        // Build contributions with effective weights
        let mlContrib = SignalContribution(
            rawScore: ml?.score ?? 0.5,
            weight: effectiveWeights.ml,
            isAvailable: ml?.isSuccessful ?? false,
            confidence: ml?.confidence ?? .unavailable
        )

        let provContrib = SignalContribution(
            rawScore: provenance?.score ?? 0.5,
            weight: effectiveWeights.provenance,
            isAvailable: provenance?.isSuccessful ?? false,
            confidence: provenance?.confidence ?? .unavailable
        )

        let metaContrib = SignalContribution(
            rawScore: metadata?.score ?? 0.5,
            weight: effectiveWeights.metadata,
            isAvailable: metadata?.isSuccessful ?? false,
            confidence: metadata?.confidence ?? .unavailable
        )

        // Apply forensic score adjustment for AI detection
        let adjustedForensicScore = adjustForensicScoreForAI(
            forensicScore: forensic?.score ?? 0.5,
            mlScore: ml?.score ?? 0.5,
            mlConfidence: ml?.confidence ?? .unavailable
        )

        let forensicContrib = SignalContribution(
            rawScore: adjustedForensicScore,
            weight: effectiveWeights.forensic,
            isAvailable: forensic?.isSuccessful ?? false,
            confidence: forensic?.confidence ?? .unavailable
        )

        // Face-swap contribution (only meaningful when faces detected)
        let faceSwapContrib = SignalContribution(
            rawScore: faceSwap?.score ?? 0.5,
            weight: effectiveWeights.faceSwap,
            isAvailable: facesDetected && (faceSwap?.isSuccessful ?? false),
            confidence: faceSwap?.confidence ?? .unavailable
        )

        let breakdown = SignalBreakdown(
            mlContribution: mlContrib,
            provenanceContribution: provContrib,
            metadataContribution: metaContrib,
            forensicContribution: forensicContrib,
            faceSwapContribution: faceSwapContrib
        )

        // Calculate weighted sum using effective weights
        var weightedSum = mlContrib.weightedScore +
            provContrib.weightedScore +
            metaContrib.weightedScore +
            forensicContrib.weightedScore

        // Include face-swap in weighted sum when faces detected
        if facesDetected {
            weightedSum += faceSwapContrib.weightedScore
        }

        // Normalize by total effective weight
        var totalEffectiveWeight = effectiveWeights.ml + effectiveWeights.provenance +
            effectiveWeights.metadata + effectiveWeights.forensic
        if facesDetected {
            totalEffectiveWeight += effectiveWeights.faceSwap
        }
        let normalizedScore = totalEffectiveWeight > 0 ? weightedSum / totalEffectiveWeight : 0.5

        return (normalizedScore, breakdown)
    }

    // MARK: Weight Redistribution Helpers

    /// Check if a detector result is decisive (not neutral/inconclusive)
    private func isDecisiveResult(score: Double?, confidence: ResultConfidence?, isSuccessful: Bool) -> Bool {
        guard isSuccessful, let score = score, let confidence = confidence else {
            return false
        }
        // A result is decisive if:
        // 1. Confidence is not low/unavailable AND
        // 2. Score is not neutral (significantly away from 0.5)
        let isConfident = confidence == .high || confidence == .medium
        let isNonNeutral = abs(score - 0.5) > 0.1 // More than 10% away from neutral
        return isConfident && isNonNeutral
    }

    /// Calculate effective weights with redistribution from inconclusive detectors
    private func calculateEffectiveWeights(
        baseWeights: SignalWeights,
        mlDecisive: Bool,
        provDecisive: Bool,
        metaDecisive: Bool,
        forensicDecisive: Bool,
        faceSwapDecisive: Bool,
        facesDetected: Bool,
        mlConfidence: ResultConfidence?
    ) -> SignalWeights {
        var mlWeight = baseWeights.ml
        var provWeight = baseWeights.provenance
        var metaWeight = baseWeights.metadata
        var forensicWeight = baseWeights.forensic
        var faceSwapWeight = baseWeights.faceSwap

        // Collect weight to redistribute from non-decisive detectors
        var weightToRedistribute = 0.0
        var decisiveCount = 0

        if !provDecisive {
            weightToRedistribute += provWeight
            provWeight = 0.05 // Keep minimal weight for display
        } else {
            decisiveCount += 1
        }

        if !metaDecisive {
            weightToRedistribute += metaWeight
            metaWeight = 0.05
        } else {
            decisiveCount += 1
        }

        if !forensicDecisive {
            weightToRedistribute += forensicWeight
            forensicWeight = 0.05
        } else {
            decisiveCount += 1
        }

        // Face-swap weight redistribution (only when faces detected)
        if facesDetected {
            if !faceSwapDecisive {
                weightToRedistribute += faceSwapWeight
                faceSwapWeight = 0.05
            } else {
                decisiveCount += 1
            }
        }

        // ML is always considered if successful
        if mlDecisive {
            decisiveCount += 1
        }

        // Redistribute weight to decisive detectors (primarily ML if it's decisive)
        if weightToRedistribute > 0 {
            if mlDecisive {
                // ML gets the lion's share of redistributed weight
                let mlBonus = weightToRedistribute * 0.7
                mlWeight += mlBonus

                // Remaining goes to other decisive detectors
                let remainingBonus = weightToRedistribute * 0.3
                let otherDecisiveCount = max(decisiveCount - 1, 1)
                let perDetectorBonus = remainingBonus / Double(otherDecisiveCount)

                if provDecisive { provWeight += perDetectorBonus }
                if metaDecisive { metaWeight += perDetectorBonus }
                if forensicDecisive { forensicWeight += perDetectorBonus }
                if facesDetected && faceSwapDecisive { faceSwapWeight += perDetectorBonus }
            } else if decisiveCount > 0 {
                // Distribute evenly among decisive detectors
                let perDetectorBonus = weightToRedistribute / Double(decisiveCount)
                if provDecisive { provWeight += perDetectorBonus }
                if metaDecisive { metaWeight += perDetectorBonus }
                if forensicDecisive { forensicWeight += perDetectorBonus }
                if facesDetected && faceSwapDecisive { faceSwapWeight += perDetectorBonus }
            }
        }

        // ML dominance boost: when ML has very high confidence, boost its weight further
        if let confidence = mlConfidence, confidence == .high {
            let dominanceBoost = 0.1
            mlWeight += dominanceBoost
        }

        return SignalWeights(
            ml: mlWeight,
            provenance: provWeight,
            metadata: metaWeight,
            forensic: forensicWeight,
            faceSwap: faceSwapWeight
        )
    }

    /// Adjust forensic score for AI detection context
    /// Low forensic manipulation score (uniform compression) can indicate AI generation
    private func adjustForensicScoreForAI(
        forensicScore: Double,
        mlScore: Double,
        mlConfidence: ResultConfidence
    ) -> Double {
        // If ML strongly suggests AI (>80%) and forensics shows low manipulation (<0.3),
        // the uniform compression actually supports AI hypothesis
        if mlScore > 0.8 && mlConfidence == .high && forensicScore < 0.3 {
            // Flip the interpretation: uniform = likely AI-generated (fresh render)
            // Map 0.2 -> 0.6, 0.1 -> 0.7, 0.0 -> 0.8
            return 0.5 + (0.3 - forensicScore)
        }

        // For moderate ML scores, bring forensic closer to neutral
        if mlScore > 0.6 && forensicScore < 0.4 {
            // Partially neutralize the "authentic" signal
            return (forensicScore + 0.5) / 2
        }

        return forensicScore
    }

    /// Check if other signals corroborate the ML assessment
    /// Returns true if at least one other signal supports ML's direction
    private func checkForCorroboration(
        mlScore: Double?,
        provenance: ProvenanceResult?,
        metadata: MetadataResult?,
        forensic: ForensicResult?,
        faceSwap: FaceSwapResult?
    ) -> Bool {
        guard let mlScore = mlScore else { return false }

        let mlSaysAI = mlScore > 0.6
        let mlSaysAuthentic = mlScore < 0.4

        // Check if any other signal agrees with ML
        var corroboratingSignals = 0

        // Provenance corroboration
        if let prov = provenance, prov.isSuccessful {
            if mlSaysAI && prov.score > 0.6 { corroboratingSignals += 1 }
            if mlSaysAuthentic && prov.score < 0.4 { corroboratingSignals += 1 }
            // Valid C2PA from trusted source is strong corroboration for authentic
            if mlSaysAuthentic && prov.credentialStatus == .valid { corroboratingSignals += 2 }
        }

        // Metadata corroboration (AI tool signatures, camera data)
        if let meta = metadata, meta.isSuccessful {
            if mlSaysAI && meta.score > 0.6 { corroboratingSignals += 1 }
            if mlSaysAuthentic && meta.score < 0.4 { corroboratingSignals += 1 }
            // Detected AI tool in metadata is strong corroboration
            if mlSaysAI, let software = meta.softwareInfo, MetadataResult.isAISoftware(software) {
                corroboratingSignals += 2
            }
            // Camera EXIF data is strong corroboration for authentic
            if mlSaysAuthentic && meta.cameraInfo != nil { corroboratingSignals += 2 }
        }

        // Forensic corroboration
        if let forensic = forensic, forensic.isSuccessful {
            // For AI detection, low forensic score (uniform compression) can corroborate
            if mlSaysAI && forensic.score < 0.3 { corroboratingSignals += 1 }
            // For authentic, high forensic score (varied compression) corroborates
            if mlSaysAuthentic && forensic.score > 0.6 { corroboratingSignals += 1 }
        }

        // Face-swap corroboration (when faces detected)
        if let faceSwap = faceSwap, faceSwap.facesDetected, faceSwap.isSuccessful {
            // Face-swap artifacts corroborate AI detection
            if mlSaysAI && faceSwap.score > 0.6 { corroboratingSignals += 2 }
            // Clean face analysis corroborates authentic
            if mlSaysAuthentic && faceSwap.score < 0.4 { corroboratingSignals += 1 }
        }

        return corroboratingSignals > 0
    }

    /// Check if any signal actively contradicts the ML assessment
    /// A contradiction is when a signal strongly disagrees (not just neutral)
    private func checkForContradiction(
        mlScore: Double?,
        provenance: ProvenanceResult?,
        metadata: MetadataResult?,
        forensic: ForensicResult?,
        faceSwap: FaceSwapResult?
    ) -> Bool {
        guard let mlScore = mlScore else { return false }

        let mlSaysAI = mlScore > 0.7
        let mlSaysAuthentic = mlScore < 0.3

        // Check if any signal strongly disagrees with ML
        // Provenance contradiction
        if let prov = provenance, prov.isSuccessful {
            // ML says AI but provenance says authentic (valid non-AI credentials)
            if mlSaysAI && prov.score < 0.3 && prov.credentialStatus == .valid {
                return true
            }
            // ML says authentic but provenance confirms AI
            if mlSaysAuthentic && prov.isDefinitivelyAI {
                return true
            }
        }

        // Metadata contradiction
        if let meta = metadata, meta.isSuccessful {
            // ML says AI but metadata has strong camera evidence
            if mlSaysAI && meta.score < 0.25 && meta.cameraInfo != nil {
                return true
            }
            // ML says authentic but metadata found AI tool
            if mlSaysAuthentic && meta.score > 0.75 {
                if let software = meta.softwareInfo, MetadataResult.isAISoftware(software) {
                    return true
                }
            }
        }

        // Face-swap contradiction (when faces detected)
        if let faceSwap = faceSwap, faceSwap.facesDetected, faceSwap.isSuccessful {
            // ML says authentic but face-swap detected high manipulation
            if mlSaysAuthentic && faceSwap.score > 0.75 && faceSwap.confidence == .high {
                return true
            }
        }

        return false
    }

    /// Apply ML confidence amplification when ML is highly confident
    /// When ML score is very high with high confidence, pull final score strongly toward ML score
    /// Key insight: neutral signals (50%) should NOT penalize a confident ML score
    /// Only active contradictions should reduce confidence
    private func applyMLConfidenceAmplification(
        baseScore: Double,
        mlScore: Double?,
        mlConfidence: ResultConfidence?,
        hasCorroboration: Bool,
        hasContradiction: Bool
    ) -> Double {
        guard let mlScore = mlScore, let mlConfidence = mlConfidence else {
            return baseScore
        }

        // Only amplify when ML has high confidence
        guard mlConfidence == .high else {
            return baseScore
        }

        // If there's active contradiction, be very conservative
        if hasContradiction {
            // Significant blending toward base score
            let blendedScore = mlScore * 0.5 + baseScore * 0.5
            return blendedScore
        }

        // Determine amplification based on corroboration
        // Key change: without corroboration but also without contradiction,
        // we trust ML much more than before (neutral signals = no opinion)
        let amplificationFactor: Double
        if hasCorroboration {
            amplificationFactor = 1.0  // Full trust
        } else {
            amplificationFactor = 0.85  // High trust (was 0.5, now more generous)
        }

        // For extremely high ML scores (>=99%)
        // When ML is this confident and nothing contradicts, trust it fully
        if mlScore >= 0.99 {
            if hasCorroboration {
                return mlScore  // 100%
            } else {
                // Without corroboration but no contradiction: trust ML
                // Return the ML score directly - neutral signals shouldn't penalize
                return mlScore
            }
        }

        // For very high ML scores (>95%)
        if mlScore > 0.95 {
            if hasCorroboration {
                return mlScore
            } else {
                // Very slight blend, mostly trust ML
                let blendedScore = mlScore * 0.97 + baseScore * 0.03
                return blendedScore
            }
        }

        // For high ML scores (>90%)
        if mlScore > 0.90 {
            let mlWeight = 0.90 * amplificationFactor
            let amplifiedScore = mlScore * mlWeight + baseScore * (1.0 - mlWeight)
            return amplifiedScore
        }

        // For moderately high ML scores (>80%)
        if mlScore > 0.80 {
            let mlWeight = 0.85 * amplificationFactor
            let amplifiedScore = mlScore * mlWeight + baseScore * (1.0 - mlWeight)
            return amplifiedScore
        }

        // For moderately high ML scores (>70%)
        if mlScore > 0.70 {
            let mlWeight = 0.80 * amplificationFactor
            let amplifiedScore = mlScore * mlWeight + baseScore * (1.0 - mlWeight)
            return amplifiedScore
        }

        // === LOW SCORES (likely authentic) ===

        // For extremely low ML scores (<=1%)
        // When ML is this confident it's authentic and nothing contradicts, trust it
        if mlScore <= 0.01 {
            if hasCorroboration {
                return mlScore
            } else {
                // Without corroboration but no contradiction: trust ML
                return mlScore
            }
        }

        // For very low ML scores (<5%)
        if mlScore < 0.05 {
            if hasCorroboration {
                return mlScore
            } else {
                // Very slight blend, mostly trust ML
                let blendedScore = mlScore * 0.97 + baseScore * 0.03
                return blendedScore
            }
        }

        // For low ML scores (<10%)
        if mlScore < 0.10 {
            let mlWeight = 0.90 * amplificationFactor
            let amplifiedScore = mlScore * mlWeight + baseScore * (1.0 - mlWeight)
            return amplifiedScore
        }

        // For somewhat low ML scores (<20%)
        if mlScore < 0.20 {
            let mlWeight = 0.85 * amplificationFactor
            let amplifiedScore = mlScore * mlWeight + baseScore * (1.0 - mlWeight)
            return amplifiedScore
        }

        // For low-moderate ML scores (<30%)
        if mlScore < 0.30 {
            let mlWeight = 0.80 * amplificationFactor
            let amplifiedScore = mlScore * mlWeight + baseScore * (1.0 - mlWeight)
            return amplifiedScore
        }

        return baseScore
    }

    // MARK: Summary Generation

    private func generateSummary(classification: OverallClassification, breakdown: SignalBreakdown) -> String {
        switch classification {
        case .confirmedAIGenerated:
            return "Image confirmed as AI-generated via C2PA content credentials."

        case .likelyAIGenerated:
            let indicators = breakdown.allContributions
                .filter { $0.contribution.isAvailable && $0.contribution.rawScore > 0.5 }
                .map { $0.name }
            return "Analysis indicates high probability of AI generation. Signals: \(indicators.joined(separator: ", "))."

        case .uncertain:
            return "Analysis inconclusive. Manual review recommended."

        case .likelyAuthentic:
            let indicators = breakdown.allContributions
                .filter { $0.contribution.isAvailable && $0.contribution.rawScore < 0.5 }
                .map { $0.name }
            return "Analysis indicates authentic photograph. Supporting signals: \(indicators.joined(separator: ", "))."
        }
    }
}
