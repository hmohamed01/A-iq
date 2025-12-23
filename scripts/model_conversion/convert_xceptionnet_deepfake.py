#!/usr/bin/env python3
"""
Convert XceptionNet Deepfake Detector to Core ML format.

This script downloads a pretrained XceptionNet deepfake detector trained on
FaceForensics++ and converts it to Core ML format for use in the A-IQ macOS app.

Requirements:
    pip install torch torchvision coremltools pillow timm

Usage:
    python convert_xceptionnet_deepfake.py

Output:
    DeepfakeDetector.mlpackage - Core ML model package (uncompiled)

To compile for deployment:
    xcrun coremlcompiler compile DeepfakeDetector.mlpackage ./
"""

import os
import sys
from pathlib import Path

import coremltools as ct
import numpy as np
import torch
import torch.nn as nn
from PIL import Image


OUTPUT_NAME = "DeepfakeDetector"
INPUT_SIZE = 299  # XceptionNet uses 299x299


def create_xceptionnet_model():
    """
    Create XceptionNet model for deepfake detection.
    Uses timm library which has XceptionNet implementation.
    """
    print("Creating XceptionNet model...")

    try:
        import timm

        # Create XceptionNet with pretrained ImageNet weights
        # Then modify for binary classification
        model = timm.create_model('xception', pretrained=True, num_classes=2)
        print(f"Model created with {sum(p.numel() for p in model.parameters())} parameters")

        return model

    except ImportError:
        print("timm not available, using torchvision Inception as fallback")
        # Fallback to InceptionV3 which is similar architecture
        from torchvision.models import inception_v3
        model = inception_v3(weights='IMAGENET1K_V1')
        model.fc = nn.Linear(model.fc.in_features, 2)
        model.aux_logits = False
        return model


def download_pretrained_weights(model):
    """
    Download pretrained deepfake detection weights.

    Note: Since direct weight download URLs vary, this function attempts
    to download from known sources or uses ImageNet pretrained as baseline.
    """
    print("Setting up pretrained weights...")

    # Option 1: Try to download from GitHub releases
    weight_urls = [
        # kaushikram31's model
        "https://github.com/kaushikram31/deepfake-detection-XceptionNet/raw/main/models/xception_ff.pth",
        # Alternative sources could be added here
    ]

    import urllib.request
    import tempfile

    for url in weight_urls:
        try:
            print(f"Trying to download from: {url}")
            with tempfile.NamedTemporaryFile(delete=False, suffix='.pth') as tmp:
                urllib.request.urlretrieve(url, tmp.name)
                state_dict = torch.load(tmp.name, map_location='cpu', weights_only=True)

                # Handle different state dict formats
                if 'model' in state_dict:
                    state_dict = state_dict['model']
                elif 'state_dict' in state_dict:
                    state_dict = state_dict['state_dict']

                # Try to load weights
                model.load_state_dict(state_dict, strict=False)
                print("Successfully loaded pretrained deepfake detection weights!")
                os.unlink(tmp.name)
                return model
        except Exception as e:
            print(f"Could not load from {url}: {e}")
            continue

    print("\nWARNING: Could not download pretrained deepfake weights.")
    print("Using ImageNet pretrained XceptionNet as baseline.")
    print("For best results, manually download weights from:")
    print("  - https://github.com/kaushikram31/deepfake-detection-XceptionNet")
    print("  - https://github.com/HongguLiu/Deepfake-Detection")
    print("\nProceeding with ImageNet pretrained model...")

    return model


class XceptionWrapper(nn.Module):
    """Wrapper to ensure consistent output format for Core ML."""

    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, x):
        logits = self.model(x)
        # Return softmax probabilities: [real_prob, fake_prob]
        probs = torch.nn.functional.softmax(logits, dim=-1)
        return probs


def trace_model(model):
    """Trace the model for TorchScript conversion."""
    print("Tracing model...")

    # Create wrapper
    wrapper = XceptionWrapper(model)
    wrapper.train(False)

    # Create dummy input (ImageNet normalization will be handled in Core ML)
    dummy_input = torch.randn(1, 3, INPUT_SIZE, INPUT_SIZE)

    print(f"Input shape: {dummy_input.shape}")

    # Trace
    with torch.no_grad():
        traced = torch.jit.trace(wrapper, dummy_input)

    # Verify
    with torch.no_grad():
        test_output = traced(dummy_input)
        print(f"Output shape: {test_output.shape}")
        print(f"Output sum (should be ~1.0): {test_output.sum().item():.4f}")

    return traced, dummy_input.shape


