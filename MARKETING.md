# A-IQ Marketing Guide

## Positioning Statement

**A-IQ** is a native macOS app that detects AI-generated images using five parallel analysis methods—all processed locally on your Mac. No uploads, no subscriptions, no cloud dependency.

---

## Key Differentiators

1. **100% Local Processing** - Images never leave your Mac
2. **Five Detection Methods** - ML classification, C2PA provenance, metadata analysis, forensic analysis (ELA/FFT), deepfake detection
3. **No Subscription** - One-time purchase
4. **Native macOS** - Fast, integrated, works offline
5. **Batch Processing** - Analyze entire folders at once

---

## Target Audiences

| Audience | Pain Point | Message |
|----------|------------|---------|
| Journalists | Verify images before publishing | "Trust but verify. Detect AI-generated images before they become misinformation." |
| Photographers | Prove their work is authentic | "Protect your authentic work in an age of synthetic media." |
| Content Moderators | Scale verification | "Batch analyze hundreds of images. Local processing means no API limits." |
| Researchers | Analyze AI imagery trends | "Five detection signals with detailed breakdowns for rigorous analysis." |
| Privacy-Conscious Users | Don't want to upload images | "Your images stay on your Mac. Always." |

---

## Hacker News - Show HN Post

### Title Options
- "Show HN: A-IQ – Detect AI-generated images locally on macOS (5 detection methods)"
- "Show HN: I built a macOS app that detects AI images using ML, C2PA, ELA, and FFT analysis"

### Post Body

```
I built A-IQ to answer the question "is this image AI-generated?" without uploading anything to the cloud.

It combines five detection methods running in parallel:

1. **ML Detection (40%)** - SigLIP Vision Transformer trained on AI vs. real images
2. **C2PA Provenance (30%)** - Checks Content Credentials from Adobe/Leica/etc. and detects 60+ AI tool signatures
3. **Metadata Analysis (15%)** - EXIF anomalies, AI software signatures, thumbnail mismatches
4. **Forensic Analysis (15%)** - Error Level Analysis + FFT frequency spectrum (AI images often lack natural 1/f noise patterns)
5. **Deepfake Detection (20% when faces present)** - Face-specific model trained on FaceForensics++

Everything runs locally using Core ML and Apple's Neural Engine. No network calls, no API keys, no subscriptions.

Built with SwiftUI, Swift Concurrency (actors for thread safety), and Apple's Vision/Accelerate frameworks.

Feedback welcome—especially on detection accuracy edge cases.

Link: [gumroad link]
```

---

## Product Hunt

### Tagline
"Detect AI-generated images locally on your Mac"

### Description
A-IQ analyzes images for signs of AI generation using five parallel detection methods—all processed locally on your Mac. No uploads, no subscriptions, no cloud dependency.

Drop an image and instantly see:
- Overall AI probability score with confidence breakdown
- ML classification from a Vision Transformer model
- C2PA content credential verification
- EXIF/metadata anomaly detection
- Forensic analysis (Error Level Analysis + frequency spectrum)
- Deepfake detection for images with faces

Perfect for journalists verifying sources, photographers protecting authentic work, and anyone who needs to know if an image is real.

### First Comment (as maker)
```
Hey Product Hunt! I'm the maker of A-IQ.

I built this because I was tired of uploading sensitive images to web-based AI detectors. As a privacy-focused Mac user, I wanted something that:

1. Never phones home
2. Combines multiple detection signals (no single method is foolproof)
3. Explains *why* it thinks something is AI-generated

The hardest part was balancing the five detection methods—each has strengths and weaknesses. C2PA is definitive when present but rare. ML is fast but can be fooled. Forensic analysis catches edits but has false positives on heavily compressed images.

I'd love feedback on accuracy. If you have images that fool it (false positives or negatives), I'm very interested!
```

---

## Reddit Posts

### r/macapps

**Title:** A-IQ - Native macOS app for detecting AI-generated images (local processing, no uploads)

```
I built A-IQ to detect AI-generated images entirely on-device. No cloud, no subscriptions.

**Features:**
- 5 detection methods: ML model, C2PA verification, metadata analysis, forensic analysis, deepfake detection
- Batch processing for folders
- Detailed signal breakdown explaining *why* something flagged
- Native SwiftUI, runs on Apple Silicon Neural Engine

**Why local?** I didn't want to upload client images to random web APIs. Everything stays on your Mac.

$9.99 on Gumroad: [link]

Happy to answer questions about how the detection works.
```

