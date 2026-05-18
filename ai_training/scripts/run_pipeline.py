#!/usr/bin/env python3
"""
Unified QAT Pipeline for Ternary Edge-RV.

Runs the complete flow:
  1. Train ternary MLP with QAT (Larq + STE)
  2. Validate weights are strictly {-1, 0, +1}
  3. Pack weights into uint32_t arrays
  4. Generate weights.h for the C user application

Usage:
    python run_pipeline.py [--epochs N] [--lr LR] [--skip-train]
"""

import os
os.environ["TF_USE_LEGACY_KERAS"] = "1"

import sys
import argparse
import numpy as np
import tensorflow as tf
import larq as lq

from train_qat_mnist import build_ternary_mlp
from generate_weights_h import generate_weights_header


SCRIPT_DIR = os.path.dirname(__file__)
MODEL_PATH = os.path.join(SCRIPT_DIR, "ternary_mnist_qat.h5")
HEADER_PATH = os.path.join(SCRIPT_DIR, "..", "..", "software", "user_app", "weights.h")


def load_data():
    (x_train, y_train), (x_test, y_test) = tf.keras.datasets.mnist.load_data()
    x_train = x_train.reshape(-1, 784).astype("float32") / 255.0
    x_test  = x_test.reshape(-1, 784).astype("float32") / 255.0
    return x_train, y_train, x_test, y_test


def verify_ternary(model):
    print("\n[Verification] Checking weight distribution...")
    all_ternary = True
    for layer in model.layers:
        if isinstance(layer, tf.keras.layers.Dense) and not isinstance(layer, lq.layers.QuantDense):
            continue
        if isinstance(layer, lq.layers.QuantDense):
            w = layer.get_weights()[0]
            unique = np.unique(np.round(w, decimals=4))
            valid = set(np.round(unique, decimals=4)).issubset({-1.0, 0.0, 1.0})
            status = "OK" if valid else "FAIL"
            if not valid:
                all_ternary = False
            print(f"  {layer.name}: unique={unique.tolist()} [{status}]")
    return all_ternary


def run_pipeline(epochs=20, lr=1e-3, skip_train=False):
    print("=" * 60)
    print("Ternary Edge-RV: Unified QAT Pipeline")
    print("=" * 60)

    x_train, y_train, x_test, y_test = load_data()

    if skip_train and os.path.exists(MODEL_PATH):
        print("\n[1/3] Loading pre-trained model...")
        model = tf.keras.models.load_model(MODEL_PATH, compile=False)
        model.compile(
            optimizer=tf.keras.optimizers.Adam(learning_rate=lr),
            loss="sparse_categorical_crossentropy",
            metrics=["accuracy"],
        )
    else:
        print("\n[1/4] Training QAT model...")
        model = build_ternary_mlp()
        model.compile(
            optimizer=tf.keras.optimizers.Adam(learning_rate=lr),
            loss="sparse_categorical_crossentropy",
            metrics=["accuracy"],
        )
        model.fit(
            x_train, y_train,
            epochs=epochs,
            batch_size=256,
            validation_split=0.1,
            verbose=1,
        )
        print(f"\nSaving model to {MODEL_PATH}...")
        model.save(MODEL_PATH)

    print("\n[2/4] Evaluating on test set...")
    loss, acc = model.evaluate(x_test, y_test, verbose=0)
    print(f"Test Accuracy: {acc * 100:.2f}%")

    print("\n[3/4] Verifying ternary constraint...")
    ok = verify_ternary(model)
    if not ok:
        print("WARNING: Some weights are not strictly ternary!")
        print("The NPU expects {-1, 0, +1}. Results may be incorrect.")

    print("\n[4/4] Generating weights.h...")
    os.makedirs(os.path.dirname(HEADER_PATH), exist_ok=True)
    generate_weights_header(MODEL_PATH, HEADER_PATH)

    print("\n" + "=" * 60)
    print("Pipeline complete!")
    print(f"  Model: {MODEL_PATH}")
    print(f"  Header: {HEADER_PATH}")
    print(f"  Accuracy: {acc * 100:.2f}%")
    print("=" * 60)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Ternary Edge-RV QAT Pipeline")
    parser.add_argument("--epochs", type=int, default=20, help="Number of training epochs")
    parser.add_argument("--lr", type=float, default=1e-3, help="Learning rate")
    parser.add_argument("--skip-train", action="store_true", help="Skip training, use saved model")
    args = parser.parse_args()

    run_pipeline(epochs=args.epochs, lr=args.lr, skip_train=args.skip_train)
