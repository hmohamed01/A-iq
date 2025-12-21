import CoreGraphics
import CoreML
import Foundation
import Vision

// MARK: - ML Detector

/// ML-based AI image detection using Core ML
/// Implements: Req 2.1, 2.2, 2.3, 2.4, 2.5, 11.2
actor MLDetector {
    // MARK: Constants

    /// Model bundle name
    private let modelName = "AIDetector"

    /// Current model version for tracking
    private let modelVersion = MLDetectionResult.defaultModelVersion

    // MARK: State

    private var model: VNCoreMLModel?
    private var isLoaded = false

    // MARK: Initialization

    init() {}

    // MARK: Model Loading

    /// Preload model for faster first inference
    /// Implements: Req 11.2
    func preloadModel() async throws {
        guard !isLoaded else { return }

        let config = MLModelConfiguration()
        config.computeUnits = .all // Use Neural Engine when available

        // Try to load the compiled model from bundle
        guard let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") else {
            throw DetectionError.modelNotLoaded
        }

        do {
            let coreMLModel = try await MLModel.load(contentsOf: modelURL, configuration: config)
            model = try VNCoreMLModel(for: coreMLModel)
            isLoaded = true
        } catch {
            throw DetectionError.modelInferenceFailed(error.localizedDescription)
        }
    }

    // MARK: Detection

    /// Perform classification on image
    /// Implements: Req 2.1, 2.2, 2.3, 2.5
    func detect(image: CGImage) async -> MLDetectionResult {
        let startTime = Date()

        // Ensure model is loaded
        if !isLoaded {
            do {
                try await preloadModel()
            } catch {
                return MLDetectionResult(error: mapToDetectionError(error))
            }
        }

        guard let visionModel = model else {
            return MLDetectionResult(error: .modelNotLoaded)
        }

        // Preprocess image if needed
        let processedImage = preprocessImage(image) ?? image

        // Run inference with timeout
        do {
            let result = try await withThrowingTaskGroup(of: MLDetectionResult.self) { group in
                group.addTask {
                    try await self.runInference(
                        on: processedImage,
                        using: visionModel,
                        startTime: startTime
                    )
                }

                group.addTask {
                    try await Task.sleep(for: .seconds(MLDetectionResult.maxInferenceTimeSeconds))
                    throw DetectionError.inferenceTimeout
                }

                guard let result = try await group.next() else {
                    throw DetectionError.inferenceTimeout
                }

                group.cancelAll()
                return result
            }
            return result

        } catch is CancellationError {
            return MLDetectionResult(error: .inferenceTimeout)
        } catch let error as DetectionError {
            return MLDetectionResult(error: error)
        } catch {
            return MLDetectionResult(error: .modelInferenceFailed(error.localizedDescription))
        }
    }

    // MARK: Private Methods

    /// Map generic errors to DetectionError
    private func mapToDetectionError(_ error: Error) -> DetectionError {
        if let detectionError = error as? DetectionError {
            return detectionError
        }
        return .modelInferenceFailed(error.localizedDescription)
    }

    /// Run Vision inference request
    private func runInference(
        on image: CGImage,
        using visionModel: VNCoreMLModel,
        startTime: Date
    ) async throws -> MLDetectionResult {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNCoreMLRequest(model: visionModel) { request, error in
                let inferenceTime = Int(Date().timeIntervalSince(startTime) * 1000)

                if let error = error {
                    continuation.resume(throwing: DetectionError.modelInferenceFailed(error.localizedDescription))
                    return
                }

                // Handle different result types based on model output format
                if let classificationObs = request.results as? [VNClassificationObservation], !classificationObs.isEmpty {
                    // Model outputs classifier labels (v1.0 ViT model)
                    let result = self.parseObservations(classificationObs, inferenceTimeMs: inferenceTime)
                    continuation.resume(returning: result)
                } else if let featureObs = request.results as? [VNCoreMLFeatureValueObservation] {
                    // Model outputs raw tensor (v2.0 SigLIP model)
                    let result = self.parseFeatureObservations(featureObs, inferenceTimeMs: inferenceTime)
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: DetectionError.modelInferenceFailed("Unsupported model output format"))
                }
            }

            // Configure request for best accuracy
            request.imageCropAndScaleOption = .centerCrop

            // Create handler and perform request
            let handler = VNImageRequestHandler(cgImage: image, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: DetectionError.modelInferenceFailed(error.localizedDescription))
            }
        }
    }

    /// Parse VNCoreMLFeatureValueObservation results (raw tensor output) into MLDetectionResult
    /// Used for SigLIP model which outputs a MultiArray of probabilities
    private func parseFeatureObservations(
        _ observations: [VNCoreMLFeatureValueObservation],
        inferenceTimeMs: Int
    ) -> MLDetectionResult {
        // Find the "probs" output tensor
        guard let probsObs = observations.first(where: { $0.featureName == "probs" }),
              let multiArray = probsObs.featureValue.multiArrayValue else {
            return MLDetectionResult(error: .modelInferenceFailed("Could not find probs output"))
        }

        // SigLIP model outputs shape [1, 2] where index 0 = "ai", index 1 = "hum"
        // Extract probabilities from MultiArray
        let aiProb: Double
        let humProb: Double

        if multiArray.count >= 2 {
            // Access the probabilities - shape is [1, 2] so we need indices [0,0] and [0,1]
            aiProb = Double(truncating: multiArray[[0, 0] as [NSNumber]])
            humProb = Double(truncating: multiArray[[0, 1] as [NSNumber]])
        } else {
            return MLDetectionResult(error: .modelInferenceFailed("Invalid output shape"))
        }

        let rawProbabilities = ["ai": aiProb, "hum": humProb]

        // Determine classification based on AI probability
        let (classification, score) = determineClassification(
            aiScore: aiProb,
            humanScore: humProb
        )

        return MLDetectionResult(
            score: score,
            classification: classification,
            inferenceTimeMs: inferenceTimeMs,
            modelVersion: modelVersion,
            rawProbabilities: rawProbabilities
        )
    }

    /// Parse VNClassificationObservation results into MLDetectionResult
    private func parseObservations(
        _ observations: [VNClassificationObservation],
        inferenceTimeMs: Int
    ) -> MLDetectionResult {
        // Build raw probabilities map
        var rawProbabilities: [String: Double] = [:]
        for observation in observations {
            rawProbabilities[observation.identifier] = Double(observation.confidence)
        }

        // Model v2.0 (SigLIP) labels: "ai", "hum"
        // Model v1.0 (ViT) labels: "ai_generated", "authentic"
        // Support both by checking for "ai" prefix and "hum" or "authentic" for human/real
        let aiScore = observations.first { $0.identifier.lowercased().hasPrefix("ai") }?.confidence ?? 0
        let humanScore = observations.first {
            let id = $0.identifier.lowercased()
            return id == "hum" || id.contains("authentic") || id.contains("real") || id.contains("human")
        }?.confidence ?? 0

        // Determine classification based on scores
        let (classification, score) = determineClassification(
            aiScore: Double(aiScore),
            humanScore: Double(humanScore)
        )

        return MLDetectionResult(
            score: score,
            classification: classification,
            inferenceTimeMs: inferenceTimeMs,
            modelVersion: modelVersion,
            rawProbabilities: rawProbabilities
        )
    }

    /// Determine classification and score from model outputs
    private func determineClassification(
        aiScore: Double,
        humanScore: Double
    ) -> (ImageClassification, Double) {
        // Score represents probability of AI generation (0 = human/authentic, 1 = AI)
        // Use aiScore directly if available, otherwise invert humanScore
        let score: Double
        if aiScore > 0 || humanScore > 0 {
            // When both scores available, use aiScore (they should sum to ~1.0)
            score = aiScore
        } else {
            score = 0.5 // Fallback if no valid scores
        }

        let classification: ImageClassification
        if score > 0.7 {
            classification = .aiGenerated
        } else if score > 0.5 {
            classification = .aiEnhanced
        } else if score < 0.3 {
            classification = .authentic
        } else {
            classification = .uncertain
        }

        return (classification, score)
    }

    /// Resize image to model input dimensions
    /// Implements: Req 2.5
    private func preprocessImage(_ image: CGImage) -> CGImage? {
        let targetWidth = Int(MLDetectionResult.modelInputSize.width)
        let targetHeight = Int(MLDetectionResult.modelInputSize.height)

        // Skip if already correct size
        if image.width == targetWidth, image.height == targetHeight {
            return image
        }

        // Create context for resizing
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

        return context.makeImage()
    }
}
