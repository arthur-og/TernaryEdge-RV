"""
Weight Packing Utility for Ternary Edge-RV NPU.

Converts ternary weights {-1, 0, +1} into packed uint32_t arrays.
Each 32-bit word holds 16 weights encoded as 2-bit values:
  -1 -> 0b11 (3)
   0 -> 0b00 (0)
  +1 -> 0b01 (1)

Little-Endian ordering: weight[0] goes into the LSB of the first word.
"""

import numpy as np


TernaryEncoding = {
    -1: 0b11,
     0: 0b00,
    +1: 0b01,
}


def encode_ternary(value: float) -> int:
    encoded = int(np.round(value))
    return TernaryEncoding.get(encoded, 0b00)


def pack_weights(weight_matrix: np.ndarray) -> list[int]:
    flat = weight_matrix.flatten().astype("float32")
    encoded = [encode_ternary(w) for w in flat]

    packed_words = []
    for i in range(0, len(encoded), 16):
        chunk = encoded[i : i + 16]
        word = 0
        for j, val in enumerate(chunk):
            word |= (val << (j * 2))
        packed_words.append(word)

    return packed_words


def unpack_weights(packed_words: list[int], shape: tuple) -> np.ndarray:
    flat = []
    for word in packed_words:
        for j in range(16):
            bits = (word >> (j * 2)) & 0b11
            if bits == 0b01:
                flat.append(1.0)
            elif bits == 0b11:
                flat.append(-1.0)
            else:
                flat.append(0.0)

    flat = flat[: int(np.prod(shape))]
    return np.array(flat, dtype="float32").reshape(shape)
