#!/usr/bin/env python3
"""Bit-exact reference model for the autonomous NPU v2.

The model intentionally uses only Python integers.  It mirrors the RTL
contract: signed INT8 inputs, signed INT32 accumulation, output-major packed
ternary weights, integer requantization and INT8 hidden activations.
"""

from __future__ import annotations

import random

ENCODE = {0: 0b00, 1: 0b01, -1: 0b11}
DECODE = {0b00: 0, 0b01: 1, 0b11: -1}
INVALID_WEIGHT = 0b10


def signed(value: int, width: int) -> int:
    mask = (1 << width) - 1
    value &= mask
    return value - (1 << width) if value & (1 << (width - 1)) else value


def signed_int8(value: int) -> int:
    return signed(value, 8)


def signed_int32(value: int) -> int:
    return signed(value, 32)


def ternary_mac(activation: int, weight_2bit: int) -> int:
    """Return one 9-bit signed PE result; reserved encoding produces zero."""
    activation = signed_int8(activation)
    if weight_2bit == 0b01:
        return signed(activation, 9)
    if weight_2bit == 0b11:
        return signed(-activation, 9)
    return 0


def pack_16_weights(encoded_2bit: list[int]) -> int:
    word = 0
    for index, value in enumerate(encoded_2bit[:16]):
        word |= (value & 0x3) << (2 * index)
    return word


def pack_weights(weights: list[int]) -> list[int]:
    return [
        pack_16_weights([ENCODE[value] for value in weights[offset:offset + 16]])
        for offset in range(0, len(weights), 16)
    ]


def unpack_weight(word: int, index: int) -> int:
    return (word >> (index * 2)) & 0x3


def unpack_weights(words: list[int], count: int) -> list[int]:
    return [unpack_weight(words[i // 16], i % 16) for i in range(count)]


def requantize(accumulator: int, bias: int, multiplier: int, shift: int) -> int:
    """RTL convention: round-to-nearest, ties away from zero, then saturate."""
    value = signed_int32(accumulator) + signed_int32(bias)
    product = value * signed_int32(multiplier)
    if shift:
        rounding = 1 << (shift - 1)
        product = product + rounding if product >= 0 else product - rounding
        product >>= shift
    return max(-(1 << 31), min((1 << 31) - 1, product))


def saturate_int8(value: int, relu: bool) -> int:
    if relu and value < 0:
        return 0
    return max(-128, min(127, value))


def layer_forward(
    activations: list[int],
    weights: list[list[int]],
    biases: list[int] | None = None,
    multipliers: list[int] | None = None,
    shift: int = 0,
    relu: bool = False,
) -> list[int]:
    """Compute one output-major layer, including postprocessing."""
    input_values = [signed_int8(value) for value in activations]
    biases = biases or [0] * len(weights)
    multipliers = multipliers or [1] * len(weights)
    outputs: list[int] = []
    for output_index, row in enumerate(weights):
        accumulator = 0
        for input_index, weight in enumerate(row):
            encoded = ENCODE[weight] if weight in ENCODE else weight
            accumulator = signed_int32(
                accumulator + ternary_mac(input_values[input_index], encoded)
            )
        value = requantize(
            accumulator, biases[output_index], multipliers[output_index], shift
        )
        outputs.append(saturate_int8(value, relu))
    return outputs


def network_forward(activations: list[int], layers: list[dict]) -> list[int]:
    """Run all layers; final layers may request INT32 logits."""
    current = [signed_int8(value) for value in activations]
    for layer_index, layer in enumerate(layers):
        output = layer_forward(
            current,
            layer["weights"],
            layer.get("biases"),
            layer.get("multipliers"),
            layer.get("shift", 0),
            layer.get("relu", False),
        )
        if layer_index == len(layers) - 1:
            current = [
                requantize(
                    sum(
                        ternary_mac(current[i], ENCODE[row[i]])
                        for i in range(len(current))
                    ),
                    (layer.get("biases") or [0] * len(output))[j],
                    (layer.get("multipliers") or [1] * len(output))[j],
                    layer.get("shift", 0),
                )
                for j, row in enumerate(layer["weights"])
            ]
        else:
            current = output
    return current


def balanced_sum(values: list[int]) -> int:
    if len(values) == 1:
        return values[0]
    middle = len(values) // 2
    return balanced_sum(values[:middle]) + balanced_sum(values[middle:])


def test_pe_extremes() -> bool:
    cases = [(-128, 0b01, -128), (-128, 0b11, 128), (127, 0b11, -127), (0, 0b01, 0)]
    return all(ternary_mac(act, weight) == expected for act, weight, expected in cases)


def test_packing() -> bool:
    values = [1, -1, 0, 1, -1, 0, 1, -1] * 2
    words = pack_weights(values)
    return unpack_weights(words, len(values)) == [ENCODE[value] for value in values]


def test_tree_equivalent() -> bool:
    random.seed(42)
    for _ in range(32):
        activations = [random.randint(-128, 127) for _ in range(64)]
        weights = [random.choice([-1, 0, 1]) for _ in range(64)]
        products = [
            ternary_mac(act, ENCODE[weight])
            for act, weight in zip(activations, weights)
        ]
        expected = sum(products)
        if expected != balanced_sum(products):
            return False
    return True


def test_partial_batch() -> bool:
    activations = list(range(-35, 35))
    weights = [[1] * 70, [-1] * 70]
    output = layer_forward(activations, weights, relu=False)
    expected = sum(activations), -sum(activations)
    return tuple(output) == expected


def test_multilayer() -> bool:
    layers = [
        {
            "weights": [[1] * 8, [-1] * 8, [1, -1] * 4, [1, 0, 1, 0, 1, 0, 1, 0], [0] * 8],
            "biases": [1, 100, 0, -20, 7],
            "relu": True,
        },
        {
            "weights": [[1] * 5, [1, -1, 1, 0, 0], [-1] * 5],
            "biases": [-10, 2, 0],
            "relu": False,
        },
    ]
    return network_forward(list(range(1, 9)), layers) == [98, -25, -108]


def test_saturation() -> bool:
    positive = layer_forward([127] * 64, [[1] * 64], relu=True)
    negative = layer_forward([-128] * 64, [[1] * 64], relu=False)
    return positive == [127] and negative == [-128]


def main() -> int:
    tests = [
        ("PE signed extremes", test_pe_extremes),
        ("2-bit weight packing", test_packing),
        ("64-lane reduction reference", test_tree_equivalent),
        ("partial 70-input layer", test_partial_batch),
        ("multilayer 8->5->3", test_multilayer),
        ("INT8 saturation", test_saturation),
    ]
    failures = 0
    for name, test in tests:
        passed = test()
        print(f"{'PASS' if passed else 'FAIL'}: {name}")
        failures += not passed
    print(f"Summary: {len(tests) - failures} passed, {failures} failed")
    return int(failures != 0)


if __name__ == "__main__":
    raise SystemExit(main())
