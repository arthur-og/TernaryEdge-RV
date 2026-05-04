import os
os.environ["TF_USE_LEGACY_KERAS"] = "1"

import numpy as np
import tensorflow as tf

# 1. Carregamento e Preparação dos Dados (Essencial para definir x_train)
(x_train, y_train), (x_test, y_test) = tf.keras.datasets.mnist.load_data()
x_train = x_train.reshape(-1, 784).astype("float32") / 255.0
x_test  = x_test.reshape(-1, 784).astype("float32") / 255.0

# 2. Definição do Modelo
model = tf.keras.models.Sequential([
    tf.keras.layers.Dense(1024, activation="relu", use_bias=False, input_shape=(784,)),
    tf.keras.layers.BatchNormalization(),
    tf.keras.layers.Dense(512, activation="relu", use_bias=False),
    tf.keras.layers.BatchNormalization(),
    tf.keras.layers.Dense(256, activation="relu", use_bias=False),
    tf.keras.layers.BatchNormalization(),
    tf.keras.layers.Dense(10, activation="softmax"),
])

# 3. Funções de Suporte (Definidas antes do uso)
def ternarize(w, t):
    pos_mask = w > t
    neg_mask = w < -t
    survivors = np.abs(w[pos_mask | neg_mask])
    alpha = np.mean(survivors) if survivors.size > 0 else 1.0
    out = np.zeros_like(w)
    out[pos_mask] = alpha
    out[neg_mask] = -alpha
    return out.astype("float32")

def recalibrate_bn(model, x_calib):
    bn_layers = [l for l in model.layers if isinstance(l, tf.keras.layers.BatchNormalization)]
    for layer in bn_layers:
        layer.momentum = 0.0 
    model.predict(x_calib, batch_size=128, verbose=0)
    for layer in bn_layers:
        layer.momentum = 0.99

# 4. Treino Inicial
print("Treinando modelo Float32...")
model.compile(optimizer="adam", loss="sparse_categorical_crossentropy", metrics=["accuracy"])
model.fit(x_train, y_train, epochs=15, batch_size=256, validation_split=0.1, verbose=1)

loss, acc = model.evaluate(x_test, y_test, verbose=0)
print(f"\nAcurácia Original (Float32): {acc*100:.2f}%\n")

# 5. Calibração e Teste de Thresholds
x_calib = x_train[:2000] # Agora x_train está definido com certeza

print("Iniciando testes de ternarização com calibração...\n")

for factor in [0.1, 0.3, 0.5, 0.7, 0.9]:
    dense_layers = [l for l in model.layers if isinstance(l, tf.keras.layers.Dense)][:-1]
    bn_layers = [l for l in model.layers if isinstance(l, tf.keras.layers.BatchNormalization)]
    
    orig_dense = [l.get_weights()[0] for l in dense_layers]
    orig_bn = [l.get_weights() for l in bn_layers]
    
    for layer in dense_layers:
        w = layer.get_weights()[0]
        t = factor * np.std(w)
        layer.set_weights([ternarize(w, t)])

    recalibrate_bn(model, x_calib)

    loss, acc_ternary = model.evaluate(x_test, y_test, verbose=0)
    print(f"Fator Std={factor:.1f} | Acurácia Ternária: {acc_ternary*100:.2f}%")

    # Restaura pesos originais para o próximo teste
    for layer, w in zip(dense_layers, orig_dense):
        layer.set_weights([w])
    for layer, w in zip(bn_layers, orig_bn):
        layer.set_weights(w)