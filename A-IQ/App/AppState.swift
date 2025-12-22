import OSLog
import SwiftData
import SwiftUI

// MARK: - Logger

private let storageLogger = Logger(subsystem: "com.aiq.app", category: "Storage")

// MARK: - App State

/// Application-wide state management
/// Implements: Req 7.1, 7.2, 7.3, 7.7, 11.3
@MainActor
final class AppState: ObservableObject {
    // MARK: Published State

    /// Current analysis result being displayed
    @Published var currentAnalysis: AggregatedResult?

    /// Whether analysis is currently in progress
    @Published var isAnalyzing: Bool = false

    /// Progress of current analysis (0.0 to 1.0)
    @Published var analysisProgress: Double = 0

    /// Current error message to display
    @Published var errorMessage: String?

    /// Images queued for batch analysis
    @Published var batchQueue: [ImageSource] = []

    /// Results from batch analysis
    @Published var batchResults: [AggregatedResult] = []

    /// Current status message
    @Published var statusMessage: String = "Ready"

    /// Currently selected tab
    @Published var selectedTab: Tab = .analyze

    /// Current analysis task (for cancellation)
    private var currentAnalysisTask: Task<Void, Never>?

    // MARK: Services

    /// Settings manager for user preferences
    let settingsManager: SettingsManager

    /// Analysis orchestrator
    let orchestrator: AnalysisOrchestrator

    /// Image input handler
    let inputHandler: ImageInputHandler

    /// Model context for persistence
    var modelContext: ModelContext?

    // MARK: Initialization

    /// Default initializer for production use
    init() {
        self.settingsManager = SettingsManager()
        self.orchestrator = AnalysisOrchestrator()
        self.inputHandler = ImageInputHandler()

        // Preload models in background
        Task {
            await orchestrator.preloadModels()
        }
    }

    /// Dependency injection initializer for testing
    init(
        settingsManager: SettingsManager,
        orchestrator: AnalysisOrchestrator,
        inputHandler: ImageInputHandler
    ) {
        self.settingsManager = settingsManager
        self.orchestrator = orchestrator
        self.inputHandler = inputHandler
    }

    // MARK: Analysis Methods

    /// Analyze a single image
    /// Implements: Req 12.1
    func analyzeImage(_ source: ImageSource) async {
        isAnalyzing = true
        analysisProgress = 0
        errorMessage = nil
        statusMessage = "Analyzing image..."

        let options = createAnalysisOptions()

        // Check for cancellation before starting
        guard !Task.isCancelled else {
            isAnalyzing = false
            statusMessage = "Analysis cancelled"
            return
        }

        currentAnalysis = await orchestrator.analyze(source, options: options)

        // Check for cancellation after analysis
        guard !Task.isCancelled else {
            isAnalyzing = false
            statusMessage = "Analysis cancelled"
            return
        }

        // Save to history
        if let result = currentAnalysis, let context = modelContext {
            await saveToHistory(result: result, context: context)
        }

        isAnalyzing = false
        analysisProgress = 1.0
        statusMessage = "Analysis complete"
    }

