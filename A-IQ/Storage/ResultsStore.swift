import CoreGraphics
import Foundation
import ImageIO
import SwiftData

// MARK: - Results Store

/// Manages persistence of analysis results using SwiftData
/// Implements: Req 8.1, 8.2, 8.3, 8.4, 8.5, 8.6, 11.4, 12.5
actor ResultsStore {
    // MARK: Constants

    /// Maximum number of records to store (1000)
    static let maxRecordCount = 1000

    /// Thumbnail JPEG quality
    static let thumbnailQuality: CGFloat = 0.7

    // MARK: Properties

    private let modelContainer: ModelContainer
    private var modelContext: ModelContext

    // MARK: Initialization

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        modelContext = ModelContext(modelContainer)
    }

    // MARK: Save

    /// Save an analysis result to persistent storage
    /// Implements: Req 8.1
    func save(_ result: AggregatedResult) async throws {
        // Check storage limit
        try await enforceStorageLimit()

        // Create record (convenience init handles all fields including filename)
        let record = try AnalysisRecord(from: result)

        // Generate thumbnail data if needed
        if record.thumbnailData == nil, let thumbnail = result.imageThumbnail {
            record.thumbnailData = generateThumbnailData(from: thumbnail)
        }

        // Insert and save
        modelContext.insert(record)
        try modelContext.save()
    }

    // MARK: Fetch

    /// Fetch all records sorted by date (newest first)
    /// Implements: Req 8.2
    func fetchAll() async throws -> [AnalysisRecord] {
        let descriptor = FetchDescriptor<AnalysisRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Fetch records with pagination
    func fetchPage(offset: Int, limit: Int) async throws -> [AnalysisRecord] {
        var descriptor = FetchDescriptor<AnalysisRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor)
    }

    /// Fetch records filtered by classification
    /// Implements: Req 8.3
    func fetch(classification: OverallClassification) async throws -> [AnalysisRecord] {
        let classificationValue = classification.rawValue
        let predicate = #Predicate<AnalysisRecord> { record in
            record.classification == classificationValue
        }
        let descriptor = FetchDescriptor<AnalysisRecord>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Search records by filename
    /// Implements: Req 8.4
    func search(query: String) async throws -> [AnalysisRecord] {
        let lowercasedQuery = query.lowercased()
        let predicate = #Predicate<AnalysisRecord> { record in
            record.filename.localizedStandardContains(lowercasedQuery)
        }
        let descriptor = FetchDescriptor<AnalysisRecord>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Fetch records within date range
    func fetch(from startDate: Date, to endDate: Date) async throws -> [AnalysisRecord] {
        let predicate = #Predicate<AnalysisRecord> { record in
            record.timestamp >= startDate && record.timestamp <= endDate
        }
        let descriptor = FetchDescriptor<AnalysisRecord>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    // MARK: Retrieve Full Result

    /// Get full AggregatedResult from a record
    /// Implements: Req 8.5
    func getFullResult(from record: AnalysisRecord) throws -> AggregatedResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AggregatedResult.self, from: record.resultJSON)
    }

    // MARK: Delete

    /// Delete a single record
    /// Implements: Req 8.6
    func delete(_ record: AnalysisRecord) async throws {
        modelContext.delete(record)
        try modelContext.save()
    }

    /// Delete multiple records
    func delete(_ records: [AnalysisRecord]) async throws {
        for record in records {
            modelContext.delete(record)
        }
        try modelContext.save()
    }

    /// Delete all records
    func deleteAll() async throws {
        let records = try await fetchAll()
        for record in records {
            modelContext.delete(record)
        }
        try modelContext.save()
    }

    // MARK: Statistics

    /// Get total record count
    func recordCount() async throws -> Int {
        let descriptor = FetchDescriptor<AnalysisRecord>()
        return try modelContext.fetchCount(descriptor)
    }

    /// Get count by classification
    func countByClassification() async throws -> [OverallClassification: Int] {
        var counts: [OverallClassification: Int] = [:]

        for classification in OverallClassification.allCases {
            let value = classification.rawValue
            let predicate = #Predicate<AnalysisRecord> { record in
                record.classification == value
            }
            let descriptor = FetchDescriptor<AnalysisRecord>(predicate: predicate)
            counts[classification] = try modelContext.fetchCount(descriptor)
        }

        return counts
    }

    // MARK: Storage Management

    /// Check and enforce storage limit
    /// Implements: Req 11.4
    private func enforceStorageLimit() async throws {
        let count = try await recordCount()

        if count >= Self.maxRecordCount {
            // Delete oldest records to make room
            let excess = count - Self.maxRecordCount + 1
            var descriptor = FetchDescriptor<AnalysisRecord>(
                sortBy: [SortDescriptor(\.timestamp, order: .forward)]
            )
            descriptor.fetchLimit = excess

            let oldRecords = try modelContext.fetch(descriptor)
            for record in oldRecords {
                modelContext.delete(record)
            }
        }
    }

    /// Flush pending writes
    /// Implements: Req 12.5
    func flushPendingWrites() async throws {
        try modelContext.save()
    }

    // MARK: Helpers

    /// Generate JPEG data from thumbnail
    private func generateThumbnailData(from image: CGImage) -> Data? {
        let mutableData = NSMutableData()

        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            "public.jpeg" as CFString,
            1,
            nil
        ) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: Self.thumbnailQuality,
        ]

        CGImageDestinationAddImage(destination, image, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return mutableData as Data
    }
}

// MARK: - Convenience Extensions

extension ResultsStore {
    /// Create a results store with a new in-memory container (for testing)
    static func inMemory() throws -> ResultsStore {
        let schema = Schema([AnalysisRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        return ResultsStore(modelContainer: container)
    }
}
