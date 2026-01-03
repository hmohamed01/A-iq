# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Run from project root (A-iq/)
cd ~/Projects/A-iq

# Build the app
xcodebuild build -scheme A-IQ -destination 'platform=macOS'

# Build for release
xcodebuild build -scheme A-IQ -configuration Release -destination 'platform=macOS'

# Clean build
xcodebuild clean build -scheme A-IQ -destination 'platform=macOS'
```

**Note:** The project has test files in `A-IQTests/` but no test target is configured in the Xcode project. Tests cannot be run via `xcodebuild test`.

## Project Overview

A-IQ is a native macOS app (SwiftUI, macOS 14+) that detects AI-generated images using five parallel detection methods. All processing happens locally with no network access required.

## Architecture

### Core Analysis Pipeline

```
ImageSource → AnalysisOrchestrator → [5 Detectors in Parallel] → ResultAggregator → AggregatedResult
                                            ↓
                    ┌─────────────┬─────────────┬─────────────┬─────────────┐
                    │             │             │             │             │
               MLDetector  ProvenanceChecker  MetadataAnalyzer  ForensicAnalyzer  FaceSwapDetector
               (Core ML)      (C2PA)           (EXIF)          (ELA/FFT)        (Vision)
                  40%*         30%*             15%*            15%*              0%*

*Default weights when no faces detected. With faces: ML 35%, Provenance 25%, Metadata 10%, Forensic 10%, FaceSwap 20%
```

### Key Components

- **AnalysisOrchestrator** (`Analysis/AnalysisOrchestrator.swift`): Actor that coordinates parallel analysis using `AsyncSemaphore` for concurrency throttling (max 4 concurrent, 2GB memory limit)
- **ResultAggregator** (`Analysis/ResultAggregator.swift`): Combines five detector scores using weighted averaging with dynamic weight redistribution based on face detection

### Directory Structure

```
A-IQ/
├── App/                    # Entry point, state management, commands
├── Analysis/               # Orchestration and result aggregation
├── Detectors/              # Five detection methods (ML, Provenance, Metadata, Forensic, FaceSwap)
├── Models/                 # Data structures, protocols, SwiftData models
├── Views/                  # SwiftUI interface and components
├── Input/                  # Image acquisition (file, clipboard, drag-drop)
├── Settings/               # User preferences via @AppStorage
├── Storage/                # SwiftData persistence layer
├── Export/                 # PDF and JSON report generation
└── Resources/              # ML model, c2patool binary, trust list
```

## ML Model Details

### Current Model: SigLIP v2.0

**File:** `A-IQ/Resources/AIDetector.mlmodelc`

| Property | Value |
|----------|-------|
| Architecture | SigLIP (Sigmoid Loss Image-Language Pretraining) Vision Transformer |
| Version | 2.0.0 |
| Input Size | 224×224 pixels (center crop) |
| Output | MultiArray [1, 2] - probabilities for [AI, Human] |
| Hardware | Neural Engine when available (MLModelConfiguration.computeUnits = .all) |
| Timeout | 2.0 seconds |

**Output Interpretation:**
- Index [0,0] = AI-generated probability
- Index [0,1] = Human/authentic probability
- Score = AI probability (0-1)

**Backup Model:** `AIDetector_v1_backup.mlmodelc` (Vision Transformer v1.0 with classification labels)

### Model Loading

```swift
// Lazy loading in MLDetector actor
private var model: VNCoreMLModel?

