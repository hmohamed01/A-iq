import Accelerate
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Forensic Analyzer

/// Performs Error Level Analysis and other forensic techniques
/// Implements: Req 5.1, 5.2, 5.3, 5.4, 5.5
actor ForensicAnalyzer {
    // MARK: Properties

    private let ciContext: CIContext

    // MARK: Initialization

    init() {
        // Create CIContext with GPU rendering for performance
        ciContext = CIContext(options: [
            .useSoftwareRenderer: false,
            .highQualityDownsample: true,
        ])
    }

    // MARK: Analysis

    /// Analyze image for forensic artifacts
    /// Implements: Req 5.1
    func analyze(image: CGImage, isLossless: Bool) async -> ForensicResult {
        let startTime = Date()

        // Run with timeout
        do {
            let result = try await withThrowingTaskGroup(of: ForensicResult.self) { group in
                group.addTask {
                    await self.performAnalysis(image: image, isLossless: isLossless, startTime: startTime)
                }

                group.addTask {
                    try await Task.sleep(for: .seconds(ForensicResult.maxProcessingTimeSeconds))
                    throw DetectionError.forensicAnalysisFailed("Timeout")
                }

                guard let result = try await group.next() else {
                    throw DetectionError.forensicAnalysisFailed("No result")
                }

                group.cancelAll()
                return result
            }
            return result

        } catch {
            return ForensicResult(error: .forensicAnalysisFailed(error.localizedDescription))
        }
    }

    /// Perform the actual analysis (ELA/noise + FFT combined)
    private func performAnalysis(image: CGImage, isLossless: Bool, startTime: Date) async -> ForensicResult {
        // Run traditional analysis and FFT in parallel
        async let traditionalResult = isLossless ?
            computeNoiseAnalysis(image: image, startTime: startTime) :
            computeELA(image: image, startTime: startTime)
        async let fftResult = computeFFTAnalysis(image: image)

        let traditional = await traditionalResult
        let fft = await fftResult

        // FFT can only boost the score, never reduce it
        // This ensures the new FFT analysis doesn't make overall detection worse
        let combinedScore: Double
        if fft.score > traditional.manipulationProbability {
            // FFT detected more AI indicators - blend scores to boost
            combinedScore = traditional.manipulationProbability * 0.7 + fft.score * 0.3
        } else {
            // FFT didn't find strong AI indicators - trust traditional analysis
            combinedScore = traditional.manipulationProbability
        }

        // Merge evidence from both analyses (only include FFT evidence if it found something)
        var combinedEvidence = traditional.evidence
        if fft.score > 0.5 {
            combinedEvidence.append(contentsOf: fft.evidence)
        }

        let processingTime = Int(Date().timeIntervalSince(startTime) * 1000)

        return ForensicResult(
            elaImage: traditional.elaImage,
            fftImage: fft.fftImage,
            suspiciousRegions: traditional.suspiciousRegions,
            analysisMethod: .combined,
            processingTimeMs: processingTime,
            manipulationProbability: combinedScore
        )
    }

    // MARK: Error Level Analysis

    /// Compute Error Level Analysis for JPEG images
    /// Implements: Req 5.2
    private func computeELA(image: CGImage, startTime: Date) async -> ForensicResult {
        // Downscale if image is too large
        let workingImage = downscaleIfNeeded(image)

        // Step 1: Recompress image at known quality
        guard let recompressedData = recompressJPEG(workingImage, quality: ForensicResult.elaQuality),
              let recompressedSource = CGImageSourceCreateWithData(recompressedData as CFData, nil),
              let recompressedImage = CGImageSourceCreateImageAtIndex(recompressedSource, 0, nil)
        else {
            return ForensicResult(error: .forensicAnalysisFailed("Failed to recompress image"))
        }

        // Step 2: Compute absolute difference
        guard let differenceImage = computeAbsoluteDifference(original: workingImage, recompressed: recompressedImage) else {
            return ForensicResult(error: .forensicAnalysisFailed("Failed to compute difference"))
        }

        // Step 3: Amplify differences for visibility
        guard let elaImage = amplifyDifferences(differenceImage, scale: 15.0) else {
            return ForensicResult(error: .forensicAnalysisFailed("Failed to amplify differences"))
        }

        // Step 4: Find suspicious regions
        let (suspiciousRegions, manipulationProbability) = findSuspiciousRegions(
            elaImage: elaImage,
            originalSize: CGSize(width: image.width, height: image.height)
        )

        let processingTime = Int(Date().timeIntervalSince(startTime) * 1000)

        return ForensicResult(
            elaImage: elaImage,
            suspiciousRegions: suspiciousRegions,
            analysisMethod: .errorLevelAnalysis,
            processingTimeMs: processingTime,
            manipulationProbability: manipulationProbability
        )
    }

    // MARK: Noise Analysis

    /// Compute noise pattern analysis for lossless images
    /// Implements: Req 5.3
    private func computeNoiseAnalysis(image: CGImage, startTime: Date) async -> ForensicResult {
        let workingImage = downscaleIfNeeded(image)

        // Apply high-pass filter to extract noise
        guard let noiseImage = extractNoisePattern(workingImage) else {
            return ForensicResult(error: .forensicAnalysisFailed("Failed to extract noise pattern"))
        }

        // Analyze noise uniformity
        let (suspiciousRegions, manipulationProbability) = analyzeNoiseUniformity(
            noiseImage: noiseImage,
            originalSize: CGSize(width: image.width, height: image.height)
        )

        let processingTime = Int(Date().timeIntervalSince(startTime) * 1000)

        return ForensicResult(
            elaImage: noiseImage,
            suspiciousRegions: suspiciousRegions,
            analysisMethod: .noiseAnalysis,
            processingTimeMs: processingTime,
            manipulationProbability: manipulationProbability
        )
    }

    // MARK: Image Processing Helpers

    /// Downscale image if larger than max resolution
    private func downscaleIfNeeded(_ image: CGImage) -> CGImage {
        let maxWidth = Int(ForensicResult.maxResolution.width)
        let maxHeight = Int(ForensicResult.maxResolution.height)

        guard image.width > maxWidth || image.height > maxHeight else {
            return image
        }

        let scale = min(
            Double(maxWidth) / Double(image.width),
            Double(maxHeight) / Double(image.height)
        )

        let newWidth = Int(Double(image.width) * scale)
        let newHeight = Int(Double(image.height) * scale)

        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

        return context.makeImage() ?? image
    }

    /// Recompress image as JPEG at specified quality
    private func recompressJPEG(_ image: CGImage, quality: Int) -> Data? {
        let mutableData = NSMutableData()

        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: Double(quality) / 100.0,
        ]

        CGImageDestinationAddImage(destination, image, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return mutableData as Data
    }

    /// Compute absolute difference between two images
    private func computeAbsoluteDifference(original: CGImage, recompressed: CGImage) -> CGImage? {
        let width = original.width
        let height = original.height

        guard width == recompressed.width, height == recompressed.height else {
            return nil
        }

        // Create bitmap contexts to access pixel data
        guard let originalData = getPixelData(from: original),
              let recompressedData = getPixelData(from: recompressed)
        else {
            return nil
        }

        // Compute absolute difference for each pixel
        var differenceData = [UInt8](repeating: 0, count: width * height * 4)

        for i in stride(from: 0, to: originalData.count, by: 4) {
            // RGB channels
            for j in 0 ..< 3 {
                let diff = abs(Int(originalData[i + j]) - Int(recompressedData[i + j]))
                differenceData[i + j] = UInt8(min(diff, 255))
            }
            // Alpha channel
            differenceData[i + 3] = 255
        }

        // Create output image
        return createImage(from: differenceData, width: width, height: height)
    }

    /// Amplify differences for better visibility
    private func amplifyDifferences(_ image: CGImage, scale: Double) -> CGImage? {
        let ciImage = CIImage(cgImage: image)

        // Apply color matrix to amplify
        let amplifyFilter = CIFilter(name: "CIColorMatrix")
        amplifyFilter?.setValue(ciImage, forKey: kCIInputImageKey)
        amplifyFilter?.setValue(CIVector(x: scale, y: 0, z: 0, w: 0), forKey: "inputRVector")
        amplifyFilter?.setValue(CIVector(x: 0, y: scale, z: 0, w: 0), forKey: "inputGVector")
        amplifyFilter?.setValue(CIVector(x: 0, y: 0, z: scale, w: 0), forKey: "inputBVector")
        amplifyFilter?.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        amplifyFilter?.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBiasVector")

        guard let outputImage = amplifyFilter?.outputImage else {
            return nil
        }

        return ciContext.createCGImage(outputImage, from: outputImage.extent)
    }

    /// Extract noise pattern from image using high-pass filter
    private func extractNoisePattern(_ image: CGImage) -> CGImage? {
        let ciImage = CIImage(cgImage: image)

        // Apply Gaussian blur then subtract to get noise
        let blurFilter = CIFilter(name: "CIGaussianBlur")
        blurFilter?.setValue(ciImage, forKey: kCIInputImageKey)
        blurFilter?.setValue(3.0, forKey: kCIInputRadiusKey)

        guard let blurredImage = blurFilter?.outputImage else {
            return nil
        }

        // Subtract blurred from original to get high-frequency noise
        let subtractFilter = CIFilter(name: "CISubtractBlendMode")
        subtractFilter?.setValue(ciImage, forKey: kCIInputImageKey)
        subtractFilter?.setValue(blurredImage, forKey: kCIInputBackgroundImageKey)

        guard let noiseImage = subtractFilter?.outputImage else {
            return nil
        }

        // Amplify for visibility
        let amplifyFilter = CIFilter(name: "CIColorMatrix")
        amplifyFilter?.setValue(noiseImage, forKey: kCIInputImageKey)
        amplifyFilter?.setValue(CIVector(x: 10, y: 0, z: 0, w: 0), forKey: "inputRVector")
        amplifyFilter?.setValue(CIVector(x: 0, y: 10, z: 0, w: 0), forKey: "inputGVector")
        amplifyFilter?.setValue(CIVector(x: 0, y: 0, z: 10, w: 0), forKey: "inputBVector")
        amplifyFilter?.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        amplifyFilter?.setValue(CIVector(x: 0.5, y: 0.5, z: 0.5, w: 0), forKey: "inputBiasVector")

        guard let outputImage = amplifyFilter?.outputImage else {
            return nil
        }

        return ciContext.createCGImage(outputImage, from: ciImage.extent)
    }

    // MARK: Region Detection

    /// Find suspicious regions in ELA image
    private func findSuspiciousRegions(
        elaImage: CGImage,
        originalSize: CGSize
    ) -> ([SuspiciousRegion], Double) {
        guard let pixelData = getPixelData(from: elaImage) else {
            return ([], 0.5)
        }

        let width = elaImage.width
        let height = elaImage.height
        let totalArea = Double(width * height)

        // Calculate average brightness and find bright regions
        var totalBrightness: Double = 0
        var brightPixelCount = 0
        let brightnessThreshold: UInt8 = 100

        for i in stride(from: 0, to: pixelData.count, by: 4) {
            let r = pixelData[i]
            let g = pixelData[i + 1]
            let b = pixelData[i + 2]
            let brightness = (Int(r) + Int(g) + Int(b)) / 3

            totalBrightness += Double(brightness)

            if brightness > Int(brightnessThreshold) {
                brightPixelCount += 1
            }
        }

        let averageBrightness = totalBrightness / Double(width * height)
        let brightAreaPercentage = (Double(brightPixelCount) / totalArea) * 100

        // Segment bright regions using connected components (simplified)
        let regions = segmentBrightRegions(
            pixelData: pixelData,
            width: width,
            height: height,
            threshold: brightnessThreshold
        )

        // Convert to suspicious regions
        let suspiciousRegions = regions.map { region -> SuspiciousRegion in
            let areaPercentage = (Double(region.pixelCount) / totalArea) * 100
            let scaledBounds = CGRect(
                x: Double(region.minX) / Double(width) * originalSize.width,
                y: Double(region.minY) / Double(height) * originalSize.height,
                width: Double(region.maxX - region.minX) / Double(width) * originalSize.width,
                height: Double(region.maxY - region.minY) / Double(height) * originalSize.height
            )

            return SuspiciousRegion(
                bounds: scaledBounds,
                intensity: region.averageIntensity / 255.0,
                areaPercentage: areaPercentage
            )
        }

        // Calculate manipulation probability based on findings
        let manipulationProbability = calculateManipulationProbability(
            averageBrightness: averageBrightness,
            brightAreaPercentage: brightAreaPercentage,
            regionCount: regions.count
        )

        return (suspiciousRegions, manipulationProbability)
    }

    /// Analyze noise uniformity for manipulation detection
    private func analyzeNoiseUniformity(
        noiseImage: CGImage,
        originalSize: CGSize
    ) -> ([SuspiciousRegion], Double) {
        // For noise analysis, look for regions with different noise patterns
        guard let pixelData = getPixelData(from: noiseImage) else {
            return ([], 0.5)
        }

        let width = noiseImage.width
        let height = noiseImage.height

        // Divide image into blocks and analyze variance
        let blockSize = 32
        var blockVariances: [(x: Int, y: Int, variance: Double)] = []

        for blockY in stride(from: 0, to: height, by: blockSize) {
            for blockX in stride(from: 0, to: width, by: blockSize) {
                let variance = calculateBlockVariance(
                    pixelData: pixelData,
                    width: width,
                    height: height,
                    blockX: blockX,
                    blockY: blockY,
                    blockSize: blockSize
                )
                blockVariances.append((blockX, blockY, variance))
            }
        }

        // Find outlier blocks (significantly different variance)
        let variances = blockVariances.map { $0.variance }
        let meanVariance = variances.reduce(0, +) / Double(variances.count)
        let stdDev = sqrt(variances.map { pow($0 - meanVariance, 2) }.reduce(0, +) / Double(variances.count))

        let outlierBlocks = blockVariances.filter { abs($0.variance - meanVariance) > 2 * stdDev }

        // Convert outliers to suspicious regions
        let totalArea = Double(width * height)
        let suspiciousRegions = outlierBlocks.map { block -> SuspiciousRegion in
            let areaPercentage = (Double(blockSize * blockSize) / totalArea) * 100
            let scaledBounds = CGRect(
                x: Double(block.x) / Double(width) * originalSize.width,
                y: Double(block.y) / Double(height) * originalSize.height,
                width: Double(blockSize) / Double(width) * originalSize.width,
                height: Double(blockSize) / Double(height) * originalSize.height
            )

            return SuspiciousRegion(
                bounds: scaledBounds,
                intensity: min(abs(block.variance - meanVariance) / (stdDev * 3), 1.0),
                areaPercentage: areaPercentage
            )
        }

        // Manipulation probability based on number of outliers
        let outlierPercentage = Double(outlierBlocks.count) / Double(blockVariances.count)
        let manipulationProbability = min(outlierPercentage * 5, 1.0)

        return (suspiciousRegions, manipulationProbability)
    }

    // MARK: Helper Methods

    /// Get pixel data from CGImage using Data for better memory management
    private func getPixelData(from image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = height * bytesPerRow

        // Use Data for automatic memory management
        var data = Data(count: totalBytes)

        let success = data.withUnsafeMutableBytes { rawBufferPointer -> Bool in
            guard let baseAddress = rawBufferPointer.baseAddress else { return false }

            guard let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }

            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        guard success else { return nil }
        return [UInt8](data)
    }

    /// Create CGImage from pixel data
    private func createImage(from data: [UInt8], width: Int, height: Int) -> CGImage? {
        var mutableData = data

        guard let context = CGContext(
            data: &mutableData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        return context.makeImage()
    }

    /// Segment bright regions using simple flood fill
    private func segmentBrightRegions(
        pixelData: [UInt8],
        width: Int,
        height: Int,
        threshold: UInt8
    ) -> [BrightRegion] {
        var visited = [Bool](repeating: false, count: width * height)
        var regions: [BrightRegion] = []

        for y in 0 ..< height {
            for x in 0 ..< width {
                let index = y * width + x
                if visited[index] { continue }

                let pixelIndex = index * 4
                let r = pixelData[pixelIndex]
                let g = pixelData[pixelIndex + 1]
                let b = pixelData[pixelIndex + 2]
                let brightness = UInt8((Int(r) + Int(g) + Int(b)) / 3)

                if brightness > threshold {
                    // Found bright pixel, flood fill to find region
                    let region = floodFill(
                        pixelData: pixelData,
                        width: width,
                        height: height,
                        startX: x,
                        startY: y,
                        threshold: threshold,
                        visited: &visited
                    )

                    if region.pixelCount > 100 { // Minimum region size
                        regions.append(region)
                    }
                }

                visited[index] = true
            }
        }

        return regions
    }

    /// Flood fill to find connected bright region
    /// Uses ContiguousArray for better stack performance
    private func floodFill(
        pixelData: [UInt8],
        width: Int,
        height: Int,
        startX: Int,
        startY: Int,
        threshold: UInt8,
        visited: inout [Bool]
    ) -> BrightRegion {
        var region = BrightRegion()
        // Use ContiguousArray for better performance than Array
        var stack = ContiguousArray<(Int, Int)>()
        stack.reserveCapacity(1000) // Pre-allocate for common case
        stack.append((startX, startY))

        let thresholdInt = Int(threshold)

        while let (x, y) = stack.popLast() {
            // Bounds check
            guard x >= 0, x < width, y >= 0, y < height else { continue }

            let index = y * width + x
            guard !visited[index] else { continue }

            let pixelIndex = index * 4
            let brightness = (Int(pixelData[pixelIndex]) + Int(pixelData[pixelIndex + 1]) + Int(pixelData[pixelIndex + 2])) / 3

            guard brightness > thresholdInt else { continue }

            visited[index] = true
            region.addPixel(x: x, y: y, brightness: Double(brightness))

            // Check neighbors (4-connected)
            stack.append((x + 1, y))
            stack.append((x - 1, y))
            stack.append((x, y + 1))
            stack.append((x, y - 1))
        }

        return region
    }

    /// Calculate variance of a block
    private func calculateBlockVariance(
        pixelData: [UInt8],
        width: Int,
        height: Int,
        blockX: Int,
        blockY: Int,
        blockSize: Int
    ) -> Double {
        var values: [Double] = []

        for y in blockY ..< min(blockY + blockSize, height) {
            for x in blockX ..< min(blockX + blockSize, width) {
                let pixelIndex = (y * width + x) * 4
                // Convert to Int before adding to prevent UInt8 overflow (255+255+255 = 765 > 255)
                let brightness = Double(Int(pixelData[pixelIndex]) + Int(pixelData[pixelIndex + 1]) + Int(pixelData[pixelIndex + 2])) / 3.0
                values.append(brightness)
            }
        }

        guard !values.isEmpty else { return 0 }

        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count)

        return variance
    }

    /// Calculate manipulation probability from analysis results
    private func calculateManipulationProbability(
        averageBrightness: Double,
        brightAreaPercentage: Double,
        regionCount: Int
    ) -> Double {
        // Higher average brightness suggests more uniform image (less manipulation)
        // Isolated bright regions suggest localized edits

        var probability = 0.5

        // If average brightness is very low, likely a clean image
        if averageBrightness < 10 {
            probability = 0.2
        } else if averageBrightness > 50 {
            probability = 0.7
        }

        // Adjust for bright area percentage
        if brightAreaPercentage > 30 {
            // Large bright areas might be normal high-frequency content
            probability = min(probability + 0.1, 1.0)
        } else if brightAreaPercentage > 5 && brightAreaPercentage < 30 {
            // Medium bright areas are most suspicious
            probability = min(probability + 0.2, 1.0)
        }

        // Multiple isolated regions are suspicious
        if regionCount > 3 {
            probability = min(probability + 0.15, 1.0)
        }

        return probability
    }
}

