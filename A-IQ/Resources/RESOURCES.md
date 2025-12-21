# A-IQ Resources

This directory contains resources bundled with the A-IQ application.

## Required Resources

### 1. AIDetector.mlmodelc (Core ML Model) - INCLUDED

The compiled Core ML model for AI image classification is included.

| Property | Value |
|----------|-------|
| Source | [Ateeqq/ai-vs-human-image-detector](https://huggingface.co/Ateeqq/ai-vs-human-image-detector) |
| Architecture | SigLIP (92.9M parameters) |
| License | Apache 2.0 |
| Accuracy | 99.23% |
| Training Data | Midjourney v6.1, Flux 1.1 Pro, SD 3.5, GPT-4o |
| Input | 224x224 RGB image (Vision framework handles resizing) |
| Output labels | `ai`, `hum` |
| Model Version | 2.0.0 |

**Note:** The previous model (v1.0, dima806/ai_vs_real_image_detection) is backed up as `AIDetector_v1_backup.mlmodelc`.

### 2. c2patool (C2PA Verification Binary) - INCLUDED

The c2patool binary for C2PA provenance verification is included.

| Property | Value |
|----------|-------|
| Source | [contentauth/c2patool](https://github.com/contentauth/c2patool) |
| Version | 0.9.12 |
| License | Apache 2.0 |
| Binary | Universal (Intel + Apple Silicon) |

### 3. trust_list.json (Already Included)

Contains trusted C2PA signers and known AI tool signatures. Edit to add/remove trusted signers.

## Adding Resources to Xcode

1. In Xcode, right-click on the project navigator
2. Select "Add Files to A-IQ..."
3. Select the Resources folder
4. Ensure "Copy items if needed" is checked
5. Ensure "Create folder references" is selected
6. Add to target: A-IQ

## File Checklist

- [x] `AIDetector.mlmodelc/` - Compiled Core ML model directory (included)
- [x] `c2patool` - C2PA verification binary (included)
- [x] `trust_list.json` - Trusted signers list
- [x] `RESOURCES.md` - This file
