import XCTest
@testable import A_IQ

final class ResultAggregatorTests: XCTestCase {
    var aggregator: ResultAggregator!

    override func setUp() {
        super.setUp()
        aggregator = ResultAggregator()
    }

    override func tearDown() {
        aggregator = nil
        super.tearDown()
    }

    // MARK: - Classification Tests

    func testClassificationLikelyAuthentic() {
        // Score < 30% should be classified as likely authentic
        let result = aggregator.aggregate(
            imageSource: .clipboard(Data()),
            thumbnail: nil,
            imageSize: nil,
            fileSizeBytes: nil,
            ml: createMLResult(score: 0.2),
            provenance: nil,
            metadata: nil,
            forensic: nil,
            analysisTimeMs: 100
        )

        XCTAssertEqual(result.classification, .likelyAuthentic)
        XCTAssertLessThan(result.overallScore, 0.3)
    }

    func testClassificationUncertain() {
        // Score 30-70% should be classified as uncertain
        let result = aggregator.aggregate(
            imageSource: .clipboard(Data()),
            thumbnail: nil,
            imageSize: nil,
            fileSizeBytes: nil,
            ml: createMLResult(score: 0.5),
            provenance: nil,
            metadata: nil,
            forensic: nil,
            analysisTimeMs: 100
        )

        XCTAssertEqual(result.classification, .uncertain)
        XCTAssertGreaterThanOrEqual(result.overallScore, 0.3)
        XCTAssertLessThanOrEqual(result.overallScore, 0.7)
    }

    func testClassificationLikelyAIGenerated() {
        // Score > 70% should be classified as likely AI-generated
        let result = aggregator.aggregate(
            imageSource: .clipboard(Data()),
            thumbnail: nil,
            imageSize: nil,
            fileSizeBytes: nil,
            ml: createMLResult(score: 0.85),
            provenance: nil,
            metadata: nil,
            forensic: nil,
            analysisTimeMs: 100
        )

        XCTAssertEqual(result.classification, .likelyAIGenerated)
        XCTAssertGreaterThan(result.overallScore, 0.7)
    }

    func testClassificationConfirmedAIGenerated() {
        // C2PA with AI tool should override to confirmed
        let provenanceResult = ProvenanceResult(
            credentialStatus: .valid,
            signerInfo: SignerInfo(name: "Adobe", isTrusted: true),
            creationTool: "DALL-E 3",
            provenanceChain: []
        )

        let result = aggregator.aggregate(
            imageSource: .clipboard(Data()),
            thumbnail: nil,
            imageSize: nil,
            fileSizeBytes: nil,
            ml: createMLResult(score: 0.5),
            provenance: provenanceResult,
            metadata: nil,
            forensic: nil,
            analysisTimeMs: 100
        )

        XCTAssertEqual(result.classification, .confirmedAIGenerated)
        XCTAssertTrue(result.isDefinitive)
    }

    // MARK: - Weighted Score Tests

    func testWeightedScoreAllSignals() {
        let result = aggregator.aggregate(
            imageSource: .clipboard(Data()),
            thumbnail: nil,
            imageSize: nil,
            fileSizeBytes: nil,
            ml: createMLResult(score: 0.8),      // 40% weight, score = 0.8
            provenance: createProvenanceResult(), // 30% weight, score = 0.5 (notPresent)
            metadata: createMetadataResult(),     // 15% weight, score = 0.2 (has camera info)
            forensic: createForensicResult(score: 0.5),      // 15% weight, score = 0.5
            analysisTimeMs: 100
        )

        // Expected: (0.8 * 0.4) + (0.5 * 0.3) + (0.2 * 0.15) + (0.5 * 0.15)
        // = 0.32 + 0.15 + 0.03 + 0.075 = 0.575
        XCTAssertEqual(result.overallScore, 0.575, accuracy: 0.01)
    }

    func testWeightedScorePartialSignals() {
        // Only ML available - should normalize by available weight
        let result = aggregator.aggregate(
            imageSource: .clipboard(Data()),
            thumbnail: nil,
            imageSize: nil,
            fileSizeBytes: nil,
            ml: createMLResult(score: 0.8),
            provenance: nil,
            metadata: nil,
            forensic: nil,
            analysisTimeMs: 100
        )

        // Only ML available (40% weight), so normalized score should be 0.8
        XCTAssertEqual(result.overallScore, 0.8, accuracy: 0.01)
    }

    func testWeightedScoreNoSignals() {
        // No signals available - should return neutral score
        let result = aggregator.aggregate(
            imageSource: .clipboard(Data()),
            thumbnail: nil,
            imageSize: nil,
            fileSizeBytes: nil,
            ml: nil,
            provenance: nil,
            metadata: nil,
            forensic: nil,
            analysisTimeMs: 100
        )

        XCTAssertEqual(result.overallScore, 0.5, accuracy: 0.01)
        XCTAssertEqual(result.classification, .uncertain)
    }