// MARK: - FFT Analysis

extension ForensicAnalyzer {
    /// Result from FFT frequency domain analysis
    struct FFTAnalysisResult {
        let score: Double
        let evidence: [Evidence]
        let fftImage: CGImage?
    }

    /// Compute FFT-based frequency domain analysis
    /// Detects spectral artifacts common in AI-generated images
    private func computeFFTAnalysis(image: CGImage) -> FFTAnalysisResult {
        let width = image.width
        let height = image.height

        // 1. Determine FFT size (power of 2, max 256)
        let fftSize = findNearestPowerOf2(min(width, height))
        guard fftSize >= 64 else {
            return FFTAnalysisResult(score: 0.5, evidence: [], fftImage: nil)
        }

        // 2. Extract center square region FIRST (much faster than processing entire image)
        guard let centerRegion = extractCenterRegion(image: image, size: fftSize) else {
            return FFTAnalysisResult(score: 0.5, evidence: [], fftImage: nil)
        }

        // 3. Convert just the center region to grayscale and apply filter
        guard let preparedData = convertAndFilter(pixelData: centerRegion, size: fftSize) else {
            return FFTAnalysisResult(score: 0.5, evidence: [], fftImage: nil)
        }

        // 4. Compute 2D FFT using Accelerate
        guard let (magnitudeSpectrum, fftVisualization) = compute2DFFT(
            data: preparedData,
            size: fftSize
        ) else {
            return FFTAnalysisResult(score: 0.5, evidence: [], fftImage: nil)
        }

        // 5. Analyze radial power spectrum for AI artifacts
        let (score, evidence) = analyzeSpectrum(
            magnitude: magnitudeSpectrum,
            size: fftSize
        )

        return FFTAnalysisResult(
            score: score,
            evidence: evidence,
            fftImage: fftVisualization
        )
    }

