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


# ── Training configuration ──

EPOCHS = 20
BATCH_SIZE = 256
LEARNING_RATE = 1e-3
MODEL_PATH = os.path.join(os.path.dirname(__file__), "ternary_mnist_qat.h5")


# ── Build, compile, and train ──

if __name__ == "__main__":
    print("=" * 60)
    print("Ternary Edge-RV: QAT Training Pipeline")
    print("=" * 60)

    model = build_ternary_mlp()

    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=LEARNING_RATE),
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"],
    )

    # Strong L1 on all quant layers
    l1_loss_total = 0
    for layer in model.layers:
        if isinstance(layer, lq.layers.QuantDense):
            l1_loss_total += tf.reduce_sum(tf.abs(layer.kernel))
    model.add_loss(lambda: l1_loss_total * 1.0)

    model.summary()

    print("\n[1/3] Training QAT model with ste_tern...")
    model.fit(
        x_train, y_train,
        epochs=EPOCHS,
        batch_size=BATCH_SIZE,
        validation_split=0.1,
        verbose=1,
    )

    print("\n[2/3] Evaluating on test set...")
    loss, acc = model.evaluate(x_test, y_test, verbose=0)
    print(f"Test Accuracy: {acc * 100:.2f}%")

    print(f"\n[3/3] Saving model to {MODEL_PATH}...")
    model.save(MODEL_PATH)
    print("Done.")

    # ── Verify ternary constraint ──
    print("\n[Verification] Checking ternary weight distribution...")
    quant_layers = [l for l in model.layers if isinstance(l, lq.layers.QuantDense)]
    for layer in quant_layers:
        w = layer.get_weights()[0]
        # The sign function simulates the ternarization: sign(w) -> -1, 0, +1
        ternary = np.where(np.abs(w) < 0.05, 0, np.where(w > 0, 1, -1))
        unique, counts = np.unique(ternary, return_counts=True)
        total = len(ternary.flatten())
        zeros_pct = counts[unique == 0][0] / total * 100 if 0 in unique else 0
        dist = dict(zip(unique, counts))
        print(f"  {layer.name}: {dist}  |  zeros: {zeros_pct:.1f}%")