    /// Analyze image from file URL
    func analyzeFile(at url: URL) async {
        do {
            let source = try inputHandler.validateFile(at: url)
            await analyzeImage(source)
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    /// Analyze image from clipboard
    func analyzeClipboard() async {
        do {
            let source = try inputHandler.extractFromClipboard()
            await analyzeImage(source)
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    /// Analyze multiple images
    /// Implements: Req 12.2
    func analyzeImages(_ sources: [ImageSource]) async {
        guard !sources.isEmpty else { return }

        isAnalyzing = true
        batchQueue = sources
        batchResults = []
        analysisProgress = 0
        statusMessage = "Analyzing \(sources.count) images..."

        let options = createAnalysisOptions()
        var completedCount = 0

        for await result in await orchestrator.analyzeBatch(sources, options: options) {
            // Check for cancellation
            guard !Task.isCancelled else {
                isAnalyzing = false
                batchQueue = []
                statusMessage = "Batch analysis cancelled"
                return
            }

            completedCount += 1
            batchResults.append(result)
            analysisProgress = Double(completedCount) / Double(sources.count)
            statusMessage = "Analyzed \(completedCount) of \(sources.count) images"

            // Save to history
            if let context = modelContext {
                await saveToHistory(result: result, context: context)
            }
        }

        isAnalyzing = false
        batchQueue = []
        statusMessage = "Batch analysis complete"
    }

    /// Analyze folder of images
    func analyzeFolder(at url: URL) async {
        do {
            statusMessage = "Scanning folder..."
            let sources = try await inputHandler.scanFolder(at: url)

            guard !sources.isEmpty else {
                errorMessage = "No supported images found in folder"
                statusMessage = "No images found"
                return
            }

            await analyzeImages(sources)
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    // MARK: File Picker

    /// Present file picker and analyze selected images
    func openFilePicker(allowsMultiple: Bool = true) async {
        let urls = await inputHandler.presentFilePicker(allowsMultiple: allowsMultiple)

        guard !urls.isEmpty else { return }

        // Cancel any existing analysis before starting new one
        currentAnalysisTask?.cancel()

        // Start analysis in a cancellable task
        currentAnalysisTask = Task {
            if urls.count == 1 {
                await analyzeFile(at: urls[0])
            } else {
                let sources = urls.map { ImageSource.fileURL($0) }
                await analyzeImages(sources)
            }
        }
    }

    /// Present folder picker and analyze images
    func openFolderPicker() async {
        guard let url = await inputHandler.presentFolderPicker() else { return }
        startAnalyzeFolder(at: url)
    }

    // MARK: State Management

    /// Clear current analysis result
    func clearCurrentAnalysis() {
        currentAnalysis = nil
        errorMessage = nil
        statusMessage = "Ready"
    }

    /// Clear all batch results
    func clearBatchResults() {
        batchResults = []
    }

    /// Cancel ongoing analysis
    func cancelAnalysis() {
        currentAnalysisTask?.cancel()
        currentAnalysisTask = nil
        isAnalyzing = false
        batchQueue = []
        statusMessage = "Analysis cancelled"
    }

    // MARK: Private Helpers

    /// Create analysis options from settings
    private func createAnalysisOptions() -> AnalysisOptions {
        AnalysisOptions(
            runMLDetection: true,
            runProvenanceCheck: true,
            runMetadataAnalysis: true,
            runForensicAnalysis: true,
            sensitivityAdjustment: settingsManager.sensitivityAdjustment
        )
    }

    /// Save analysis result to history
    private func saveToHistory(result: AggregatedResult, context: ModelContext) async {
        do {
            // Create record with thumbnail setting from preferences
            let record = try AnalysisRecord(
                from: result,
                storeThumbnail: settingsManager.storeThumbnailsInHistory
            )

            // Insert into context
            context.insert(record)

            // Try to save
            try context.save()
        } catch {
            storageLogger.error("Failed to save analysis record: \(error.localizedDescription)")
        }
    }
}

// MARK: - Navigation State

extension AppState {
    /// Currently selected tab in the main view
    enum Tab: String, CaseIterable {
        case analyze = "Analyze"
        case history = "History"

        var systemImage: String {
            switch self {
            case .analyze: return "doc.viewfinder"
            case .history: return "clock"
            }
        }
    }
}

// MARK: - Drop Handling

extension AppState {
    /// Handle dropped files
    func handleDroppedFiles(_ urls: [URL]) {
        let validSources = urls.compactMap { url -> ImageSource? in
            let ext = url.pathExtension.lowercased()
            guard ImageInputHandler.supportedExtensions.contains(ext) else {
                return nil
            }
            return .fileURL(url)
        }

        guard !validSources.isEmpty else {
            errorMessage = "No supported image files found"
            return
        }

        // Cancel any existing analysis before starting new one
        currentAnalysisTask?.cancel()

        // Start analysis in a cancellable task
        currentAnalysisTask = Task {
            if validSources.count == 1 {
                await analyzeImage(validSources[0])
            } else {
                await analyzeImages(validSources)
            }
        }
    }

    /// Start file analysis with proper task tracking
    func startAnalyzeFile(at url: URL) {
        currentAnalysisTask?.cancel()
        currentAnalysisTask = Task {
            await analyzeFile(at: url)
        }
    }

    /// Start clipboard analysis with proper task tracking
    func startAnalyzeClipboard() {
        currentAnalysisTask?.cancel()
        currentAnalysisTask = Task {
            await analyzeClipboard()
        }
    }

    /// Start folder analysis with proper task tracking
    func startAnalyzeFolder(at url: URL) {
        currentAnalysisTask?.cancel()
        currentAnalysisTask = Task {
            await analyzeFolder(at: url)
        }
    }
}