### r/photography

**Title:** Tool for photographers to verify image authenticity / detect AI-generated images

```
With AI-generated images becoming indistinguishable from photos, I built a tool to help verify authenticity.

A-IQ analyzes images using:
- EXIF metadata (real cameras leave fingerprints AI tools don't)
- C2PA Content Credentials (Adobe's provenance standard)
- Error Level Analysis (compression artifact patterns)
- Frequency analysis (natural images follow specific spectral patterns)
- ML classification

It's useful for:
- Verifying submitted images are real photographs
- Checking if stock images are AI-generated
- Protecting your own work's authenticity claims

Runs locally on macOS—images never uploaded anywhere.

[link]
```

### r/StableDiffusion

**Title:** I built a tool to detect AI-generated images - feedback on evasion techniques welcome

```
I know this might seem counterintuitive to post here, but I built A-IQ to detect AI-generated images using 5 methods:

1. ML classifier (SigLIP-based)
2. C2PA/metadata signatures (catches images with AI tool fingerprints)
3. EXIF anomalies (missing camera data, suspicious timestamps)
4. Error Level Analysis
5. FFT frequency analysis (AI images often deviate from natural 1/f spectral decay)

I'm genuinely curious about edge cases. What techniques do you think would evade detection?

- Adding fake EXIF?
- Specific post-processing?
- img2img from real photo bases?

Not trying to start an arms race—just want to make detection more robust for legitimate use cases (journalism, content moderation).

[link if interested]
```

---

## Twitter/X Threads

### Launch Thread

```
1/ I built an app to detect AI-generated images.

It runs 100% locally on your Mac. No uploads. No API calls. No subscriptions.

Here's how it works: [screenshot of app]

2/ Most AI detectors use a single method. A-IQ uses five:

- ML Vision Transformer
- C2PA Content Credentials
- EXIF/Metadata analysis
- Error Level Analysis
- FFT frequency spectrum
- Deepfake detection (for faces)

Each catches different things.

3/ Why does local processing matter?

If you're a journalist verifying a leaked image, you can't upload it to a random website.

If you're a lawyer reviewing evidence, cloud uploads are a liability.

A-IQ never phones home.

4/ The forensic analysis is my favorite part.

It runs FFT (Fast Fourier Transform) on the image. Natural photos follow a "1/f" frequency pattern. AI images often don't.

[screenshot of frequency spectrum view]

5/ C2PA detection checks for Content Credentials—a provenance standard supported by Adobe, Leica, Nikon, and others.

When present, it's definitive proof of origin. A-IQ also detects 60+ AI tool signatures in metadata.

6/ Available now for macOS:

[gumroad link]

$9.99, no subscription.

If you verify images for work—journalism, content moderation, legal, research—I'd love your feedback on accuracy.
```

### Engagement Posts (for ongoing marketing)

**When AI image news breaks:**
```
Another satisfying day of [news topic] discourse.

Meanwhile, here's what A-IQ shows for that image:
[screenshot]

AI detection is hard. No single signal is definitive. That's why A-IQ combines five methods.

[link]
```

**Technical deep-dive:**
```
How do you detect AI-generated images?

One method: FFT frequency analysis.

Natural photos have characteristic "1/f" spectral decay. AI-generated images often have unusual frequency patterns—artifacts from the generation process.

A-IQ analyzes this automatically: [screenshot]
```

---

## Blog Post Outline

### Title: "How A-IQ Detects AI-Generated Images: A Technical Deep Dive"

1. **Introduction**
   - The problem: AI images are everywhere
   - Why detection matters (misinformation, fraud, authenticity)

2. **Why No Single Method Works**
   - ML classifiers can be fooled
   - Metadata can be stripped/faked
   - Forensic analysis has false positives
   - Solution: combine multiple signals

3. **The Five Detection Methods**

   **3.1 ML Classification**
   - SigLIP Vision Transformer architecture
   - Trained on AI vs. authentic images
   - Runs on Apple Neural Engine

   **3.2 C2PA Content Credentials**
   - What is C2PA? (Adobe-led provenance standard)
   - How A-IQ verifies credential chains
   - Detecting 60+ AI tool signatures

   **3.3 Metadata Analysis**
   - EXIF fingerprints of real cameras
   - AI tool signatures in XMP/IPTC
   - Anomaly detection (future dates, missing data)
   - Thumbnail mismatch detection

   **3.4 Forensic Analysis**
   - Error Level Analysis (ELA) explained
   - FFT frequency spectrum analysis
   - Why AI images deviate from 1/f patterns

   **3.5 Deepfake Detection**
   - Face-specific model (FaceForensics++ trained)
   - Why faces need special handling