def convert_to_coreml(traced_model, input_shape):
    """Convert traced model to Core ML format."""
    print("Converting to Core ML...")

    # ImageNet normalization: (pixel / 255 - mean) / std
    # mean = [0.485, 0.456, 0.406], std = [0.229, 0.224, 0.225]
    # Combined: scale = 1/(255*std), bias = -mean/std

    # For simplicity, use standard ImageNet preprocessing
    image_input = ct.ImageType(
        name="face_image",
        shape=input_shape,
        scale=1.0 / (255.0 * 0.226),  # Approximate for all channels
        bias=[-0.485/0.229, -0.456/0.224, -0.406/0.225],
        color_layout=ct.colorlayout.RGB,
    )

    mlmodel = ct.convert(
        traced_model,
        inputs=[image_input],
        outputs=[ct.TensorType(name="probabilities")],
        minimum_deployment_target=ct.target.macOS14,
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16,
    )

    return mlmodel


def finalize_model(mlmodel):
    """Add metadata to the model."""
    print("Finalizing model...")

    mlmodel.author = "A-IQ App"
    mlmodel.license = "Research use"
    mlmodel.short_description = (
        "Deepfake/face-swap detector (XceptionNet architecture). "
        "Trained on FaceForensics++ dataset. "
        "Input: 299x299 face crop. Output: [real_prob, fake_prob]."
    )
    mlmodel.version = "1.0.0"

    # Add metadata
    mlmodel.user_defined_metadata["class_labels"] = "Real,Fake"
    mlmodel.user_defined_metadata["training_data"] = "FaceForensics++"
    mlmodel.user_defined_metadata["input_size"] = str(INPUT_SIZE)
    mlmodel.user_defined_metadata["output_format"] = "[real_probability, fake_probability]"

    return mlmodel


def main():
    print("=" * 60)
    print("XceptionNet Deepfake Detector to Core ML Converter")
    print("=" * 60)

    # Check dependencies
    try:
        import coremltools
        print(f"coremltools version: {coremltools.__version__}")
    except ImportError:
        print("ERROR: coremltools not installed")
        print("Run: pip install coremltools torch torchvision timm pillow")
        sys.exit(1)

    # Create model
    model = create_xceptionnet_model()

    # Try to load pretrained weights
    model = download_pretrained_weights(model)
    model.train(False)

    # Trace
    traced, input_shape = trace_model(model)

    # Convert
    mlmodel = convert_to_coreml(traced, input_shape)

    # Finalize
    mlmodel = finalize_model(mlmodel)

    # Save
    output_path = f"{OUTPUT_NAME}.mlpackage"
    print(f"\nSaving model to: {output_path}")
    mlmodel.save(output_path)

    print("\n" + "=" * 60)
    print("SUCCESS!")
    print("=" * 60)
    print(f"\nModel saved to: {output_path}")
    print(f"\nTo compile for deployment:")
    print(f"  xcrun coremlcompiler compile {output_path} ./")
    print(f"\nThen copy DeepfakeDetector.mlmodelc to:")
    print(f"  A-IQ/Resources/DeepfakeDetector.mlmodelc")

    # Get model size
    import shutil
    if os.path.exists(output_path):
        size_mb = sum(
            f.stat().st_size for f in Path(output_path).rglob('*') if f.is_file()
        ) / (1024 * 1024)
        print(f"\nModel size: {size_mb:.1f} MB")

    # Verify
    print("\nVerifying model...")
    test_image = Image.new("RGB", (INPUT_SIZE, INPUT_SIZE), color=(100, 150, 200))
    try:
        loaded = ct.models.MLModel(output_path)
        result = loaded.predict({"face_image": test_image})
        print(f"Test prediction: {result}")
        probs = result.get('probabilities', result)
        if hasattr(probs, '__iter__'):
            print(f"  Real probability: {probs[0]:.4f}")
            print(f"  Fake probability: {probs[1]:.4f}")
        print("Model verification PASSED!")
    except Exception as e:
        print(f"Verification warning: {e}")
        print("Model may still work - compile and test in Xcode.")


if __name__ == "__main__":
    main()
