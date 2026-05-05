"""
QAT Training Script for Ternary Edge-RV
Uses Larq for Quantization-Aware Training with Straight-Through Estimator (STE).
Produces strictly ternary weights {-1, 0, +1} — no scaling factors.
"""

import os
os.environ["TF_USE_LEGACY_KERAS"] = "1"

import numpy as np
import tensorflow as tf
import larq as lq


# ── Dataset loading and preprocessing ──

(x_train, y_train), (x_test, y_test) = tf.keras.datasets.mnist.load_data()

x_train = x_train.reshape(-1, 784).astype("float32") / 255.0
x_test  = x_test.reshape(-1, 784).astype("float32") / 255.0


# ── Ternary MLP model definition ──

def build_ternary_mlp(input_shape=(784,), num_classes=10):
    model = tf.keras.models.Sequential([
        lq.layers.QuantDense(
            1024,
            input_shape=input_shape,
            use_bias=False,
            kernel_quantizer="ste_tern",
            kernel_constraint="weight_clip",
        ),
        tf.keras.layers.BatchNormalization(),
        tf.keras.layers.Activation("relu"),

        lq.layers.QuantDense(
            512,
            use_bias=False,
            kernel_quantizer="ste_tern",
            kernel_constraint="weight_clip",
        ),
        tf.keras.layers.BatchNormalization(),
        tf.keras.layers.Activation("relu"),

        lq.layers.QuantDense(
            256,
            use_bias=False,
            kernel_quantizer="ste_tern",
            kernel_constraint="weight_clip",
        ),
        tf.keras.layers.BatchNormalization(),
        tf.keras.layers.Activation("relu"),

        tf.keras.layers.Dense(num_classes, activation="softmax"),
    ])
    return model