func preloadModel() async throws {
    let config = MLModelConfiguration()
    config.computeUnits = .all  // Use Neural Engine
    let compiledModel = try await AIDetector.load(configuration: config)
    model = try VNCoreMLModel(for: compiledModel.model)
}
```

## Detectors

All detectors conform to `DetectionResult` protocol and return score (0-1), confidence, and evidence:

### 1. MLDetector (40% weight)
**File:** `Detectors/MLDetector.swift`

- Vision + Core ML with SigLIP Vision Transformer
- Neural Engine acceleration on Apple Silicon
- 224×224 input with center crop scaling
- 2-second timeout with task group race
- Classification: AI-Generated (>70%), AI-Enhanced (50-70%), Authentic (<30%), Uncertain

### 2. ProvenanceChecker (30% weight)
**File:** `Detectors/ProvenanceChecker.swift`

- C2PA content credentials via bundled `c2patool` binary
- Async process execution with 5-second timeout
- Lazy trust list loading from `trust_list.json`
- Shared AI tools list with MetadataAnalyzer (60+ signatures)
- Definitive proof: Valid C2PA + known AI tool = confirmed AI-generated

**Enhanced C2PA Parsing:**
- **AI Generation Info**: Parses `c2pa.ai_generative_info` and `c2pa.synthetic` assertions for explicit AI disclosure
- **Model/Prompt Extraction**: Extracts AI model name, prompt, and generation parameters (cfg_scale, steps, sampler, seed)
- **Ingredient Analysis**: Parses `c2pa.ingredients` to detect AI-generated parent/source images in composites
- **Action Chain Analysis**: Scans provenance chain for AI tool involvement at any step
- **AI Training Detection**: Checks `c2pa.ai_training` assertions for training usage status

**Scoring Logic:**
- 1.0: Definitive AI (valid C2PA + known AI tool or explicit AI assertion)
- 0.95: Explicit AI assertion without valid credentials
- 0.85: AI tool detected in provenance chain
- 0.8: Parent image is AI-generated (composite)
- 0.7: Tampered credentials
- 0.5: No credentials / untrusted signer (neutral)
- 0.2: Valid credentials from non-AI tool (likely authentic)

**Evidence Types:**
- `provenanceCredentialValid` - Valid C2PA credentials found
- `provenanceAIToolDetected` - AI tool detected (tool, chain, or ingredient)
- `provenanceCredentialInvalid` - Invalid or tampered credentials
- `provenanceNoCredentials` - No C2PA credentials present
- `provenanceUntrustedSigner` - Credentials from untrusted signer

### 3. MetadataAnalyzer (15% weight)
**File:** `Detectors/MetadataAnalyzer.swift`

- EXIF/IPTC/TIFF/XMP metadata extraction via ImageIO
- Camera info: make, model, lens, focal length, aperture, ISO, shutter speed
- AI software detection: 60+ tool signatures including DALL-E, Midjourney, Stable Diffusion, Flux, Fooocus, ComfyUI, etc.
- Anomaly detection: missing EXIF in JPEG, future dates, pre-1990 dates, timestamp inconsistencies

**Enhanced Detection Capabilities:**
- **Thumbnail Mismatch**: Compares embedded EXIF thumbnail to main image (>25% difference flagged)
- **Color Profile Analysis**: Detects generic/uncalibrated profiles, camera brand vs profile mismatches
- **JPEG Compression Analysis**: Identifies AI pipeline software (Pillow, PyTorch, OpenCV), unusual JFIF density
- **XMP/IPTC Deep Inspection**: Scans for AI terms (prompts, cfg scale, sampler, seed, etc.) and SD generation parameters

**Anomaly Types:**
- `missingExif` - No EXIF in JPEG file
- `aiToolDetected` - AI software signature found
- `thumbnailMismatch` - Embedded thumbnail differs from main image
- `suspiciousColorProfile` - Generic/mismatched color profile
- `suspiciousQuantization` - AI pipeline software or unusual compression
- `suspiciousXMP` - AI-related terms in metadata

### 4. ForensicAnalyzer (15% weight)
**File:** `Detectors/ForensicAnalyzer.swift`

Combines traditional analysis with FFT-based frequency domain analysis:

**Traditional Analysis (60% of forensic score):**
- **JPEG/Lossy:** Error Level Analysis (recompress at 90%, compute diff, amplify 15×)
- **PNG/Lossless:** Noise pattern analysis (Gaussian blur subtraction, 32×32 block variance)

**FFT Analysis (40% of forensic score):**
- 2D FFT via Accelerate vDSP for hardware acceleration
- Laplacian filter preprocessing to emphasize frequency artifacts
- Radial power spectrum analysis (azimuthal averaging)
- Power law fitting (natural images follow 1/f^n decay, slope typically -2 to -3)
- Spectral peak detection for GAN upsampling artifacts
- Heat map visualization of frequency spectrum

**Evidence Types:**
- `forensicELAInconsistency` - ELA detected suspicious regions
- `forensicNoiseAnomaly` - Noise variance outliers detected
- `forensicFrequencyAnomaly` - Spectrum deviates from 1/f pattern
- `forensicSpectralSignature` - Spectral peaks indicate AI artifacts
- `forensicClean` - No significant artifacts detected

**Constraints:**
- Max resolution: 3840×2160 (downscaled if larger)
- FFT size: Power of 2, max 512×512
- 3-second timeout
- Suspicious region detection via flood-fill connected components

### 5. FaceSwapDetector (20% weight when faces detected)
**File:** `Detectors/FaceSwapDetector.swift`

Detects face-swap and deepfake artifacts using ML-based detection. Uses Apple's Vision framework for face detection, then runs a SigLIP-based deepfake classifier on each detected face.

**Model:** `A-IQ/Resources/DeepfakeDetector.mlmodelc`

| Property | Value |
|----------|-------|
| Source | prithivMLmods/deepfake-detector-model-v1 (Hugging Face) |
| Architecture | SigLIP Vision Transformer |
| Accuracy | ~94% (FaceForensics++ dataset) |
| Input Size | 224×224 pixels (face crop with 20% padding) |
| Output | MultiArray [1, 2] - probabilities for [Fake, Real] |

**Detection Pipeline:**
1. Vision framework detects faces via `VNDetectFaceRectanglesRequest`
2. Each face is cropped with 20% padding for context
3. Face crop resized to 224×224 and fed to DeepfakeDetector model
4. "Fake" probability becomes the face's deepfake score

**Dynamic Weight Behavior:**
- When faces detected: Adds 20% weight, other detectors reduce proportionally (ML 35%, Provenance 25%, Metadata 10%, Forensic 10%)
- When no faces: Returns neutral result (score 0.5, confidence `.unavailable`), original weights apply

**Evidence Types:**
- `faceSwapFaceDetected` - Faces found for analysis
- `faceSwapNoFaces` - No faces detected in image
- `faceSwapTextureAnomaly` - Moderate manipulation indicators (50-70%)
- `faceSwapBlendingArtifact` - High deepfake probability detected (>70%)

**Constraints:**
- 2.5-second timeout with task group race pattern
- Minimum face size: 5% of image area
- Score aggregated from individual face scores, weighted by face area
- Returns per-face analysis with bounds, score, and detected artifacts

## State Management

- **AppState** (`App/AppState.swift`): `@MainActor` ObservableObject with cancellation support and dependency injection
- **SettingsManager** (`Settings/SettingsManager.swift`): `@MainActor` user preferences via `@AppStorage`
- **ResultsStore** (`Storage/ResultsStore.swift`): Actor wrapping SwiftData for history persistence (max 1000 records)

## Data Flow

1. Input via `ImageInputHandler` (file picker, clipboard, drag-drop, folder scan)
2. Creates `ImageSource` enum (`.fileURL`, `.imageData`, `.clipboard`)
3. `AnalysisOrchestrator.analyze()` runs detectors in parallel using `async let`
4. `ResultAggregator` combines scores with weight redistribution and corroboration checking
5. Classification thresholds: <30% authentic, 30-70% uncertain, >70% AI-generated
6. Saved to SwiftData via `AnalysisRecord` model

## Key Types

### Detection Protocol
```swift
protocol DetectionResult {
    var detectorName: String { get }
    var score: Double { get }           // 0 = authentic, 1 = AI-generated
    var confidence: ResultConfidence { get }
    var evidence: [Evidence] { get }
    var error: DetectionError? { get }
}
```

### Result Types
- **AggregatedResult** (`Models/AggregatedResult.swift`): Final analysis with breakdown, evidence, thumbnails
- **SignalBreakdown**: Per-detector contribution with weighted scores
- **AnalysisRecord** (`Models/AnalysisRecord.swift`): SwiftData persistence model

### Classification
```swift
enum OverallClassification {
    case confirmedAIGenerated   // C2PA definitive proof
    case likelyAIGenerated      // > 70%
    case uncertain              // 30-70%
    case likelyAuthentic        // < 30%
}
```

## Concurrency Model

- `AnalysisOrchestrator`, `ResultsStore`, `ImageInputHandler`, `ProvenanceChecker`, `MetadataAnalyzer`, `ForensicAnalyzer`, `FaceSwapDetector` are actors
- `AppState` and `SettingsManager` are `@MainActor` for UI binding
- All detector methods are `async` and run concurrently via `async let`
- `AsyncSemaphore` controls max concurrent analyses (no busy-wait polling)
- Analysis tasks are cancellable via `currentAnalysisTask` in AppState
- Timeout enforcement via task group race pattern

## Logging

Uses OSLog with category-specific loggers:
```swift
private let analysisLogger = Logger(subsystem: "com.aiq.app", category: "Analysis")
```

Categories:
- `Analysis` - Pipeline events, detector results
- `Storage` - Persistence operations
- `Export` - Report generation

## Testing

AppState supports dependency injection for testing:
```swift
init(settingsManager: SettingsManager, orchestrator: AnalysisOrchestrator, inputHandler: ImageInputHandler)
```

## User Settings

**File:** `Settings/SettingsManager.swift`

| Setting | Default | Description |
|---------|---------|-------------|
| sensitivityThreshold | 0.5 | Adjusts score by ±0.1 |
| defaultExportFormat | PDF | PDF or JSON |
| autoAnalyzeOnDrop | true | Auto-analyze dropped files |
| showELAByDefault | false | Show forensic overlay |
| historyRetentionDays | 0 | 0 = forever |
| storeThumbnailsInHistory | true | Store thumbnails (disable for privacy) |

## Required Resources (Not in Repo)

- `AIDetector.mlmodelc`: Compiled Core ML SigLIP model (164MB) → `A-IQ/Resources/`
- `DeepfakeDetector.mlmodelc`: Compiled Core ML deepfake detector (164MB) → `A-IQ/Resources/`
- `c2patool`: C2PA verification binary (34MB) → `A-IQ/Resources/`
- `trust_list.json`: Trusted C2PA signers list → `A-IQ/Resources/`

## External Dependencies

**Apple Frameworks Only:**
- SwiftUI, SwiftData, Vision, Core ML, CoreGraphics, ImageIO, Accelerate, CoreImage, AppKit, PDFKit, OSLog, UniformTypeIdentifiers

**Bundled Executables:**
- `c2patool` from Content Authenticity Initiative

No third-party CocoaPods or Swift Package Manager dependencies.

## Recent Code Improvements (v1.2 - January 2026)

### New Features (v1.2)

1. **Grok/xAI Detection**: Added comprehensive detection for xAI's Grok image generator
   - New patterns: `Grok`, `xAI`, `Aurora`, `Grok Imagine`, `Grok 2`, `Grok-2`, `grok-2-image`
   - Note: xAI does not implement C2PA credentials; detection relies on ML analysis and metadata signatures

### Critical Fixes (v1.1)

1. **Graceful Error Handling**: Replaced `fatalError` in app initialization with user-friendly error dialogs. Uses `NSApplication.terminate()` with an unreachable `fatalError()` to satisfy Swift's definite initialization requirement for `modelContainer`.
2. **Complete Menu Implementation**: All menu commands (Open File, Open Folder, Paste, Export) now functional
3. **Proper Task Cancellation**: Improved cancellation handling using `Task.checkCancellation()` with proper error distinction
4. **Comprehensive Error Handling**: Added try/catch blocks throughout analysis methods with user feedback
5. **Input Validation**: Added file size limits (100MB) and symlink resolution for security
6. **Constants Extraction**: Created `AnalysisConstants.swift` to centralize configuration values

### Code Quality Improvements (v1.1)

- **Removed Dead Code**: Fixed unused variables in `MetadataAnalyzer.swift` (`hasMatchingProfile`, `hasCameraProfile`)
- **Consistent Optional Handling**: Added generic `buildContribution<T: DetectionResult>` helper in `ResultAggregator.swift`
- **Standardized Default Values**: Use `AnalysisConstants.neutralScore` (0.5) instead of magic numbers
- **Error Handling Consistency**: Standardized error handling patterns across async methods
- **Security Enhancements**: Path traversal protection, file size validation, input sanitization
- **Code Organization**: Centralized constants for easier maintenance and configuration
- **User Experience**: Better error messages, graceful cancellation, functional menu commands

### Key Helper Methods

**ResultAggregator.buildContribution** - Creates SignalContribution from optional DetectionResult:
```swift
private func buildContribution<T: DetectionResult>(from result: T?, weight: Double) -> SignalContribution {
    SignalContribution(
        rawScore: result?.score ?? AnalysisConstants.neutralScore,
        weight: weight,
        isAvailable: result?.isSuccessful ?? false,
        confidence: result?.confidence ?? .unavailable
    )
}
```

### Files Modified

1. `App/AIQApp.swift` - Graceful error handling
2. `App/AppCommands.swift` - Complete menu implementation
3. `App/AppState.swift` - Error handling and cancellation
4. `Input/ImageInputHandler.swift` - Input validation and security
5. `Analysis/AnalysisOrchestrator.swift` - Constants usage
6. `Analysis/ResultAggregator.swift` - Constants usage, buildContribution helper
7. `Detectors/MetadataAnalyzer.swift` - Removed unused variables
8. `Models/AnalysisConstants.swift` - Centralized constants file

### AnalysisConstants Reference

**File:** `Models/AnalysisConstants.swift`

| Constant | Value | Usage |
|----------|-------|-------|
| `maxConcurrentAnalyses` | 4 | Semaphore limit in AnalysisOrchestrator |
| `memoryThresholdBytes` | 2GB | Memory throttling threshold |
| `memoryConstrainedDelayMs` | 500 | Pause when memory constrained |
| `thumbnailSize` | 256×256 | Result thumbnail dimensions |
| `neutralScore` | 0.5 | Default score for unavailable detectors |
| `decisiveThreshold` | 0.1 | Distance from neutral to be "decisive" |
| `minDisplayWeight` | 0.05 | Minimum weight for non-decisive detectors |
| `likelyAuthenticThreshold` | 0.30 | Score below = Likely Authentic |
| `likelyAIGeneratedThreshold` | 0.70 | Score above = Likely AI-Generated |
| `mlRedistributionShare` | 0.7 | ML gets 70% of redistributed weight |
| `mlDominanceBoost` | 0.05 | Extra weight for high-confidence ML |
| `mlAmplificationWithCorroboration` | 1.0 | Full trust with corroboration |
| `mlAmplificationWithoutCorroboration` | 0.85 | High trust without corroboration |
| `maxFileSizeBytes` | 100MB | Maximum input file size |