    /// Extract center square region from image (fast crop using CGImage)
    private func extractCenterRegion(image: CGImage, size: Int) -> [UInt8]? {
        let width = image.width
        let height = image.height

        // Calculate crop rect for center square
        let startX = (width - size) / 2
        let startY = (height - size) / 2
        let cropRect = CGRect(x: startX, y: startY, width: size, height: size)

        // Use CGImage cropping (hardware accelerated)
        guard let croppedImage = image.cropping(to: cropRect) else {
            return nil
        }

        // Get pixel data from cropped image only
        return getPixelData(from: croppedImage)
    }

    /// Convert pixel data to grayscale and apply Laplacian filter in one pass
    private func convertAndFilter(pixelData: [UInt8], size: Int) -> [Float]? {
        // First convert to grayscale
        var grayscale = [Float](repeating: 0, count: size * size)

        for i in 0 ..< (size * size) {
            let pixelIndex = i * 4
            let r = Float(pixelData[pixelIndex])
            let g = Float(pixelData[pixelIndex + 1])
            let b = Float(pixelData[pixelIndex + 2])
            grayscale[i] = 0.299 * r + 0.587 * g + 0.114 * b
        }

        // Apply Laplacian filter
        var filtered = [Float](repeating: 0, count: size * size)

        for y in 1 ..< (size - 1) {
            for x in 1 ..< (size - 1) {
                let idx = y * size + x
                let center = grayscale[idx]
                let up = grayscale[(y - 1) * size + x]
                let down = grayscale[(y + 1) * size + x]
                let left = grayscale[y * size + (x - 1)]
                let right = grayscale[y * size + (x + 1)]
                filtered[idx] = 4 * center - up - down - left - right
            }
        }

        return filtered
    }

