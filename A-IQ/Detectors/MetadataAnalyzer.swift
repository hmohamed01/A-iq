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
        let timestampAnomaly = checkTimestampConsistency(exif: exifDict, tiff: tiffDict)
        if let anomaly = timestampAnomaly {
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
