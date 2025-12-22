import Foundation
import SwiftData

// MARK: - Analysis Record

/// Persistent storage model for analysis history
/// Implements: Req 8.1, 8.2, 8.3, 8.4, 8.5
@Model
final class AnalysisRecord {
    // MARK: Properties

    /// Unique identifier matching the AggregatedResult
    @Attribute(.unique)
    var id: UUID

    /// Original filename or display name
    var filename: String

    /// Thumbnail image data (JPEG compressed)
    var thumbnailData: Data?

    /// When the analysis was performed
    var timestamp: Date

    /// Overall confidence score (0.0 to 1.0)
    var overallScore: Double

    /// Classification result as string
    var classification: String

    /// Full result serialized as JSON
    var resultJSON: Data

    /// File size in bytes (optional)
    var fileSizeBytes: Int?

    /// Image dimensions as string "WxH"
    var imageDimensions: String?

    /// Analysis duration in milliseconds
    var analysisTimeMs: Int

    // MARK: Initializers

    init(
        id: UUID,
        filename: String,
        thumbnailData: Data? = nil,
        timestamp: Date,
        overallScore: Double,
        classification: String,
        resultJSON: Data,
        fileSizeBytes: Int? = nil,
        imageDimensions: String? = nil,
        analysisTimeMs: Int
    ) {
        self.id = id
        self.filename = filename
        self.thumbnailData = thumbnailData
        self.timestamp = timestamp
        self.overallScore = overallScore
        self.classification = classification
        self.resultJSON = resultJSON
        self.fileSizeBytes = fileSizeBytes
        self.imageDimensions = imageDimensions
        self.analysisTimeMs = analysisTimeMs
    }

    /// Create from an AggregatedResult
    /// - Parameters:
    ///   - result: The analysis result to store
    ///   - storeThumbnail: Whether to store the thumbnail (disable for privacy)
    convenience init(from result: AggregatedResult, storeThumbnail: Bool = true) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(result)

        var dimensions: String? = nil
        if let size = result.imageSize {
            dimensions = "\(Int(size.width))x\(Int(size.height))"
        }

        let thumbnail: Data? = storeThumbnail
            ? result.imageThumbnail?.jpegData(compressionQuality: 0.7)
            : nil

        self.init(
            id: result.id,
            filename: result.imageSource.displayName,
            thumbnailData: thumbnail,
            timestamp: result.timestamp,
            overallScore: result.overallScore,
            classification: result.classification.rawValue,
            resultJSON: jsonData,
            fileSizeBytes: result.fileSizeBytes,
            imageDimensions: dimensions,
            analysisTimeMs: result.totalAnalysisTimeMs
        )
    }

    // MARK: Methods

    /// Decode the full AggregatedResult from stored JSON
    func decodeResult() throws -> AggregatedResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var result = try decoder.decode(AggregatedResult.self, from: resultJSON)

        // Restore thumbnail from stored data (CGImage isn't Codable)
        if let data = thumbnailData, let thumbnail = cgImageFromData(data) {
            result = result.withThumbnail(thumbnail)
        }

        return result
    }

    /// Convert stored thumbnail data back to CGImage
    private func cgImageFromData(_ data: Data) -> CGImage? {
        #if os(macOS)
        guard let nsImage = NSImage(data: data),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return cgImage
        #else
        return nil
        #endif
    }

    /// Get the classification enum value
    var classificationEnum: OverallClassification {
        OverallClassification(rawValue: classification) ?? .uncertain
    }

    /// Format the file size for display
    var formattedFileSize: String? {
        guard let bytes = fileSizeBytes else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    /// Format the timestamp for display
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }

    /// Score as percentage string
    var scorePercentage: String {
        "\(Int(overallScore * 100))%"
    }
}

// MARK: - CGImage JPEG Extension

extension CGImage {
    /// Convert CGImage to JPEG data
    func jpegData(compressionQuality: CGFloat) -> Data? {
        #if os(macOS)
            let bitmapRep = NSBitmapImageRep(cgImage: self)
            return bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
        #else
            // iOS would use UIImage
            return nil
        #endif
    }
}

#if os(macOS)
    import AppKit
#endif

// MARK: - Query Helpers

extension AnalysisRecord {
    /// Predicate for searching by classification
    static func classificationPredicate(_ classification: OverallClassification) -> Predicate<AnalysisRecord> {
        let classificationString = classification.rawValue
        return #Predicate<AnalysisRecord> { record in
            record.classification == classificationString
        }
    }

    /// Predicate for searching by filename
    static func filenamePredicate(containing search: String) -> Predicate<AnalysisRecord> {
        return #Predicate<AnalysisRecord> { record in
            record.filename.localizedStandardContains(search)
        }
    }

    /// Predicate for date range
    static func dateRangePredicate(from startDate: Date, to endDate: Date) -> Predicate<AnalysisRecord> {
        return #Predicate<AnalysisRecord> { record in
            record.timestamp >= startDate && record.timestamp <= endDate
        }
    }
}

// MARK: - Storage Limits

extension AnalysisRecord {
    /// Maximum records before prompting for cleanup
    /// Implements: Req 8.6
    static let maxRecordsBeforePrompt = 1000

    /// Target thumbnail size
    static let thumbnailSize = CGSize(width: 200, height: 200)
}