    /// Find nearest power of 2 that is <= value
    private func findNearestPowerOf2(_ value: Int) -> Int {
        var power = 1
        while power * 2 <= value {
            power *= 2
        }
        return min(power, 256) // Cap at 256 for performance (was 512)
    }

    /// Compute 2D FFT using Accelerate vDSP
    private func compute2DFFT(data: [Float], size: Int) -> ([Float], CGImage?)? {
        let log2n = vDSP_Length(log2(Float(size)))
        let halfSize = size / 2

        // Create FFT setup
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return nil
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        // Prepare split complex arrays for 2D FFT
        var realPart = data
        var imagPart = [Float](repeating: 0, count: size * size)

        // Row-wise FFT using proper pointer handling
        for row in 0 ..< size {
            var rowReal = [Float](repeating: 0, count: size)
            var rowImag = [Float](repeating: 0, count: size)

            // Extract row
            for col in 0 ..< size {
                rowReal[col] = realPart[row * size + col]
                rowImag[col] = imagPart[row * size + col]
            }

            // Perform 1D FFT on row with proper pointer lifetime
            rowReal.withUnsafeMutableBufferPointer { realPtr in
                rowImag.withUnsafeMutableBufferPointer { imagPtr in
                    var rowSplit = DSPSplitComplex(
                        realp: realPtr.baseAddress!,
                        imagp: imagPtr.baseAddress!
                    )
                    vDSP_fft_zip(fftSetup, &rowSplit, 1, log2n, FFTDirection(FFT_FORWARD))
                }
            }

            // Store back
            for col in 0 ..< size {
                realPart[row * size + col] = rowReal[col]
                imagPart[row * size + col] = rowImag[col]
            }
        }

        // Column-wise FFT
        for col in 0 ..< size {
            var colReal = [Float](repeating: 0, count: size)
            var colImag = [Float](repeating: 0, count: size)

            // Extract column
            for row in 0 ..< size {
                colReal[row] = realPart[row * size + col]
                colImag[row] = imagPart[row * size + col]
            }

            // Perform 1D FFT on column with proper pointer lifetime
            colReal.withUnsafeMutableBufferPointer { realPtr in
                colImag.withUnsafeMutableBufferPointer { imagPtr in
                    var colSplit = DSPSplitComplex(
                        realp: realPtr.baseAddress!,
                        imagp: imagPtr.baseAddress!
                    )
                    vDSP_fft_zip(fftSetup, &colSplit, 1, log2n, FFTDirection(FFT_FORWARD))
                }
            }

            // Store back
            for row in 0 ..< size {
                realPart[row * size + col] = colReal[row]
                imagPart[row * size + col] = colImag[row]
            }
        }

        // Compute magnitude spectrum: sqrt(real^2 + imag^2)
        var magnitude = [Float](repeating: 0, count: size * size)
        for i in 0 ..< (size * size) {
            magnitude[i] = sqrt(realPart[i] * realPart[i] + imagPart[i] * imagPart[i])
        }

        // Shift zero frequency to center (FFT shift)
        var shiftedMagnitude = [Float](repeating: 0, count: size * size)
        for y in 0 ..< size {
            for x in 0 ..< size {
                let srcX = (x + halfSize) % size
                let srcY = (y + halfSize) % size
                shiftedMagnitude[y * size + x] = magnitude[srcY * size + srcX]
            }
        }

        // Create visualization image (log scale for visibility)
        let visualization = createFFTVisualization(
            magnitude: shiftedMagnitude,
            size: size
        )

        return (shiftedMagnitude, visualization)
    }

