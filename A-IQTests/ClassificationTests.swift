import XCTest
@testable import A_IQ

final class ClassificationTests: XCTestCase {

    // MARK: - Overall Classification Tests

    func testClassificationFromScoreLikelyAuthentic() {
        let classification = OverallClassification.from(score: 0.15, isDefinitive: false)
        XCTAssertEqual(classification, .likelyAuthentic)
    }

    func testClassificationFromScoreUncertainLow() {
        let classification = OverallClassification.from(score: 0.35, isDefinitive: false)
        XCTAssertEqual(classification, .uncertain)
    }

    func testClassificationFromScoreUncertainMid() {
        let classification = OverallClassification.from(score: 0.50, isDefinitive: false)
        XCTAssertEqual(classification, .uncertain)
    }

    func testClassificationFromScoreUncertainHigh() {
        let classification = OverallClassification.from(score: 0.65, isDefinitive: false)
        XCTAssertEqual(classification, .uncertain)
    }

    func testClassificationFromScoreLikelyAIGenerated() {
        let classification = OverallClassification.from(score: 0.85, isDefinitive: false)
        XCTAssertEqual(classification, .likelyAIGenerated)
    }

    func testClassificationDefinitiveOverride() {
        // Even with low score, definitive should return confirmed
        let classification = OverallClassification.from(score: 0.20, isDefinitive: true)
        XCTAssertEqual(classification, .confirmedAIGenerated)
    }

    func testClassificationThresholdBoundaryLow() {
        // Exactly at 30% threshold
        let classification = OverallClassification.from(score: 0.30, isDefinitive: false)
        XCTAssertEqual(classification, .uncertain)
    }

    func testClassificationThresholdBoundaryHigh() {
        // Exactly at 70% threshold
        let classification = OverallClassification.from(score: 0.70, isDefinitive: false)
        XCTAssertEqual(classification, .uncertain)
    }

    func testClassificationJustAbove70() {
        let classification = OverallClassification.from(score: 0.71, isDefinitive: false)
        XCTAssertEqual(classification, .likelyAIGenerated)
    }

    func testClassificationJustBelow30() {
        let classification = OverallClassification.from(score: 0.29, isDefinitive: false)
        XCTAssertEqual(classification, .likelyAuthentic)
    }

    // MARK: - Classification Properties Tests

    func testClassificationDisplayNames() {
        XCTAssertEqual(OverallClassification.likelyAuthentic.displayName, "Likely Authentic")
        XCTAssertEqual(OverallClassification.uncertain.displayName, "Uncertain")
        XCTAssertEqual(OverallClassification.likelyAIGenerated.displayName, "Likely AI-Generated")
        XCTAssertEqual(OverallClassification.confirmedAIGenerated.displayName, "Confirmed AI-Generated")
    }

    func testClassificationShortNames() {
        XCTAssertEqual(OverallClassification.likelyAuthentic.shortName, "Authentic")
        XCTAssertEqual(OverallClassification.uncertain.shortName, "Uncertain")
        XCTAssertEqual(OverallClassification.likelyAIGenerated.shortName, "AI-Generated")
        XCTAssertEqual(OverallClassification.confirmedAIGenerated.shortName, "AI-Generated")
    }

    func testClassificationIsAIGenerated() {
        XCTAssertFalse(OverallClassification.likelyAuthentic.isAIGenerated)
        XCTAssertFalse(OverallClassification.uncertain.isAIGenerated)
        XCTAssertTrue(OverallClassification.likelyAIGenerated.isAIGenerated)
        XCTAssertTrue(OverallClassification.confirmedAIGenerated.isAIGenerated)
    }

    // MARK: - Signal Weights Tests

    func testSignalWeightsTotal() {
        let weights = SignalBreakdown.weights
        let total = weights.ml + weights.provenance + weights.metadata + weights.forensic
        XCTAssertEqual(total, 1.0, accuracy: 0.001)
    }

