import os
os.environ["TF_USE_LEGACY_KERAS"] = "1"

import numpy as np
import tensorflow as tf


(x_train, y_train), (x_test, y_test) = tf.keras.datasets.mnist.load_data()
x_train = x_train.reshape(-1, 784).astype("float32") / 255.0
x_test  = x_test.reshape(-1, 784).astype("float32") / 255.0

model = tf.keras.models.Sequential([
    tf.keras.layers.Dense(1024, activation="relu", use_bias=False, input_shape=(784,)),
    tf.keras.layers.BatchNormalization(),
    tf.keras.layers.Dense(512, activation="relu", use_bias=False),
    tf.keras.layers.BatchNormalization(),
    tf.keras.layers.Dense(256, activation="relu", use_bias=False),
    tf.keras.layers.BatchNormalization(),
    tf.keras.layers.Dense(10, activation="softmax"),
])

model.compile(optimizer="adam", loss="sparse_categorical_crossentropy", metrics=["accuracy"])
model.fit(x_train, y_train, epochs=15, batch_size=256, validation_split=0.1, verbose=0)

loss, acc = model.evaluate(x_test, y_test, verbose=0)
print(f"Float32: {acc*100:.2f}%\n")

def ternarize(w, t):
    pos_mask = w > t
    neg_mask = w < -t
    
    survivors = np.abs(w[pos_mask | neg_mask])
    if survivors.size > 0:
        alpha = np.mean(survivors)
    else:
        alpha = 1.0
        
    out = np.zeros_like(w)
    out[pos_mask] = alpha
    out[neg_mask] = -alpha
    return out.astype("float32")

for threshold in [0.1, 0.2, 0.3, 0.4, 0.5]:
    
    original_weights = []
    dense_layers = [l for l in model.layers if isinstance(l, tf.keras.layers.Dense)][:-1]
    
    for layer in dense_layers:
        w = layer.get_weights()[0]
        original_weights.append(w.copy())
        layer.set_weights([ternarize(w, threshold)])

    loss, acc = model.evaluate(x_test, y_test, verbose=0)
    
    
    for layer, w in zip(dense_layers, original_weights):
        layer.set_weights([w])

    print(f"Threshold={threshold:.1f} → Acurácia: {acc*100:.2f}%")