    /// Create a visualization image of the FFT magnitude spectrum
    private func createFFTVisualization(magnitude: [Float], size: Int) -> CGImage? {
        // Find max for normalization (excluding DC component at center)
        let center = size / 2
        var maxVal: Float = 0

        for y in 0 ..< size {
            for x in 0 ..< size {
                // Skip center region (DC component)
                let dist = sqrt(Float((x - center) * (x - center) + (y - center) * (y - center)))
                if dist > 5 {
                    maxVal = max(maxVal, magnitude[y * size + x])
                }
            }
        }

        guard maxVal > 0 else { return nil }

        // Convert to log scale and normalize to 0-255
        var pixelData = [UInt8](repeating: 0, count: size * size * 4)

        // Helper to safely convert Float to UInt8 with clamping
        func toUInt8(_ value: Float) -> UInt8 {
            UInt8(min(255, max(0, value)))
        }

        for y in 0 ..< size {
            for x in 0 ..< size {
                let idx = y * size + x
                // Clamp logValue to 0-1 range to handle floating point edge cases
                let logValue = min(1.0, max(0.0, log(1 + magnitude[idx]) / log(1 + maxVal)))

                let pixelIdx = idx * 4
                // Use a heat map: dark blue -> cyan -> yellow -> white
                if logValue < 0.33 {
                    let t = logValue * 3
                    pixelData[pixelIdx] = 0
                    pixelData[pixelIdx + 1] = toUInt8(t * 100)
                    pixelData[pixelIdx + 2] = toUInt8(50 + t * 150)
                } else if logValue < 0.66 {
                    let t = (logValue - 0.33) * 3
                    pixelData[pixelIdx] = toUInt8(t * 255)
                    pixelData[pixelIdx + 1] = toUInt8(100 + t * 155)
                    pixelData[pixelIdx + 2] = toUInt8(200 - t * 100)
                } else {
                    let t = min(1.0, (logValue - 0.66) * 3) // Clamp t for the last segment
                    pixelData[pixelIdx] = 255
                    pixelData[pixelIdx + 1] = 255
                    pixelData[pixelIdx + 2] = toUInt8(100 + t * 155)
                }
                pixelData[pixelIdx + 3] = 255 // Alpha
            }
        }

        return createImage(from: pixelData, width: size, height: size)
    }

