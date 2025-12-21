import CoreLocation
import Foundation

// MARK: - Metadata Result

/// Result from image metadata analysis
/// Implements: Req 4.1, 4.2, 4.3, 4.4, 4.5, 4.6
struct MetadataResult: DetectionResult, Codable, Sendable {
    // MARK: DetectionResult Protocol

    let detectorName: String = "MetadataAnalyzer"
    let score: Double
    let confidence: ResultConfidence
    let evidence: [Evidence]
    let error: DetectionError?

    // MARK: Metadata-Specific Properties

    /// Whether EXIF data is present
    let hasExifData: Bool

    /// Camera information from EXIF
    let cameraInfo: CameraInfo?

    /// Software used to create/edit the image
    let softwareInfo: String?

    /// Creation date from metadata
    let creationDate: Date?

    /// GPS location if present
    let gpsLocation: GPSLocation?

    /// Detected metadata anomalies
    let anomalies: [MetadataAnomaly]

    /// All extracted metadata as key-value pairs
    let rawMetadata: [String: String]

    // MARK: Initializers

    /// Create a successful metadata result
    init(
        hasExifData: Bool,
        cameraInfo: CameraInfo? = nil,
        softwareInfo: String? = nil,
        creationDate: Date? = nil,
        gpsLocation: GPSLocation? = nil,
        anomalies: [MetadataAnomaly] = [],
        rawMetadata: [String: String] = [:],
        isJPEG: Bool = false
    ) {
        self.hasExifData = hasExifData
        self.cameraInfo = cameraInfo
        self.softwareInfo = softwareInfo
        self.creationDate = creationDate
        self.gpsLocation = gpsLocation
        self.anomalies = anomalies
        self.rawMetadata = rawMetadata
        error = nil

        // Calculate score based on metadata analysis
        var scoreFactors: [Double] = []

        // Check for AI software signatures
        let isAISoftware = softwareInfo.map { Self.isAISoftware($0) } ?? false
        if isAISoftware {
            scoreFactors.append(0.9) // Strong indicator of AI
        }

        // Missing EXIF in JPEG is suspicious
        if isJPEG && !hasExifData {
            scoreFactors.append(0.6)
        }

        // Camera info suggests authentic photo
        if cameraInfo != nil {
            scoreFactors.append(0.2)
        }

        // GPS data suggests authentic photo
        if gpsLocation != nil {
            scoreFactors.append(0.15)
        }

        // Anomalies increase score
        for anomaly in anomalies {
            switch anomaly.type {
            case .aiToolDetected:
                scoreFactors.append(0.9)
            case .impossibleDate, .futureDateDetected:
                scoreFactors.append(0.5)
            case .missingExif:
                scoreFactors.append(0.4)
            case .inconsistentTimestamps:
                scoreFactors.append(0.3)
            }
        }

        // Average the factors or use neutral if none
        if scoreFactors.isEmpty {
            score = 0.5
        } else {
            score = scoreFactors.reduce(0, +) / Double(scoreFactors.count)
        }

        // Determine confidence
        if cameraInfo != nil || isAISoftware || !anomalies.isEmpty {
            confidence = .high
        } else if hasExifData {
            confidence = .medium
        } else {
            confidence = .low
        }

        // Build evidence
        var evidenceList: [Evidence] = []

        if hasExifData {
            evidenceList.append(Evidence(
                type: .metadataPresent,
                description: "EXIF metadata present in image",
                isPositiveIndicator: false
            ))
        } else if isJPEG {
            evidenceList.append(Evidence(
                type: .metadataAbsent,
                description: "No EXIF metadata found (unusual for JPEG)",
                isPositiveIndicator: true
            ))
        }

        if let camera = cameraInfo {
            evidenceList.append(Evidence(
                type: .metadataCameraInfo,
                description: "Camera: \(camera.make) \(camera.model)",
                details: [
                    "make": camera.make,
                    "model": camera.model,
                    "lens": camera.lens ?? "Unknown",
                ],
                isPositiveIndicator: false
            ))
        }

        if let gps = gpsLocation {
            evidenceList.append(Evidence(
                type: .metadataGPSLocation,
                description: "GPS coordinates present",
                details: [
                    "latitude": String(format: "%.6f", gps.latitude),
                    "longitude": String(format: "%.6f", gps.longitude),
                ],
                isPositiveIndicator: false
            ))
        }

        if let software = softwareInfo, Self.isAISoftware(software) {
            evidenceList.append(Evidence(
                type: .metadataAISoftware,
                description: "AI software detected: \(software)",
                details: ["software": software],
                isPositiveIndicator: true
            ))
        }

        for anomaly in anomalies {
            evidenceList.append(Evidence(
                type: anomaly.type.toEvidenceType(),
                description: anomaly.description,
                isPositiveIndicator: true
            ))
        }

        evidence = evidenceList
    }