    // MARK: - Sensitivity Adjustment Tests

    func testSensitivityAdjustmentPositive() {
        let aggregatorWithSensitivity = ResultAggregator(sensitivityAdjustment: 0.1)

        let result = aggregatorWithSensitivity.aggregate(
            imageSource: .clipboard(Data()),
            thumbnail: nil,
            imageSize: nil,
            fileSizeBytes: nil,
            ml: createMLResult(score: 0.65),
            provenance: nil,
            metadata: nil,
            forensic: nil,
            analysisTimeMs: 100
        )

        // Base score 0.65 + 0.1 adjustment = 0.75
        XCTAssertEqual(result.overallScore, 0.75, accuracy: 0.01)
        XCTAssertEqual(result.classification, .likelyAIGenerated)
    }

    func testSensitivityAdjustmentNegative() {
        let aggregatorWithSensitivity = ResultAggregator(sensitivityAdjustment: -0.1)

        let result = aggregatorWithSensitivity.aggregate(
            imageSource: .clipboard(Data()),
            thumbnail: nil,
            imageSize: nil,
            fileSizeBytes: nil,
            ml: createMLResult(score: 0.35),
            provenance: nil,
            metadata: nil,
            forensic: nil,
            analysisTimeMs: 100
        )

        // Base score 0.35 - 0.1 adjustment = 0.25
        XCTAssertEqual(result.overallScore, 0.25, accuracy: 0.01)
        XCTAssertEqual(result.classification, .likelyAuthentic)
    }

    func testSensitivityAdjustmentClamped() {
        // Adjustment should be clamped to -0.1 to 0.1
        let aggregatorWithExcessiveSensitivity = ResultAggregator(sensitivityAdjustment: 0.5)

        let result = aggregatorWithExcessiveSensitivity.aggregate(
            imageSource: .clipboard(Data()),
            thumbnail: nil,
            imageSize: nil,
            fileSizeBytes: nil,
            ml: createMLResult(score: 0.5),
            provenance: nil,
            metadata: nil,
            forensic: nil,
            analysisTimeMs: 100
        )

        // Should clamp to 0.1, so 0.5 + 0.1 = 0.6
        XCTAssertEqual(result.overallScore, 0.6, accuracy: 0.01)
    }

    // MARK: - Signal Breakdown Tests

    func testSignalBreakdownContributions() {
        let result = aggregator.aggregate(
            imageSource: .clipboard(Data()),
            thumbnail: nil,
            imageSize: nil,
            fileSizeBytes: nil,
            ml: createMLResult(score: 0.8),
            provenance: createProvenanceResult(), // score = 0.5 (notPresent)
            metadata: nil,
            forensic: createForensicResult(score: 0.5),
            analysisTimeMs: 100
        )

        let breakdown = result.signalBreakdown

        XCTAssertTrue(breakdown.mlContribution.isAvailable)
        XCTAssertEqual(breakdown.mlContribution.rawScore, 0.8, accuracy: 0.01)

        XCTAssertTrue(breakdown.provenanceContribution.isAvailable)
        XCTAssertEqual(breakdown.provenanceContribution.rawScore, 0.5, accuracy: 0.01) // notPresent = 0.5

        XCTAssertFalse(breakdown.metadataContribution.isAvailable)

        XCTAssertTrue(breakdown.forensicContribution.isAvailable)
        XCTAssertEqual(breakdown.forensicContribution.rawScore, 0.5, accuracy: 0.01)
    }

    // MARK: - Helper Methods

    private func createMLResult(score: Double) -> MLDetectionResult {
        MLDetectionResult(
            score: score,
            classification: score > 0.5 ? .aiGenerated : .authentic,
            inferenceTimeMs: 50,
            modelVersion: "1.0.0"
        )
    }

    private func createProvenanceResult() -> ProvenanceResult {
        // Creates a result with credentialStatus: .notPresent, which gives score = 0.5
        ProvenanceResult(
            credentialStatus: .notPresent,
            signerInfo: nil,
            creationTool: nil,
            provenanceChain: []
        )
    }

    private func createMetadataResult() -> MetadataResult {
        // Creates a result with camera info, which gives score = 0.2 (suggests authentic)
        MetadataResult(
            hasExifData: true,
            cameraInfo: CameraInfo(make: "Canon", model: "EOS R5"),
            isJPEG: true
        )
    }

    private func createForensicResult(score: Double) -> ForensicResult {
        ForensicResult(
            elaImage: nil,
            suspiciousRegions: [],
            analysisMethod: .errorLevelAnalysis,
            processingTimeMs: 100,
            manipulationProbability: score
        )
    }
}
