# A-IQ: AI Image Detection for macOS

A native macOS application that analyzes images to determine whether they are AI-generated, AI-enhanced, or authentic photographs. All processing happens locally on your Mac with no data sent to external servers.

## Features

### Multi-Signal Detection
A-IQ combines four independent detection methods for reliable results:

| Signal | Weight | Method |
|--------|--------|--------|
| **ML Detection** | 40% | SigLIP Vision Transformer neural network |
| **Provenance** | 30% | C2PA content credentials verification |
| **Metadata** | 15% | EXIF/IPTC anomaly analysis |
| **Forensics** | 15% | Error Level Analysis (ELA) |

### Key Capabilities
- **Privacy-First**: All processing happens locally. No images uploaded to any server.
- **Offline Capable**: Works without an internet connection.
- **Native Performance**: Optimized for Apple Silicon with Neural Engine acceleration.
- **Batch Analysis**: Analyze entire folders of images.
- **Export Reports**: Generate PDF or JSON reports of findings.
- **History**: Browse and search past analysis results.

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon or Intel Mac

## Installation

1. Download the latest release from the Releases page
2. Move A-IQ.app to your Applications folder
3. Launch A-IQ

## Usage

### Analyzing Images

| Method | How |
|--------|-----|
| **Drag and Drop** | Drag any image onto the A-IQ window |
| **Open File** | Click "Open File" or press `Cmd+O` |
| **Paste** | Copy an image and press `Cmd+V` |
| **Batch Analysis** | Select "Open Folder" to analyze multiple images |

### Understanding Results

A-IQ provides a confidence score from 0-100%:

| Score | Classification | Meaning |
|-------|---------------|---------|
| < 30% | **Likely Authentic** | Low probability of AI generation |
| 30-70% | **Uncertain** | Review recommended |
| > 70% | **Likely AI-Generated** | High probability of AI generation |
| 100% | **Confirmed AI-Generated** | C2PA credentials prove AI origin |

### Signal Breakdown

Each analysis shows weighted contributions from four independent detectors:

- **ML Detection (40%)**: SigLIP Vision Transformer trained on modern AI generators (DALL-E, Midjourney, Stable Diffusion, etc.)
- **Provenance (30%)**: Checks C2PA content credentials for digital signatures from known AI tools
- **Metadata (15%)**: Analyzes EXIF/IPTC/XMP for 60+ AI software signatures, thumbnail mismatches, color profile anomalies, and embedded generation parameters
- **Forensics (15%)**: Error Level Analysis detects compression inconsistencies and manipulation artifacts

## Supported Formats

- JPEG / JPG
- PNG
- HEIC / HEIF
- WebP
- TIFF
- AVIF

## How Detection Works

### ML Detection (SigLIP Model)
The core ML detector uses a SigLIP (Sigmoid Loss Image-Language Pretraining) Vision Transformer model. Images are resized to 224x224 pixels and processed through the neural network, which outputs probabilities for AI-generated vs. human-created content.

**Model Details:**
- Architecture: Vision Transformer (ViT)
- Input: 224x224 pixels (center crop)
- Output: [AI probability, Human probability]
- Hardware: Neural Engine on Apple Silicon, GPU fallback on Intel

### Provenance (C2PA)
Checks for Content Credentials embedded in images using the C2PA standard. When valid credentials from a trusted signer indicate an AI tool was used (DALL-E, Midjourney, Stable Diffusion, Adobe Firefly, etc.), this provides definitive proof of AI generation.

### Metadata Analysis
Examines EXIF, IPTC, TIFF, and XMP metadata using multiple detection methods:

**AI Software Detection (60+ signatures):**
- DALL-E, Midjourney, Stable Diffusion, Flux, Fooocus, ComfyUI, and many more
- Detects AI pipeline software (Pillow, PyTorch, OpenCV, ImageMagick)

**Anomaly Detection:**
- Missing EXIF data in JPEG files (common in AI-generated images)
- Timestamp anomalies (future dates, pre-digital era dates)
- Absence of camera information

**Advanced Checks:**
- Thumbnail mismatch detection (compares embedded thumbnail to main image)
- Color profile analysis (generic profiles, camera/profile brand mismatches)
- XMP/IPTC deep inspection (AI prompts, generation parameters, seed values)

### Forensic Analysis
Performs Error Level Analysis (ELA) on JPEG images:
1. Recompresses the image at 90% quality
2. Computes pixel-by-pixel differences
3. Identifies regions with inconsistent compression artifacts
4. AI-generated images often show uniform error levels, while edited photos show localized differences

For PNG/lossless formats, noise pattern analysis detects variance inconsistencies across image blocks.

## Architecture

```
A-IQ/
├── App/           # Application entry point and state
├── Analysis/      # Orchestration and result aggregation
├── Detectors/     # ML, Provenance, Metadata, Forensic analyzers
├── Models/        # Data structures and protocols
├── Views/         # SwiftUI interface
├── Input/         # Image acquisition (file, clipboard, drag-drop)
├── Storage/       # SwiftData persistence
├── Export/        # PDF/JSON report generation
├── Settings/      # User preferences
└── Resources/     # ML model, c2patool, trust list
```

## Building from Source

### Prerequisites

- Xcode 15.0 or later
- macOS 14.0 SDK

### Build Steps

```bash
# Clone the repository
git clone https://github.com/yourusername/A-IQ.git
cd A-IQ

# Build via command line
xcodebuild build -scheme A-IQ -destination 'platform=macOS'

# Or open in Xcode
open A-IQ.xcodeproj
```

### Required Resources

The following files are required but not included in the repository:

1. **ML Model** (`AIDetector.mlmodelc`)
   - SigLIP Vision Transformer trained for AI detection
   - Place in `A-IQ/Resources/`

2. **c2patool** binary
   - Download from [C2PA releases](https://github.com/contentauth/c2patool/releases)
   - Place in `A-IQ/Resources/`
   - Ensure execute permissions: `chmod +x c2patool`

3. **Trust List** (`trust_list.json`)
   - JSON file listing trusted C2PA signers
   - Place in `A-IQ/Resources/`

## Privacy

A-IQ is designed with privacy as a core principle:

- **No Network Access**: The app makes no network requests
- **Local Processing**: All analysis runs on-device using Core ML
- **No Telemetry**: No usage data or analytics collected
- **No Cloud**: Images never leave your Mac
- **Sandboxed**: Full macOS app sandbox with minimal permissions

## Technical Details

### Concurrency
- Actor-based architecture for thread safety
- Parallel detector execution via `async let`
- Max 4 concurrent analyses with memory throttling (2GB limit)
- Cancellable analysis tasks

### Performance
- Neural Engine acceleration on Apple Silicon
- GPU fallback on Intel Macs
- Large images downscaled to 4K for forensic analysis
- Lazy model loading to reduce startup time

### Storage
- SwiftData for analysis history
- Max 1000 records with automatic cleanup
- JPEG-compressed thumbnails (70% quality)
- Full results stored as JSON

## License

MIT License - See LICENSE file for details.

## Acknowledgments

- [C2PA](https://c2pa.org/) for the content provenance standard
- [Content Authenticity Initiative](https://contentauthenticity.org/) for c2patool
- [SigLIP](https://arxiv.org/abs/2303.15343) research for the vision transformer architecture
- Research community for advances in synthetic media detection

## Contributing

Contributions are welcome! Please read CONTRIBUTING.md for guidelines.
