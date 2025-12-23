import CoreGraphics
import Foundation
import ImageIO
import OSLog

// MARK: - Logger

private let analysisLogger = Logger(subsystem: "com.aiq.app", category: "Analysis")

// MARK: - Async Semaphore

/// A simple async semaphore for limiting concurrent operations
private actor AsyncSemaphore {
    private var count: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(count: Int) {
        self.count = count
    }

    func wait() async {
        if count > 0 {
            count -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            count += 1
        }
    }
}

// MARK: - Analysis Orchestrator

/// Coordinates parallel analysis across all detectors
/// Implements: Req 2.1, 3.1, 12.1, 12.2, 12.3, 12.4
actor AnalysisOrchestrator {
    // MARK: Constants

    /// Maximum concurrent analyses
    static let maxConcurrentAnalyses = 4

    /// Memory threshold for throttling (2GB)
    static let memoryThresholdBytes: Int = 2_000_000_000

    /// Thumbnail size for results
    static let thumbnailSize = CGSize(width: 256, height: 256)

    // MARK: Dependencies

    private let mlDetector: MLDetector
    private let provenanceChecker: ProvenanceChecker
    private let metadataAnalyzer: MetadataAnalyzer
    private let forensicAnalyzer: ForensicAnalyzer
    private let faceSwapDetector: FaceSwapDetector
    private let resultAggregator: ResultAggregator

    // MARK: State

    private let analysisSemaphore = AsyncSemaphore(count: maxConcurrentAnalyses)

    // MARK: Initialization

    init(
        mlDetector: MLDetector = MLDetector(),
        provenanceChecker: ProvenanceChecker = ProvenanceChecker(),
        metadataAnalyzer: MetadataAnalyzer = MetadataAnalyzer(),
        forensicAnalyzer: ForensicAnalyzer = ForensicAnalyzer(),
        faceSwapDetector: FaceSwapDetector = FaceSwapDetector(),
        resultAggregator: ResultAggregator = ResultAggregator()
    ) {
        self.mlDetector = mlDetector
        self.provenanceChecker = provenanceChecker
        self.metadataAnalyzer = metadataAnalyzer
        self.forensicAnalyzer = forensicAnalyzer
        self.faceSwapDetector = faceSwapDetector
        self.resultAggregator = resultAggregator
    }

    // MARK: Preloading

    /// Preload ML model for faster first analysis
    /// Implements: Req 11.2
    func preloadModels() async {
        do {
            try await mlDetector.preloadModel()
        } catch {
            // Log error but don't fail - model will be loaded on first use
            analysisLogger.warning("Failed to preload ML model: \(error.localizedDescription)")
        }
    }

    // MARK: Single Image Analysis

    /// Analyze a single image through all detectors
    /// Implements: Req 12.1, 12.4
    func analyze(_ source: ImageSource, options: AnalysisOptions) async -> AggregatedResult {
        let startTime = Date()

        // Wait for semaphore (respects max concurrent analyses)
        await analysisSemaphore.wait()

        // Also check memory constraint with brief delay if needed
        if isMemoryConstrained() {
            // Brief pause to allow memory cleanup
            try? await Task.sleep(for: .milliseconds(500))
        }

        defer {
            Task { await analysisSemaphore.signal() }
        }

        // Load image data
        let (image, fileURL, imageData, imageSize, fileSizeBytes) = await loadImage(from: source)

        guard let cgImage = image else {
            return createFailedResult(source: source, error: "Failed to load image", startTime: startTime)
        }

        // Determine if image is lossless format
        let isLossless = isLosslessFormat(source: source)

        // Run all detectors in parallel
        async let mlResult = options.runMLDetection
            ? await mlDetector.detect(image: cgImage)
            : nil as MLDetectionResult?

        async let provenanceResult: ProvenanceResult? = {
            guard options.runProvenanceCheck, let url = fileURL else { return nil }
            return await provenanceChecker.checkProvenance(fileURL: url)
        }()

        async let metadataResult = options.runMetadataAnalysis
            ? await analyzeMetadata(fileURL: fileURL, imageData: imageData)
            : nil as MetadataResult?

        async let forensicResult = options.runForensicAnalysis
            ? await forensicAnalyzer.analyze(image: cgImage, isLossless: isLossless)
            : nil as ForensicResult?

        async let faceSwapResult = options.runFaceSwapDetection
            ? await faceSwapDetector.analyze(image: cgImage)
            : nil as FaceSwapResult?

        // Collect results
        let ml = await mlResult
        let provenance = await provenanceResult
        let metadata = await metadataResult
        let forensic = await forensicResult
        let faceSwap = await faceSwapResult

        // Generate thumbnail
        let thumbnail = generateThumbnail(from: cgImage)

        // Calculate analysis time
        let analysisTimeMs = Int(Date().timeIntervalSince(startTime) * 1000)

        // Aggregate results
        return resultAggregator.aggregate(
            imageSource: source,
            thumbnail: thumbnail,
            imageSize: imageSize,
            fileSizeBytes: fileSizeBytes,
            ml: ml,
            provenance: provenance,
            metadata: metadata,
            forensic: forensic,
            faceSwap: faceSwap,
            analysisTimeMs: analysisTimeMs
        )
    }

    // MARK: Batch Analysis

    /// Analyze multiple images with concurrency control
    /// Implements: Req 12.2, 12.3
    func analyzeBatch(
        _ sources: [ImageSource],
        options: AnalysisOptions
    ) -> AsyncStream<AggregatedResult> {
        AsyncStream { continuation in
            Task {
                // Semaphore in analyze() handles concurrency limiting
                await withTaskGroup(of: AggregatedResult.self) { group in
                    for source in sources {
                        group.addTask {
                            await self.analyze(source, options: options)
                        }
                    }

                    // Yield results as they complete
                    for await result in group {
                        continuation.yield(result)
                    }
                }
                continuation.finish()
            }
        }
    }

    // MARK: Image Loading

    /// Load image from source
    private func loadImage(from source: ImageSource) async -> (
        image: CGImage?,
        fileURL: URL?,
        imageData: Data?,
        imageSize: CGSize?,
        fileSizeBytes: Int?
    ) {
        switch source {
        case let .fileURL(url):
            return await loadImageFromFile(url: url)

        case let .imageData(data, _):
            return loadImageFromData(data: data)

        case .clipboard:
            return (nil, nil, nil, nil, nil) // Clipboard handling done at input layer
        }
    }

    /// Load image from file URL
    private func loadImageFromFile(url: URL) async -> (
        CGImage?, URL?, Data?, CGSize?, Int?
    ) {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else {
            return (nil, url, nil, nil, nil)
        }

        let size = CGSize(width: image.width, height: image.height)
        let fileSize = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int

        return (image, url, nil, size, fileSize)
    }

    /// Load image from data
    private func loadImageFromData(data: Data) -> (
        CGImage?, URL?, Data?, CGSize?, Int?
    ) {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else {
            return (nil, nil, data, nil, data.count)
        }

        let size = CGSize(width: image.width, height: image.height)
        return (image, nil, data, size, data.count)
    }

    // MARK: Metadata Analysis Helper

    /// Analyze metadata using appropriate method
    private func analyzeMetadata(fileURL: URL?, imageData: Data?) async -> MetadataResult {
        if let url = fileURL {
            return await metadataAnalyzer.analyze(fileURL: url)
        } else if let data = imageData {
            return await metadataAnalyzer.analyze(imageData: data)
        } else {
            return MetadataResult(error: .metadataExtractionFailed)
        }
    }

    // MARK: Helper Methods

    /// Generate thumbnail for display
    private func generateThumbnail(from image: CGImage) -> CGImage? {
        let width = Int(Self.thumbnailSize.width)
        let height = Int(Self.thumbnailSize.height)

        // Calculate aspect-fit dimensions
        let aspectRatio = Double(image.width) / Double(image.height)
        let targetWidth: Int
        let targetHeight: Int

        if aspectRatio > 1 {
            targetWidth = width
            targetHeight = Int(Double(width) / aspectRatio)
        } else {
            targetHeight = height
            targetWidth = Int(Double(height) * aspectRatio)
        }

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

    /// Check if source is a lossless format
    private func isLosslessFormat(source: ImageSource) -> Bool {
        switch source {
        case let .fileURL(url):
            let ext = url.pathExtension.lowercased()
            return ["png", "tiff", "tif", "bmp"].contains(ext)

        case let .imageData(data, _):
            // Check PNG magic bytes
            if data.count >= 8 {
                let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
                let header = [UInt8](data.prefix(8))
                if header == pngMagic {
                    return true
                }
            }
            return false

        case .clipboard:
            return false // Assume lossy for clipboard
        }
    }

    /// Create a failed result
    private func createFailedResult(
        source: ImageSource,
        error: String,
        startTime: Date
    ) -> AggregatedResult {
        let breakdown = SignalBreakdown(
            mlContribution: .unavailable(weight: SignalBreakdown.weights.ml),
            provenanceContribution: .unavailable(weight: SignalBreakdown.weights.provenance),
            metadataContribution: .unavailable(weight: SignalBreakdown.weights.metadata),
            forensicContribution: .unavailable(weight: SignalBreakdown.weights.forensic),
            faceSwapContribution: .unavailable(weight: 0.0)
        )

        return AggregatedResult(
            imageSource: source,
            overallScore: 0.5,
            classification: .uncertain,
            isDefinitive: false,
            summary: "Analysis failed: \(error)",
            signalBreakdown: breakdown,
            totalAnalysisTimeMs: Int(Date().timeIntervalSince(startTime) * 1000)
        )
    }

    // MARK: Memory Management

    /// Check if memory usage is constrained
    /// Implements: Req 12.3
    private nonisolated func isMemoryConstrained() -> Bool {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return false }
        return info.resident_size > Self.memoryThresholdBytes
    }
}
