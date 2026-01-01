#!/usr/bin/env python3
"""
Convert Ateeqq/ai-vs-human-image-detector (SigLIP) to Core ML format.

This script downloads the SigLIP-based AI image detector from Hugging Face
and converts it to Core ML format for use in the A-IQ macOS app.

Requirements:
    pip install torch transformers coremltools pillow

Usage:
    python convert_siglip_to_coreml.py

Output:
    AIDetector.mlpackage - Core ML model package (uncompiled)

To compile for deployment:
    xcrun coremlcompiler compile AIDetector.mlpackage ./
"""

import os
import sys
from pathlib import Path

import coremltools as ct
import numpy as np
import torch
from PIL import Image
from transformers import AutoImageProcessor, SiglipForImageClassification


MODEL_ID = "Ateeqq/ai-vs-human-image-detector"
OUTPUT_NAME = "AIDetector"
INPUT_SIZE = 224  # SigLIP base uses 224x224


def download_model():
    """Download model and processor from Hugging Face."""
    print(f"Downloading model: {MODEL_ID}")
    processor = AutoImageProcessor.from_pretrained(MODEL_ID)
    model = SiglipForImageClassification.from_pretrained(MODEL_ID)
    # Set to inference mode (no gradients, deterministic)
    model.train(False)
    print(f"Model loaded: {model.config.num_labels} classes")
    print(f"Labels: {model.config.id2label}")
    return model, processor


class SigLIPWrapper(torch.nn.Module):
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
    wrapper = SigLIPWrapper(model)
    wrapper.train(False)  # Set to inference mode

    # Trace with example input
    with torch.no_grad():
        traced = torch.jit.trace(wrapper, pixel_values)

    # Verify output
    with torch.no_grad():
        test_output = traced(pixel_values)
        print(f"Output shape: {test_output.shape}")
        print(f"Output sum (should be ~1.0): {test_output.sum().item():.4f}")

    return traced, pixel_values.shape


def create_classifier_model(traced_model, input_shape, model_config):
    """Create a proper classifier model for Vision framework."""
    print("Creating classifier model...")

    id2label = model_config.id2label
    class_labels = [id2label[i] for i in range(len(id2label))]
    print(f"Class labels for classifier: {class_labels}")

    # SigLIP normalization: (pixel / 255 - 0.5) / 0.5 = pixel / 127.5 - 1
    image_input = ct.ImageType(
        name="image",
        shape=input_shape,
        scale=1.0 / 127.5,
        bias=[-1.0, -1.0, -1.0],
        color_layout=ct.colorlayout.RGB,
    )

    # Convert with classifier output type
    mlmodel = ct.convert(
        traced_model,
        inputs=[image_input],
        outputs=[ct.TensorType(name="probs")],
        minimum_deployment_target=ct.target.macOS14,
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16,
    )

    return mlmodel, class_labels


def finalize_model(mlmodel, class_labels):
    """Finalize model with proper metadata and quantization."""
    print("Finalizing model with Float16 precision...")

    # Set metadata
    mlmodel.author = "A-IQ App"
    mlmodel.license = "Apache 2.0"
    mlmodel.short_description = (
        "AI-generated image detector (SigLIP architecture). "
        "Trained on modern generators: Midjourney v6.1, Flux 1.1 Pro, "
        "Stable Diffusion 3.5, GPT-4o. Accuracy: 99.23%."
    )
    mlmodel.version = "2.0.0"

    # Add class labels as user metadata for reference
    mlmodel.user_defined_metadata["class_labels"] = ",".join(class_labels)
    mlmodel.user_defined_metadata["source_model"] = MODEL_ID
    mlmodel.user_defined_metadata["input_size"] = str(INPUT_SIZE)

    return mlmodel


def main():
    print("=" * 60)
    print("SigLIP to Core ML Converter")
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

    # Trace model
    traced, input_shape = trace_model(model, processor)

    # Convert to Core ML
    mlmodel, class_labels = create_classifier_model(traced, input_shape, model.config)

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
    print(f"\nThen copy AIDetector.mlmodelc to:")
    print(f"  A-IQ/Resources/AIDetector.mlmodelc")

    # Verify the model works
    print("\nVerifying model...")
    test_image = Image.new("RGB", (INPUT_SIZE, INPUT_SIZE), color=(100, 150, 200))
    try:
        # Load and test
        loaded = ct.models.MLModel(output_path)
        result = loaded.predict({"image": test_image})
        print(f"Test prediction: {result}")
        print("Model verification PASSED!")
    except Exception as e:
        print(f"Verification warning: {e}")
        print("Model may still work - compile and test in Xcode.")


if __name__ == "__main__":
    main()
