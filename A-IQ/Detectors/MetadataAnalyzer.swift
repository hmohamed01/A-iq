import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Metadata Analyzer

/// Extracts and analyzes EXIF/IPTC metadata from images
/// Implements: Req 4.1, 4.2, 4.3, 4.4, 4.5, 4.6
actor MetadataAnalyzer {
    // MARK: Initialization

    init() {}

    // MARK: Analysis Methods

    /// Analyze metadata from file URL
    /// Implements: Req 4.1
    func analyze(fileURL: URL) async -> MetadataResult {
        guard let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            return MetadataResult(error: .imageLoadFailed)
        }

        let isJPEG = isJPEGFile(url: fileURL)
        return analyzeImageSource(imageSource, isJPEG: isJPEG)
    }

    /// Analyze metadata from image data
    /// Implements: Req 4.1
    func analyze(imageData: Data) async -> MetadataResult {
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            return MetadataResult(error: .imageLoadFailed)
        }

        let isJPEG = isJPEGData(data: imageData)
        return analyzeImageSource(imageSource, isJPEG: isJPEG)
    }

    // MARK: Private Analysis

    /// Analyze an image source for metadata
    private func analyzeImageSource(_ source: CGImageSource, isJPEG: Bool) -> MetadataResult {
        // Get all metadata
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return MetadataResult(
                hasExifData: false,
                isJPEG: isJPEG
            )
        }

        // Extract specific metadata sections
        let exifDict = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let tiffDict = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        let gpsDict = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any]
        let iptcDict = properties[kCGImagePropertyIPTCDictionary as String] as? [String: Any]

        let hasExif = exifDict != nil || tiffDict != nil

        // Extract components
        let cameraInfo = extractCameraInfo(exif: exifDict, tiff: tiffDict)
        let softwareInfo = extractSoftwareInfo(tiff: tiffDict, iptc: iptcDict, exif: exifDict)
        let creationDate = extractCreationDate(exif: exifDict, tiff: tiffDict)
        let gpsLocation = extractGPSLocation(gps: gpsDict)
        let rawMetadata = flattenMetadata(properties)

        // Detect anomalies
        var anomalies: [MetadataAnomaly] = []

        // Check for missing EXIF in JPEG
        if isJPEG && !hasExif {
            anomalies.append(MetadataAnomaly(
                type: .missingExif,
                description: "No EXIF metadata found in JPEG file (may indicate synthetic image)"
            ))
        }

        // Check for AI software
        if let software = softwareInfo, MetadataResult.isAISoftware(software) {
            anomalies.append(MetadataAnomaly(
                type: .aiToolDetected,
                description: "Image software indicates AI tool: \(software)",
                details: ["software": software]
            ))
        }

        // Check for date anomalies
        if let date = creationDate {
            if date > Date() {
                anomalies.append(MetadataAnomaly(
                    type: .futureDateDetected,
                    description: "Creation date is in the future",
                    details: ["date": ISO8601DateFormatter().string(from: date)]
                ))
            }

            // Check for impossibly old dates (before digital cameras)
            let earliestValidDate = Calendar.current.date(from: DateComponents(year: 1990, month: 1, day: 1))!
            if date < earliestValidDate {
                anomalies.append(MetadataAnomaly(
                    type: .impossibleDate,
                    description: "Creation date predates digital photography",
                    details: ["date": ISO8601DateFormatter().string(from: date)]
                ))
            }
        }

        // Check for timestamp inconsistencies
        if let anomaly = checkTimestampConsistency(exif: exifDict, tiff: tiffDict) {
            anomalies.append(anomaly)
        }

        // Check for thumbnail mismatch (JPEG only)
        if isJPEG, let anomaly = checkThumbnailMismatch(source: source) {
            anomalies.append(anomaly)
        }

        // Check for color profile anomalies
        if let anomaly = checkColorProfile(properties: properties, cameraInfo: cameraInfo) {
            anomalies.append(anomaly)
        }

        // Check JPEG compression characteristics
        if let anomaly = checkJPEGCompression(properties: properties, isJPEG: isJPEG) {
            anomalies.append(anomaly)
        }

        // Deep inspection of XMP/IPTC for AI indicators
        if let anomaly = checkXMPAndIPTC(properties: properties) {
            anomalies.append(anomaly)
        }

        return MetadataResult(
            hasExifData: hasExif,
            cameraInfo: cameraInfo,
            softwareInfo: softwareInfo,
            creationDate: creationDate,
            gpsLocation: gpsLocation,
            anomalies: anomalies,
            rawMetadata: rawMetadata,
            isJPEG: isJPEG
        )
    }

    // MARK: Camera Info Extraction

    /// Extract camera information from EXIF/TIFF
    private func extractCameraInfo(exif: [String: Any]?, tiff: [String: Any]?) -> CameraInfo? {
        guard let make = tiff?[kCGImagePropertyTIFFMake as String] as? String,
              let model = tiff?[kCGImagePropertyTIFFModel as String] as? String
        else {
            return nil
        }

        // Extract lens info
        var lens: String?
        if let lensModel = exif?[kCGImagePropertyExifLensModel as String] as? String {
            lens = lensModel
        } else if let lensMake = exif?[kCGImagePropertyExifLensMake as String] as? String {
            lens = lensMake
        }

        // Extract focal length
        var focalLength: String?
        if let fl = exif?[kCGImagePropertyExifFocalLength as String] as? Double {
            focalLength = String(format: "%.0fmm", fl)
        }

        // Extract aperture
        var aperture: String?
        if let fNumber = exif?[kCGImagePropertyExifFNumber as String] as? Double {
            aperture = String(format: "f/%.1f", fNumber)
        }

        // Extract ISO
        var iso: String?
        if let isoValues = exif?[kCGImagePropertyExifISOSpeedRatings as String] as? [Int],
           let firstISO = isoValues.first
        {
            iso = String(firstISO)
        }

        // Extract shutter speed
        var shutterSpeed: String?
        if let exposure = exif?[kCGImagePropertyExifExposureTime as String] as? Double {
            if exposure < 1 {
                shutterSpeed = "1/\(Int(1 / exposure))"
            } else {
                shutterSpeed = String(format: "%.1fs", exposure)
            }
        }

        return CameraInfo(
            make: make,
            model: model,
            lens: lens,
            focalLength: focalLength,
            aperture: aperture,
            iso: iso,
            shutterSpeed: shutterSpeed
        )
    }

    // MARK: Software Extraction

    /// Extract software information from metadata
    private func extractSoftwareInfo(
        tiff: [String: Any]?,
        iptc: [String: Any]?,
        exif: [String: Any]?
    ) -> String? {
        // Check TIFF software field
        if let software = tiff?[kCGImagePropertyTIFFSoftware as String] as? String {
            return software
        }

        // Check IPTC originating program
        if let program = iptc?[kCGImagePropertyIPTCOriginatingProgram as String] as? String {
            return program
        }

        // Check EXIF user comment for software hints
        if let userComment = exif?[kCGImagePropertyExifUserComment as String] as? String {
            // Some AI tools put their name in user comment
            for pattern in MetadataResult.aiSoftwarePatterns {
                if userComment.localizedCaseInsensitiveContains(pattern) {
                    return userComment
                }
            }
        }

        return nil
    }

    // MARK: Date Extraction

    /// Extract creation date from metadata
    private func extractCreationDate(exif: [String: Any]?, tiff: [String: Any]?) -> Date? {
        // Try EXIF DateTimeOriginal first
        if let dateString = exif?[kCGImagePropertyExifDateTimeOriginal as String] as? String {
            return parseEXIFDate(dateString)
        }

        // Try EXIF DateTimeDigitized
        if let dateString = exif?[kCGImagePropertyExifDateTimeDigitized as String] as? String {
            return parseEXIFDate(dateString)
        }

        // Try TIFF DateTime
        if let dateString = tiff?[kCGImagePropertyTIFFDateTime as String] as? String {
            return parseEXIFDate(dateString)
        }

        return nil
    }

    /// Parse EXIF date format (YYYY:MM:DD HH:MM:SS)
    private func parseEXIFDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        if let date = formatter.date(from: string) {
            return date
        }

        // Try alternative formats
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: string)
    }

    // MARK: GPS Extraction

    /// Extract GPS location from metadata
    private func extractGPSLocation(gps: [String: Any]?) -> GPSLocation? {
        guard let gpsDict = gps,
              let latitude = gpsDict[kCGImagePropertyGPSLatitude as String] as? Double,
              let longitude = gpsDict[kCGImagePropertyGPSLongitude as String] as? Double
        else {
            return nil
        }

        // Apply direction references
        var lat = latitude
        var lon = longitude

        if let latRef = gpsDict[kCGImagePropertyGPSLatitudeRef as String] as? String, latRef == "S" {
            lat = -lat
        }

        if let lonRef = gpsDict[kCGImagePropertyGPSLongitudeRef as String] as? String, lonRef == "W" {
            lon = -lon
        }

        let altitude = gpsDict[kCGImagePropertyGPSAltitude as String] as? Double

        return GPSLocation(latitude: lat, longitude: lon, altitude: altitude)
    }

    // MARK: Timestamp Validation

    /// Check for timestamp inconsistencies
    private func checkTimestampConsistency(exif: [String: Any]?, tiff: [String: Any]?) -> MetadataAnomaly? {
        let originalDate = exif?[kCGImagePropertyExifDateTimeOriginal as String] as? String
        let digitizedDate = exif?[kCGImagePropertyExifDateTimeDigitized as String] as? String
        let modifyDate = tiff?[kCGImagePropertyTIFFDateTime as String] as? String

        // Check if modify date is before original date (suspicious)
        if let original = originalDate.flatMap(parseEXIFDate),
           let modify = modifyDate.flatMap(parseEXIFDate)
        {
            if modify < original {
                return MetadataAnomaly(
                    type: .inconsistentTimestamps,
                    description: "Modification date is before original capture date",
                    details: [
                        "originalDate": originalDate ?? "",
                        "modifyDate": modifyDate ?? "",
                    ]
                )
            }
        }

        // Check if original and digitized dates are very different (unusual)
        if let original = originalDate.flatMap(parseEXIFDate),
           let digitized = digitizedDate.flatMap(parseEXIFDate)
        {
            let difference = abs(original.timeIntervalSince(digitized))
            if difference > 86400 { // More than 1 day
                return MetadataAnomaly(
                    type: .inconsistentTimestamps,
                    description: "Original and digitized dates differ significantly",
                    details: [
                        "originalDate": originalDate ?? "",
                        "digitizedDate": digitizedDate ?? "",
                    ]
                )
            }
        }

        return nil
    }

    // MARK: Thumbnail Analysis

    /// Check if embedded thumbnail differs significantly from main image
    private func checkThumbnailMismatch(source: CGImageSource) -> MetadataAnomaly? {
        // Get main image
        guard let mainImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        // Try to get embedded thumbnail
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
            kCGImageSourceCreateThumbnailFromImageAlways: false,
            kCGImageSourceThumbnailMaxPixelSize: 160
        ]

        guard let embeddedThumb = CGImageSourceCreateThumbnailAtIndex(
            source, 0, thumbnailOptions as CFDictionary
        ) else {
            // No embedded thumbnail - not an anomaly by itself
            return nil
        }

        // Create a scaled version of main image for comparison
        let thumbWidth = embeddedThumb.width
        let thumbHeight = embeddedThumb.height

        guard let context = CGContext(
            data: nil,
            width: thumbWidth,
            height: thumbHeight,
            bitsPerComponent: 8,
            bytesPerRow: thumbWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(mainImage, in: CGRect(x: 0, y: 0, width: thumbWidth, height: thumbHeight))

        guard let scaledMain = context.makeImage() else {
            return nil
        }

        // Compare histograms of both images
        let difference = compareImageHistograms(embeddedThumb, scaledMain)

        // Threshold: if difference is > 25%, it's suspicious
        if difference > 0.25 {
            return MetadataAnomaly(
                type: .thumbnailMismatch,
                description: "Embedded thumbnail differs from main image (\(Int(difference * 100))% difference)",
                details: ["difference": String(format: "%.1f%%", difference * 100)]
            )
        }

        return nil
    }

    /// Compare two images using simple histogram comparison
    private func compareImageHistograms(_ image1: CGImage, _ image2: CGImage) -> Double {
        // Simple average color comparison as a quick check
        guard let data1 = image1.dataProvider?.data,
              let data2 = image2.dataProvider?.data else {
            return 0
        }

        // Safety: ensure pointers are valid before dereferencing
        guard let ptr1 = CFDataGetBytePtr(data1),
              let ptr2 = CFDataGetBytePtr(data2) else {
            return 0
        }

        let length = min(CFDataGetLength(data1), CFDataGetLength(data2))
        guard length > 3 else { return 0 }

        // Sample pixels and compare
        var totalDiff: Double = 0
        let sampleStep = max(1, length / 1000) // Sample up to 1000 pixels

        var sampleCount = 0
        var i = 0
        while i < length - 3 {
            let r1 = Double(ptr1[i])
            let g1 = Double(ptr1[i + 1])
            let b1 = Double(ptr1[i + 2])

            let r2 = Double(ptr2[i])
            let g2 = Double(ptr2[i + 1])
            let b2 = Double(ptr2[i + 2])

            // Normalized difference
            let diff = (abs(r1 - r2) + abs(g1 - g2) + abs(b1 - b2)) / (3.0 * 255.0)
            totalDiff += diff
            sampleCount += 1

            i += sampleStep * 4
        }

        return sampleCount > 0 ? totalDiff / Double(sampleCount) : 0
    }

    // MARK: Color Profile Analysis

    /// Check for suspicious color profile patterns
    private func checkColorProfile(properties: [String: Any], cameraInfo: CameraInfo?) -> MetadataAnomaly? {
        let profileName = properties[kCGImagePropertyProfileName as String] as? String

        // If camera info exists but no color profile, it's slightly suspicious
        // Real cameras usually embed their color profile
        if cameraInfo != nil && profileName == nil {
            // Not flagging this as it's too common
            return nil
        }

        // Check for generic/synthetic profiles that AI tools often use
        if let profile = profileName?.lowercased() {
            // sRGB is fine and common
            // But certain patterns suggest AI generation
            let suspiciousProfiles = [
                "generic rgb",
                "generic gray",
                "uncalibrated",
            ]

            for suspicious in suspiciousProfiles {
                if profile.contains(suspicious) {
                    return MetadataAnomaly(
                        type: .suspiciousColorProfile,
                        description: "Generic color profile detected: \(profileName ?? "unknown")",
                        details: ["profile": profileName ?? "unknown"]
                    )
                }
            }
        }

        // If there's camera info but profile doesn't match camera manufacturer
        if let camera = cameraInfo, let profile = profileName {
            let cameraLower = camera.make.lowercased()
            let profileLower = profile.lowercased()

            // Camera-specific profiles should generally match
            let cameraProfilePatterns = [
                "canon": ["canon", "eos"],
                "nikon": ["nikon", "nikkor"],
                "sony": ["sony"],
                "fuji": ["fuji", "fujifilm"],
                "panasonic": ["panasonic", "lumix"],
                "olympus": ["olympus"],
                "leica": ["leica"],
            ]

            for (brand, patterns) in cameraProfilePatterns {
                if cameraLower.contains(brand) {
                    // Camera is from this brand - check if profile mentions a different brand
                    for (otherBrand, otherPatterns) in cameraProfilePatterns where otherBrand != brand {
                        if otherPatterns.contains(where: { profileLower.contains($0) }) {
                            return MetadataAnomaly(
                                type: .suspiciousColorProfile,
                                description: "Color profile (\(profile)) doesn't match camera (\(camera.make))",
                                details: ["profile": profile, "camera": camera.make]
                            )
                        }
                    }
                    break
                }
            }
        }

        return nil
    }

    // MARK: XMP/IPTC Deep Inspection

    /// Deep inspection of XMP and IPTC metadata for AI indicators
    private func checkXMPAndIPTC(properties: [String: Any]) -> MetadataAnomaly? {
        // Get raw metadata as string for pattern matching
        let rawDict = properties as NSDictionary
        let rawString = rawDict.description.lowercased()

        // Check for AI-related terms in any metadata field
        let aiKeywords = [
            "artificial intelligence",
            "ai generated",
            "ai-generated",
            "machine learning",
            "neural network",
            "diffusion model",
            "text-to-image",
            "text2image",
            "prompt:",
            "negative prompt",
            "cfg scale",
            "sampling steps",
            "sampler:",
            "seed:",
            "checkpoint",
            "lora",
            "embeddings",
            "controlnet",
            "img2img",
            "inpainting",
            "dreambooth",
            "textual inversion",
        ]

        for keyword in aiKeywords {
            if rawString.contains(keyword) {
                return MetadataAnomaly(
                    type: .suspiciousXMP,
                    description: "AI-related term found in metadata: \"\(keyword)\"",
                    details: ["keyword": keyword]
                )
            }
        }

        // Check IPTC keywords specifically
        let iptcDict = properties[kCGImagePropertyIPTCDictionary as String] as? [String: Any]
        if let keywords = iptcDict?[kCGImagePropertyIPTCKeywords as String] as? [String] {
            let keywordsLower = keywords.joined(separator: " ").lowercased()

            for aiKeyword in aiKeywords {
                if keywordsLower.contains(aiKeyword) {
                    return MetadataAnomaly(
                        type: .suspiciousXMP,
                        description: "AI-related keyword in IPTC: \"\(aiKeyword)\"",
                        details: ["keywords": keywords.joined(separator: ", ")]
                    )
                }
            }

            // Also check for known AI tool names in keywords
            for pattern in MetadataResult.aiSoftwarePatterns {
                if keywordsLower.contains(pattern.lowercased()) {
                    return MetadataAnomaly(
                        type: .suspiciousXMP,
                        description: "AI tool name found in IPTC keywords: \"\(pattern)\"",
                        details: ["keywords": keywords.joined(separator: ", ")]
                    )
                }
            }
        }

        // Check IPTC caption/description
        if let caption = iptcDict?[kCGImagePropertyIPTCCaptionAbstract as String] as? String {
            let captionLower = caption.lowercased()

            for aiKeyword in aiKeywords {
                if captionLower.contains(aiKeyword) {
                    return MetadataAnomaly(
                        type: .suspiciousXMP,
                        description: "AI-related term in image caption",
                        details: ["caption": caption]
                    )
                }
            }
        }

        // Check for suspicious patterns in user comment
        let exifDict = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
        if let userComment = exifDict?[kCGImagePropertyExifUserComment as String] as? String {
            let commentLower = userComment.lowercased()

            // Check for generation parameters (common in SD outputs)
            if commentLower.contains("steps:") && commentLower.contains("sampler:") {
                return MetadataAnomaly(
                    type: .suspiciousXMP,
                    description: "Stable Diffusion generation parameters found in EXIF",
                    details: ["userComment": String(userComment.prefix(200))]
                )
            }

            // Check for embedded prompt
            if commentLower.contains("prompt:") || commentLower.hasPrefix("a ") && commentLower.contains(",") {
                // Likely a prompt string
                let promptIndicators = ["masterpiece", "best quality", "highly detailed", "8k", "4k uhd", "hyperrealistic"]
                for indicator in promptIndicators {
                    if commentLower.contains(indicator) {
                        return MetadataAnomaly(
                            type: .suspiciousXMP,
                            description: "AI prompt-like text detected in EXIF comment",
                            details: ["indicator": indicator]
                        )
                    }
                }
            }
        }

        // Check for empty/stripped metadata combined with JPEG (suspicious)
        // This is already handled by missingExif check

        return nil
    }

    // MARK: JPEG Compression Analysis

    /// Analyze JPEG compression characteristics for signs of re-encoding or AI generation
    private func checkJPEGCompression(properties: [String: Any], isJPEG: Bool) -> MetadataAnomaly? {
        guard isJPEG else { return nil }

        // Check JFIF properties
        let jfifDict = properties[kCGImagePropertyJFIFDictionary as String] as? [String: Any]

        // Check for unusual JFIF density settings
        // AI tools often output with default 72 DPI or unusual values
        if let jfif = jfifDict {
            let xDensity = jfif[kCGImagePropertyJFIFXDensity as String] as? Int ?? 72
            let yDensity = jfif[kCGImagePropertyJFIFYDensity as String] as? Int ?? 72

            // Very unusual densities can indicate synthetic origin
            if xDensity == 1 && yDensity == 1 {
                return MetadataAnomaly(
                    type: .suspiciousQuantization,
                    description: "JPEG has minimal density values (common in AI-generated images)",
                    details: ["xDensity": String(xDensity), "yDensity": String(yDensity)]
                )
            }
        }

        // Check for Photoshop/editing software quality markers
        // These are often in the 8BIM resource blocks but we can detect via software field
        let tiffDict = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        if let software = tiffDict?[kCGImagePropertyTIFFSoftware as String] as? String {
            let softwareLower = software.lowercased()

            // Detect common image processing libraries used by AI pipelines
            let aiPipelineIndicators = [
                "pillow",
                "pil",
                "opencv",
                "imagemagick",
                "graphicsmagick",
                "python",
                "pytorch",
                "tensorflow",
                "torch",
            ]

            for indicator in aiPipelineIndicators {
                if softwareLower.contains(indicator) {
                    return MetadataAnomaly(
                        type: .suspiciousQuantization,
                        description: "Image processed with AI/ML pipeline software: \(software)",
                        details: ["software": software]
                    )
                }
            }
        }

        // Check depth - AI images sometimes have unusual bit depths
        if let depth = properties[kCGImagePropertyDepth as String] as? Int {
            // Standard is 8-bit per channel
            // 16-bit is fine for HDR/RAW workflows
            // Other values are unusual
            if depth != 8 && depth != 16 && depth != 24 && depth != 32 {
                return MetadataAnomaly(
                    type: .suspiciousQuantization,
                    description: "Unusual bit depth: \(depth)",
                    details: ["depth": String(depth)]
                )
            }
        }

        return nil
    }

    // MARK: Helper Methods

    /// Flatten nested metadata into key-value pairs
    private func flattenMetadata(_ properties: [String: Any], prefix: String = "") -> [String: String] {
        var result: [String: String] = [:]

        for (key, value) in properties {
            let fullKey = prefix.isEmpty ? key : "\(prefix).\(key)"

            if let dict = value as? [String: Any] {
                result.merge(flattenMetadata(dict, prefix: fullKey)) { _, new in new }
            } else if let array = value as? [Any] {
                result[fullKey] = array.map { String(describing: $0) }.joined(separator: ", ")
            } else {
                result[fullKey] = String(describing: value)
            }
        }

        return result
    }

    /// Check if file is JPEG format
    private func isJPEGFile(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "jpg" || ext == "jpeg"
    }

    /// Check if data is JPEG format
    private func isJPEGData(data: Data) -> Bool {
        // Check for JPEG magic bytes (FFD8)
        guard data.count >= 2 else { return false }
        return data[0] == 0xFF && data[1] == 0xD8
    }
}