    /// Analyze the magnitude spectrum for AI-generated image signatures
    private func analyzeSpectrum(magnitude: [Float], size: Int) -> (Double, [Evidence]) {
        let center = size / 2
        var evidence: [Evidence] = []

        // 1. Compute radial power profile (azimuthal average)
        let maxRadius = center - 1
        var radialProfile = [Float](repeating: 0, count: maxRadius)
        var radialCounts = [Int](repeating: 0, count: maxRadius)

        for y in 0 ..< size {
            for x in 0 ..< size {
                let dx = x - center
                let dy = y - center
                let radius = Int(sqrt(Float(dx * dx + dy * dy)))

                if radius > 0 && radius < maxRadius {
                    radialProfile[radius] += magnitude[y * size + x]
                    radialCounts[radius] += 1
                }
            }
        }

        // Average the radial profile
        for r in 0 ..< maxRadius {
            if radialCounts[r] > 0 {
                radialProfile[r] /= Float(radialCounts[r])
            }
        }

        // 2. Fit power law (natural images follow 1/f^n decay)
        // Convert to log-log space and perform linear regression
        var logRadius = [Float]()
        var logPower = [Float]()

        for r in 5 ..< maxRadius where radialProfile[r] > 0 {
            logRadius.append(log(Float(r)))
            logPower.append(log(radialProfile[r]))
        }

        guard logRadius.count > 10 else {
            return (0.5, evidence)
        }

        // Linear regression to find slope (power law exponent)
        let n = Float(logRadius.count)
        let sumX = logRadius.reduce(0, +)
        let sumY = logPower.reduce(0, +)
        let sumXY = zip(logRadius, logPower).map { $0 * $1 }.reduce(0, +)
        let sumX2 = logRadius.map { $0 * $0 }.reduce(0, +)

        let slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX)
        let intercept = (sumY - slope * sumX) / n

