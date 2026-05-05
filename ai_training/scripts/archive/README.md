# Archived PTQ Scripts

These scripts use Post-Training Quantization (PTQ) and were replaced by the QAT pipeline.

They are kept here for reference and comparison purposes.

## Why were they replaced?

- **PTQ does not use STE**: The network is trained in float32 first, then quantized after. This means the network never learns to handle quantization noise.
- **Scaling factor α**: The `ternarize()` function returns weights `{-α, 0, +α}` where `α = mean(survivors)`. This means the hardware still needs multipliers, breaking the "multiplierless" premise.
- **QAT trains with ternary weights**: The new pipeline uses Larq's `ste_tern` quantizer, which applies the Straight-Through Estimator during training. The network learns to work with strict `{-1, 0, +1}` weights — no scaling factor needed.

## Files

- `train_ternary_mnist.py` — Float32 training + PTQ threshold sweep
- `find_threshold.py` — PTQ with BatchNorm recalibration and std-based thresholds
