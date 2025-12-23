import CoreGraphics
import CoreImage
import CoreML
import Foundation
import Vision

// MARK: - Face Swap Detector

/// Detects face-swap/deepfake artifacts in images containing faces
/// Uses a SigLIP-based deepfake detection model trained on FaceForensics++
actor FaceSwapDetector {
    // MARK: Constants

    /// Model bundle name
    private let modelName = "DeepfakeDetector"

    /// Input size expected by the model
    private let modelInputSize = 224

    // MARK: State

    private var model: VNCoreMLModel?
    private var isLoaded = false
    private let ciContext: CIContext

    // MARK: Initialization

    init() {
        ciContext = CIContext(options: [
            .useSoftwareRenderer: false,
            .highQualityDownsample: true,
        ])
    }

    // MARK: Model Loading

    /// Preload model for faster first inference
    func preloadModel() async throws {
        guard !isLoaded else { return }

        let config = MLModelConfiguration()
        config.computeUnits = .all // Use Neural Engine when available

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

    // MARK: Analysis Entry Point

    /// Analyze image for face-swap artifacts
    /// Returns early with neutral result if no faces detected
    func analyze(image: CGImage) async -> FaceSwapResult {
        let startTime = Date()

        // Ensure model is loaded
        if !isLoaded {
            do {
                try await preloadModel()
            } catch {
                let processingTime = Int(Date().timeIntervalSince(startTime) * 1000)
                return FaceSwapResult.noFaces(processingTimeMs: processingTime)
            }
        }

        // Run with timeout
        do {
            let result = try await withThrowingTaskGroup(of: FaceSwapResult.self) { group in
                group.addTask {
                    await self.performAnalysis(image: image, startTime: startTime)
                }

                group.addTask {
                    try await Task.sleep(for: .seconds(FaceSwapResult.maxProcessingTimeSeconds))
                    throw DetectionError.forensicAnalysisFailed("FaceSwap timeout")
                }

                guard let result = try await group.next() else {
                    throw DetectionError.forensicAnalysisFailed("No result")
                }

                group.cancelAll()
                return result
            }
            return result
        } catch {
            let processingTime = Int(Date().timeIntervalSince(startTime) * 1000)
            return FaceSwapResult.noFaces(processingTimeMs: processingTime)
        }
    }

    // MARK: Core Analysis

    private func performAnalysis(image: CGImage, startTime: Date) async -> FaceSwapResult {
        // Step 1: Detect faces using Vision
        let faces = await detectFaces(in: image)

        guard !faces.isEmpty else {
            let processingTime = Int(Date().timeIntervalSince(startTime) * 1000)
            return FaceSwapResult.noFaces(processingTimeMs: processingTime)
        }

        guard let visionModel = model else {
            let processingTime = Int(Date().timeIntervalSince(startTime) * 1000)
            return FaceSwapResult.noFaces(processingTimeMs: processingTime)
        }

        // Step 2: Analyze each face region with ML model
        var faceAnalyses: [FaceAnalysis] = []

        for faceObservation in faces {
            let analysis = await analyzeFaceWithML(
                image: image,
                face: faceObservation,
                model: visionModel
            )
            faceAnalyses.append(analysis)
        }

        // Step 3: Aggregate face analyses into final result
        let processingTime = Int(Date().timeIntervalSince(startTime) * 1000)
        return FaceSwapResult(
            faceAnalyses: faceAnalyses,
            processingTimeMs: processingTime
        )
    }

    // MARK: Face Detection

    private func detectFaces(in image: CGImage) async -> [VNFaceObservation] {
        await withCheckedContinuation { continuation in
            let request = VNDetectFaceRectanglesRequest { request, error in
                if error != nil {
                    continuation.resume(returning: [])
                    return
                }

                let faces = request.results as? [VNFaceObservation] ?? []

                // Filter out very small faces
                let minArea = FaceSwapResult.minFaceSizePercent * FaceSwapResult.minFaceSizePercent
                let validFaces = faces.filter { face in
                    let area = face.boundingBox.width * face.boundingBox.height
                    return area >= minArea
                }

                continuation.resume(returning: validFaces)
            }

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    // MARK: ML-Based Face Analysis

    private func analyzeFaceWithML(
        image: CGImage,
        face: VNFaceObservation,
        model: VNCoreMLModel
    ) async -> FaceAnalysis {
        // Convert normalized coordinates to pixel coordinates
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)

        let faceRect = CGRect(
            x: face.boundingBox.minX * imageWidth,
            y: (1 - face.boundingBox.maxY) * imageHeight, // Vision uses bottom-left origin
            width: face.boundingBox.width * imageWidth,
            height: face.boundingBox.height * imageHeight
        )

        // Expand face rect slightly to include context (20% padding)
        let padding = faceRect.width * 0.2
        let expandedRect = faceRect.insetBy(dx: -padding, dy: -padding)
            .intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))

        // Crop face region
        guard let faceImage = image.cropping(to: expandedRect) else {
            return FaceAnalysis(faceBounds: faceRect, artifacts: [], score: 0.5)
        }

        // Run ML inference on the face
        let (fakeProb, realProb) = await runDeepfakeInference(on: faceImage, using: model)

        // Score is the "fake" probability
        let score = fakeProb

        // Determine artifacts based on score
        var artifacts: [FaceSwapArtifact] = []

        if score > 0.7 {
            artifacts.append(FaceSwapArtifact(
                type: .blendingArtifact,
                description: "High deepfake probability detected (\(Int(score * 100))%)",
                location: faceRect,
                severity: .high
            ))
        } else if score > 0.5 {
            artifacts.append(FaceSwapArtifact(
                type: .textureAnomaly,
                description: "Moderate manipulation indicators (\(Int(score * 100))%)",
                location: faceRect,
                severity: .medium
            ))
        }

        return FaceAnalysis(
            faceBounds: faceRect,
            artifacts: artifacts,
            score: score,
            boundaryELAScore: score, // Use ML score for all sub-scores
            noiseDiscontinuityScore: score,
            lightingConsistencyScore: score
        )
    }

    // MARK: ML Inference

    private func runDeepfakeInference(
        on faceImage: CGImage,
        using visionModel: VNCoreMLModel
    ) async -> (fakeProb: Double, realProb: Double) {
        await withCheckedContinuation { continuation in
            let request = VNCoreMLRequest(model: visionModel) { request, error in
                if error != nil {
                    continuation.resume(returning: (0.5, 0.5))
                    return
                }

                // Handle feature observation output (SigLIP-style model)
                if let featureObs = request.results as? [VNCoreMLFeatureValueObservation] {
                    // Find the "probabilities" output tensor
                    if let probsObs = featureObs.first(where: { $0.featureName == "probabilities" }),
                       let multiArray = probsObs.featureValue.multiArrayValue,
                       multiArray.count >= 2
                    {
                        // Model outputs [Fake, Real] probabilities
                        let fakeProb = Double(truncating: multiArray[[0, 0] as [NSNumber]])
                        let realProb = Double(truncating: multiArray[[0, 1] as [NSNumber]])
                        continuation.resume(returning: (fakeProb, realProb))
                        return
                    }
                }

                // Handle classification observation output
                if let classObs = request.results as? [VNClassificationObservation] {
                    var fakeProb = 0.5
                    var realProb = 0.5

                    for obs in classObs {
                        let label = obs.identifier.lowercased()
                        if label.contains("fake") || label.contains("deepfake") {
                            fakeProb = Double(obs.confidence)
                        } else if label.contains("real") || label.contains("authentic") {
                            realProb = Double(obs.confidence)
                        }
                    }

                    continuation.resume(returning: (fakeProb, realProb))
                    return
                }

                // Default fallback
                continuation.resume(returning: (0.5, 0.5))
            }

            // Configure request
            request.imageCropAndScaleOption = .centerCrop

            // Create handler and perform request
            let handler = VNImageRequestHandler(cgImage: faceImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: (0.5, 0.5))
            }
        }
    }
}