        // Calculate R² (goodness of fit)
        let meanY = sumY / n
        var ssTot: Float = 0
        var ssRes: Float = 0

        for i in 0 ..< logRadius.count {
            let predicted = slope * logRadius[i] + intercept
            ssRes += (logPower[i] - predicted) * (logPower[i] - predicted)
            ssTot += (logPower[i] - meanY) * (logPower[i] - meanY)
        }

        let rSquared = 1 - (ssRes / max(ssTot, 0.0001))

        // 3. Detect spectral peaks (GAN upsampling artifacts)
        var peakCount = 0
        var peakFrequencies: [Int] = []

        // Look for local maxima that deviate significantly from the power law fit
        for r in 10 ..< (maxRadius - 5) {
            let predicted = exp(slope * log(Float(r)) + intercept)
            let actual = radialProfile[r]

            // Check if this is a local maximum
            if actual > radialProfile[r - 1] && actual > radialProfile[r + 1] {
                // Check if it significantly exceeds the predicted value
                if actual > predicted * 2.0 {
                    peakCount += 1
                    peakFrequencies.append(r)
                }
            }
        }

        // 4. Calculate AI probability score
        var score: Double = 0.5

        // Power law slope: natural images typically have slope around -2 to -3
        // AI images often have flatter slopes or irregular patterns
        let slopeScore: Double
        if slope > -1.5 {
            slopeScore = 0.8 // Very flat slope, suspicious
        } else if slope > -2.0 {
            slopeScore = 0.6
        } else if slope < -3.5 {
            slopeScore = 0.6 // Too steep, unusual
        } else {
            slopeScore = 0.3 // Normal range
        }