4. **Combining Signals**
   - Weighted scoring system
   - Dynamic weights (faces present vs. not)
   - Corroboration between methods

5. **Limitations & Honest Assessment**
   - What A-IQ catches well
   - What's still hard (img2img, heavy post-processing)
   - The ongoing arms race

6. **Conclusion**
   - Download link
   - Call for feedback

---

## Email for Press/Influencer Outreach

**Subject:** AI image detection tool for [their audience] - A-IQ for macOS

```
Hi [Name],

I built A-IQ, a macOS app that detects AI-generated images using five analysis methods—all processed locally, never uploaded to the cloud.

I thought it might be relevant for [their audience/publication] because [specific reason].

**What makes it different:**
- 100% local processing (privacy-first)
- Combines ML, C2PA verification, metadata analysis, forensic analysis, and deepfake detection
- Shows *why* an image flagged, not just a score
- No subscription, works offline

I'd be happy to provide a review copy or answer questions about how the detection works technically.

[Link]

Best,
[Your name]
```

---

## Gumroad Page Copy

### Title
A-IQ - AI Image Detection for macOS

### Short Description
Detect AI-generated images locally on your Mac. Five detection methods, zero uploads.

### Full Description

**Is that image real?**

A-IQ answers this question using five parallel detection methods—all running locally on your Mac. Your images never leave your device.

**Five Detection Methods:**

1. **ML Detection** - Vision Transformer model classifies AI vs. authentic images
2. **C2PA Provenance** - Verifies Content Credentials and detects 60+ AI tool signatures
3. **Metadata Analysis** - Checks EXIF anomalies, camera fingerprints, AI software traces
4. **Forensic Analysis** - Error Level Analysis + FFT frequency spectrum analysis
5. **Deepfake Detection** - Specialized model for face-swap and synthetic face detection

**Why Local Processing Matters:**

- Journalists: Verify sensitive images without uploading to third parties
- Lawyers: Analyze evidence without cloud liability
- Photographers: Check submissions privately
- Everyone: Your images, your device, your privacy

**Features:**

- Drag & drop or batch analyze entire folders
- Detailed signal breakdown for each detection method
- Export reports as PDF or JSON
- Native macOS app, optimized for Apple Silicon
- Works completely offline

**Requirements:**
- macOS 14.0 or later
- Apple Silicon or Intel Mac

**One-time purchase. No subscription. No account required.**

---

## Visual Assets Checklist

- [ ] App icon (1024x1024 for marketing)
- [ ] Screenshot: Main interface with analysis result
- [ ] Screenshot: Batch results view
- [ ] Screenshot: Signal breakdown detail
- [ ] Screenshot: ELA visualization
- [ ] GIF: Drag and drop → analysis flow
- [ ] GIF: Batch processing
- [ ] Comparison graphic: "Web detectors vs. A-IQ" (upload vs. local)
- [ ] Social card (1200x630) for link previews

---

## Launch Checklist

- [ ] Gumroad page finalized with all copy
- [ ] Screenshots and GIFs uploaded
- [ ] Product Hunt scheduled
- [ ] Hacker News post drafted
- [ ] Reddit posts drafted (don't post all same day)
- [ ] Twitter launch thread ready
- [ ] Press list compiled (Mac blogs, photography sites, journalism tools)
- [ ] Review copies ready to send

---

## Metrics to Track

- Gumroad views → conversion rate
- Traffic sources (which channels work)
- Reddit/HN upvotes and comments
- Twitter impressions and link clicks
- Press coverage mentions

---

## Responding to Objections

**"Web detectors are free"**
→ "Free detectors require uploading your images to their servers. A-IQ processes everything locally—your images never leave your Mac."

**"AI detection doesn't work"**
→ "No single method is foolproof. That's why A-IQ combines five detection methods. Each catches different artifacts. The combination is more robust than any single approach."

**"I can tell AI images myself"**
→ "For obvious cases, sure. But AI is improving fast. A-IQ catches subtle signals humans miss—metadata fingerprints, frequency spectrum anomalies, compression artifacts."

**"Too expensive"**
→ "It's a one-time purchase with no subscription. Compare to web APIs that charge per image or monthly fees."
