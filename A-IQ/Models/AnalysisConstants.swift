import Foundation

// MARK: - Analysis Constants

/// Centralized constants for analysis configuration
/// Helps maintain consistency and makes configuration easier to adjust
enum AnalysisConstants {
    // MARK: Concurrency
    
    /// Maximum number of concurrent analyses
    static let maxConcurrentAnalyses = 4
    
    // MARK: Memory Management
    
    /// Memory threshold for throttling (2GB)
    static let memoryThresholdBytes: Int = 2_000_000_000
    
    /// Memory check delay when constrained (milliseconds)
    static let memoryConstrainedDelayMs: Int = 500
    
    // MARK: Image Processing
    
    /// Thumbnail size for results display
    static let thumbnailSize = CGSize(width: 256, height: 256)
    
    // MARK: Classification Thresholds
    
    /// Score below this indicates likely authentic
    static let likelyAuthenticThreshold: Double = 0.30
    
    /// Score above this indicates likely AI-generated
    static let likelyAIGeneratedThreshold: Double = 0.70
    
    /// Neutral score (no opinion)
    static let neutralScore: Double = 0.5
    
    // MARK: Score Adjustments
    
    /// Minimum score value
    static let minScore: Double = 0.0
    
    /// Maximum score value
    static let maxScore: Double = 1.0
    
    /// Decisive threshold - score must be this far from neutral to be considered decisive
    static let decisiveThreshold: Double = 0.1
    
    // MARK: ML Confidence Amplification
    
    /// High confidence amplification factor with corroboration
    static let mlAmplificationWithCorroboration: Double = 1.0
    
    /// High confidence amplification factor without corroboration
    static let mlAmplificationWithoutCorroboration: Double = 0.85
    
    /// ML weight boost when confidence is very high
    static let mlDominanceBoost: Double = 0.1
    
    // MARK: Weight Redistribution
    
    /// Percentage of redistributed weight that goes to ML when decisive
    static let mlRedistributionShare: Double = 0.7
    
    /// Minimum weight to keep for display purposes
    static let minDisplayWeight: Double = 0.05
}