    /// Create a failed metadata result
    init(error: DetectionError) {
        hasExifData = false
        cameraInfo = nil
        softwareInfo = nil
        creationDate = nil
        gpsLocation = nil
        anomalies = []
        rawMetadata = [:]
        score = 0.5
        confidence = .unavailable
        self.error = error
        evidence = []
    }
}

// MARK: - Camera Info

/// Camera information extracted from EXIF
struct CameraInfo: Sendable, Codable {
    let make: String
    let model: String
    let lens: String?
    let focalLength: String?
    let aperture: String?
    let iso: String?
    let shutterSpeed: String?

    init(
        make: String,
        model: String,
        lens: String? = nil,
        focalLength: String? = nil,
        aperture: String? = nil,
        iso: String? = nil,
        shutterSpeed: String? = nil
    ) {
        self.make = make
        self.model = model
        self.lens = lens
        self.focalLength = focalLength
        self.aperture = aperture
        self.iso = iso
        self.shutterSpeed = shutterSpeed
    }
}

// MARK: - GPS Location

/// GPS location from image metadata
struct GPSLocation: Sendable, Codable {
    let latitude: Double
    let longitude: Double
    let altitude: Double?

    init(latitude: Double, longitude: Double, altitude: Double? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Metadata Anomaly

/// Detected anomaly in image metadata
struct MetadataAnomaly: Sendable, Codable, Identifiable {
    let id: UUID
    let type: AnomalyType
    let description: String
    let details: [String: String]

    init(
        id: UUID = UUID(),
        type: AnomalyType,
        description: String,
        details: [String: String] = [:]
    ) {
        self.id = id
        self.type = type
        self.description = description
        self.details = details
    }
}

// MARK: - Anomaly Type

/// Types of metadata anomalies
enum AnomalyType: String, Sendable, Codable {
    case missingExif = "missing_exif"
    case aiToolDetected = "ai_tool_detected"
    case futureDateDetected = "future_date"
    case impossibleDate = "impossible_date"
    case inconsistentTimestamps = "inconsistent_timestamps"

    var displayName: String {
        switch self {
        case .missingExif: return "Missing EXIF"
        case .aiToolDetected: return "AI Tool Detected"
        case .futureDateDetected: return "Future Date"
        case .impossibleDate: return "Impossible Date"
        case .inconsistentTimestamps: return "Inconsistent Timestamps"
        }
    }

    func toEvidenceType() -> EvidenceType {
        switch self {
        case .missingExif: return .metadataAbsent
        case .aiToolDetected: return .metadataAISoftware
        case .futureDateDetected, .impossibleDate: return .metadataDateAnomaly
        case .inconsistentTimestamps: return .metadataAnomaly
        }
    }
}

// MARK: - AI Software Detection

extension MetadataResult {
    /// Known AI software signatures in metadata
    /// Implements: Req 4.4
    static let aiSoftwarePatterns: [String] = [
        "Adobe Firefly",
        "Photoshop Generative",
        "DALL-E",
        "DALL·E",
        "Midjourney",
        "Stable Diffusion",
        "ComfyUI",
        "Automatic1111",
        "InvokeAI",
        "Leonardo.ai",
        "Runway",
        "Bing Image Creator",
        "DreamStudio",
    ]

    /// Check if software string indicates AI involvement
    static func isAISoftware(_ software: String) -> Bool {
        let lowercased = software.lowercased()
        return aiSoftwarePatterns.contains { pattern in
            lowercased.contains(pattern.lowercased())
        }
    }
}