        // R² score: poor fit to power law suggests AI generation
        let fitScore: Double
        if rSquared < 0.7 {
            fitScore = 0.8 // Poor fit, suspicious
        } else if rSquared < 0.85 {
            fitScore = 0.5
        } else {
            fitScore = 0.2 // Good fit, likely natural
        }

        // Peak score: spectral peaks indicate GAN artifacts
        let peakScore: Double
        if peakCount >= 3 {
            peakScore = 0.9 // Multiple peaks, very suspicious
        } else if peakCount >= 1 {
            peakScore = 0.6
        } else {
            peakScore = 0.3
        }

        // Combine scores
        score = slopeScore * 0.3 + fitScore * 0.4 + peakScore * 0.3

        // Build evidence
        if peakCount > 0 {
            evidence.append(Evidence(
                type: .forensicSpectralSignature,
                description: "Detected \(peakCount) spectral peak(s) at frequencies: \(peakFrequencies.prefix(3).map { String($0) }.joined(separator: ", "))",
                details: [
                    "peak_count": String(peakCount),
                    "peak_frequencies": peakFrequencies.prefix(5).map { String($0) }.joined(separator: ","),
                ],
                isPositiveIndicator: true
            ))
        }

        if rSquared < 0.8 {
            evidence.append(Evidence(
                type: .forensicFrequencyAnomaly,
                description: "Frequency spectrum deviates from natural 1/f pattern (R²=\(String(format: "%.2f", rSquared)))",
                details: [
                    "power_law_slope": String(format: "%.2f", slope),
                    "r_squared": String(format: "%.3f", rSquared),
                ],
                isPositiveIndicator: true
            ))
        } else if score < 0.4 {
            evidence.append(Evidence(
                type: .forensicClean,
                description: "Frequency spectrum follows natural 1/f pattern",
                details: [
                    "power_law_slope": String(format: "%.2f", slope),
                    "r_squared": String(format: "%.3f", rSquared),
                ],
                isPositiveIndicator: false
            ))
        }

        return (score, evidence)
    }
}

// MARK: - Supporting Types

private struct BrightRegion {
    var minX = Int.max
    var maxX = Int.min
    var minY = Int.max
    var maxY = Int.min
    var pixelCount = 0
    var totalIntensity: Double = 0

    var averageIntensity: Double {
        pixelCount > 0 ? totalIntensity / Double(pixelCount) : 0
    }

    mutating func addPixel(x: Int, y: Int, brightness: Double) {
        minX = min(minX, x)
        maxX = max(maxX, x)
        minY = min(minY, y)
        maxY = max(maxY, y)
        pixelCount += 1
        totalIntensity += brightness
    }
}
