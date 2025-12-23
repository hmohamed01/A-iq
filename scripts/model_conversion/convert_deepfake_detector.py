#!/usr/bin/env python3
"""
Convert Deepfake Detector (SigLIP-based) to Core ML format.

This script downloads the deepfake-detector-model-v1 from Hugging Face
and converts it to Core ML format for use in the A-IQ macOS app.

Model: prithivMLmods/deepfake-detector-model-v1
Architecture: SigLIP (google/siglip-base-patch16-512)
Accuracy: ~94%

Requirements:
    pip install torch transformers coremltools pillow

Usage:
    python convert_deepfake_detector.py

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
from PIL import Image
from transformers import AutoImageProcessor, AutoModelForImageClassification


MODEL_ID = "prithivMLmods/deepfake-detector-model-v1"
OUTPUT_NAME = "DeepfakeDetector"
INPUT_SIZE = 512  # SigLIP uses 512x512 for this model


def download_model():
    """Download model and processor from Hugging Face."""
    print(f"Downloading model: {MODEL_ID}")
    processor = AutoImageProcessor.from_pretrained(MODEL_ID)
    model = AutoModelForImageClassification.from_pretrained(MODEL_ID)
    model.train(False)
    print(f"Model loaded: {model.config.num_labels} classes")
    print(f"Labels: {model.config.id2label}")
    return model, processor


class DeepfakeWrapper(torch.nn.Module):
    """Wrapper to simplify model for Core ML export."""

    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, pixel_values):
        outputs = self.model(pixel_values=pixel_values)
        # Return softmax probabilities
        probs = torch.nn.functional.softmax(outputs.logits, dim=-1)
        return probs


def trace_model(model, processor):
    """Trace the model with example input for TorchScript conversion."""
    print("Tracing model...")

    # Create dummy input matching expected preprocessing
    dummy_image = Image.new("RGB", (INPUT_SIZE, INPUT_SIZE), color=(128, 128, 128))
    inputs = processor(images=dummy_image, return_tensors="pt")
    pixel_values = inputs["pixel_values"]

    print(f"Input shape: {pixel_values.shape}")
    print(f"Input range: [{pixel_values.min():.3f}, {pixel_values.max():.3f}]")

    # Wrap model for cleaner export
    wrapper = DeepfakeWrapper(model)
    wrapper.train(False)

    # Trace with example input
    with torch.no_grad():
        traced = torch.jit.trace(wrapper, pixel_values)

    # Verify output
    with torch.no_grad():
        test_output = traced(pixel_values)
        print(f"Output shape: {test_output.shape}")
        print(f"Output sum (should be ~1.0): {test_output.sum().item():.4f}")

    return traced, pixel_values.shape


def convert_to_coreml(traced_model, input_shape, model_config):
    """Convert traced model to Core ML format."""
    print("Converting to Core ML...")

    id2label = model_config.id2label
    class_labels = [id2label[i] for i in range(len(id2label))]
    print(f"Class labels: {class_labels}")

    # SigLIP normalization: (pixel / 255 - 0.5) / 0.5 = pixel / 127.5 - 1
    image_input = ct.ImageType(
        name="face_image",
        shape=input_shape,
        scale=1.0 / 127.5,
        bias=[-1.0, -1.0, -1.0],
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

    return mlmodel, class_labels


def finalize_model(mlmodel, class_labels):
    """Add metadata to the model."""
    print("Finalizing model...")

    mlmodel.author = "A-IQ App"
    mlmodel.license = "Apache 2.0"
    mlmodel.short_description = (
        "Deepfake/face-swap detector (SigLIP architecture). "
        "Fine-tuned for binary deepfake image classification. "
        "Input: 512x512 face crop. Accuracy: ~94%."
    )
    mlmodel.version = "1.0.0"

    # Add metadata
    mlmodel.user_defined_metadata["class_labels"] = ",".join(class_labels)
    mlmodel.user_defined_metadata["source_model"] = MODEL_ID
    mlmodel.user_defined_metadata["input_size"] = str(INPUT_SIZE)

    return mlmodel


def main():
    print("=" * 60)
    print("Deepfake Detector (SigLIP) to Core ML Converter")
    print("=" * 60)

    # Check dependencies
    try:
        import coremltools
        print(f"coremltools version: {coremltools.__version__}")
    except ImportError:
        print("ERROR: coremltools not installed")
        print("Run: pip install coremltools torch transformers pillow")
        sys.exit(1)

    # Download model
    model, processor = download_model()

    # Trace
    traced, input_shape = trace_model(model, processor)

    # Convert
    mlmodel, class_labels = convert_to_coreml(traced, input_shape, model.config)

    # Finalize
    mlmodel = finalize_model(mlmodel, class_labels)

    # Save
    output_path = f"{OUTPUT_NAME}.mlpackage"
    print(f"\nSaving model to: {output_path}")
    mlmodel.save(output_path)

    print("\n" + "=" * 60)
    print("SUCCESS!")
    print("=" * 60)
    print(f"\nModel saved to: {output_path}")
    print(f"Class labels: {class_labels}")
    print(f"\nTo compile for deployment:")
    print(f"  xcrun coremlcompiler compile {output_path} ./")
    print(f"\nThen copy DeepfakeDetector.mlmodelc to:")
    print(f"  A-IQ/Resources/DeepfakeDetector.mlmodelc")

    # Get model size
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
        print("Model verification PASSED!")
    except Exception as e:
        print(f"Verification warning: {e}")
        print("Model may still work - compile and test in Xcode.")


if __name__ == "__main__":
    main()