    func testSignalWeightsValues() {
        let weights = SignalBreakdown.weights
        XCTAssertEqual(weights.ml, 0.40, accuracy: 0.001)
        XCTAssertEqual(weights.provenance, 0.30, accuracy: 0.001)
        XCTAssertEqual(weights.metadata, 0.15, accuracy: 0.001)
        XCTAssertEqual(weights.forensic, 0.15, accuracy: 0.001)
    }

    // MARK: - Signal Contribution Tests

    func testSignalContributionAvailable() {
        let contribution = SignalContribution(
            rawScore: 0.75,
            weight: 0.40,
            isAvailable: true,
            confidence: .high
        )

        XCTAssertEqual(contribution.rawScore, 0.75, accuracy: 0.001)
        XCTAssertEqual(contribution.weightedScore, 0.30, accuracy: 0.001) // 0.75 * 0.40
        XCTAssertTrue(contribution.isAvailable)
        XCTAssertEqual(contribution.confidence, .high)
    }

    func testSignalContributionUnavailable() {
        let contribution = SignalContribution(
            rawScore: 0.75,
            weight: 0.40,
            isAvailable: false,
            confidence: .unavailable
        )

        XCTAssertEqual(contribution.rawScore, 0.75, accuracy: 0.001)
        XCTAssertEqual(contribution.weightedScore, 0.0, accuracy: 0.001) // Not available, so 0
        XCTAssertFalse(contribution.isAvailable)
        XCTAssertEqual(contribution.confidence, .unavailable)
    }

    func testSignalContributionUnavailableFactory() {
        let contribution = SignalContribution.unavailable(weight: 0.40)

        XCTAssertEqual(contribution.rawScore, 0.5, accuracy: 0.001)
        XCTAssertEqual(contribution.weightedScore, 0.0, accuracy: 0.001)
        XCTAssertFalse(contribution.isAvailable)
        XCTAssertEqual(contribution.confidence, .unavailable)
    }

    func testSignalContributionScoreClamping() {
        let contributionHigh = SignalContribution(
            rawScore: 1.5, // Above 1.0
            weight: 0.40,
            isAvailable: true,
            confidence: .high
        )
        XCTAssertEqual(contributionHigh.rawScore, 1.0, accuracy: 0.001)

        let contributionLow = SignalContribution(
            rawScore: -0.5, // Below 0.0
            weight: 0.40,
            isAvailable: true,
            confidence: .high
        )
        XCTAssertEqual(contributionLow.rawScore, 0.0, accuracy: 0.001)
    }

    // MARK: - Result Confidence Tests

    func testResultConfidenceWeights() {
        XCTAssertEqual(ResultConfidence.high.weight, 1.0, accuracy: 0.001)
        XCTAssertEqual(ResultConfidence.medium.weight, 0.7, accuracy: 0.001)
        XCTAssertEqual(ResultConfidence.low.weight, 0.4, accuracy: 0.001)
        XCTAssertEqual(ResultConfidence.unavailable.weight, 0.0, accuracy: 0.001)
    }

    func testResultConfidenceDisplayNames() {
        XCTAssertEqual(ResultConfidence.high.displayName, "High")
        XCTAssertEqual(ResultConfidence.medium.displayName, "Medium")
        XCTAssertEqual(ResultConfidence.low.displayName, "Low")
        XCTAssertEqual(ResultConfidence.unavailable.displayName, "Unavailable")
    }

    // MARK: - Image Classification Tests

    func testImageClassificationDisplayNames() {
        XCTAssertEqual(ImageClassification.authentic.displayName, "Authentic")
        XCTAssertEqual(ImageClassification.aiGenerated.displayName, "AI-Generated")
        XCTAssertEqual(ImageClassification.aiEnhanced.displayName, "AI-Enhanced")
        XCTAssertEqual(ImageClassification.uncertain.displayName, "Uncertain")
    }

    func testImageClassificationIsAIInvolved() {
        XCTAssertFalse(ImageClassification.authentic.isAIInvolved)
        XCTAssertTrue(ImageClassification.aiGenerated.isAIInvolved)
        XCTAssertTrue(ImageClassification.aiEnhanced.isAIInvolved)
        XCTAssertFalse(ImageClassification.uncertain.isAIInvolved)
    }
}
