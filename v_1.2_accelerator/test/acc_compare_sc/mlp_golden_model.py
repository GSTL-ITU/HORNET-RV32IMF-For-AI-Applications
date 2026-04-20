#!/usr/bin/env python3
"""
MLP Golden Model — FPGA Accelerator Verification
=================================================
Reads weight_init.mem and bias_init.mem, runs inference layer by layer,
and dumps intermediate ping-pong RAM contents in 1024-bit row format
so you can diff directly against Vivado simulation memory dumps.

Weight .mem layout (reverse-engineered from generate_weights_mem()):
  - One 1024-bit line = 32 x IEEE-754 floats, stored REVERSED within the line
    i.e. bytes on disk: [w31][w30]...[w1][w0]
  - Lines are written: for o in range(out_dim): for block in range(blocks_per_neuron)
    So neuron 0's weights come first, contiguously, then neuron 1, etc.
  - in_dim is zero-padded to next multiple of 32

Bias .mem layout:
  - One 32-bit hex value per line, all layers concatenated in order

MAC operation (mirrors hardware):
  y[o] = sum(x[i] * w[o][i] for i in range(in_dim)) + b[o]

Output format per layer (mirrors ping-pong RAM):
  Row 0:  n31  n30 ... n0       (MSB to LSB within line)
  Row 1:  n63  n62 ... n32
  ...
  Row k:  n[32k+31] ... n[32k]

Network: 122 -> 256 -> 128 -> 64 -> 32 -> 5
"""

import struct
import sys
import re

# ==============================================================================
# ARCHITECTURE
# ==============================================================================
ARCHITECTURE = [
    {"in": 122, "out": 256},
    {"in": 256, "out": 128},
    {"in": 128, "out":  64},
    {"in":  64, "out":  32},
    {"in":  32, "out":   5},
]

WEIGHT_FILE = "weight_init.mem"
BIAS_FILE   = "bias_init.mem"

# ==============================================================================
# IEEE-754 HELPERS
# ==============================================================================

def hex8_to_float(h: str) -> float:
    """8-char little-endian hex string -> Python float."""
    return struct.unpack('<f', struct.pack('<I', int(h, 16)))[0]

def float_to_hex8(f: float) -> str:
    """Python float -> 8-char little-endian hex string."""
    return f"{struct.unpack('<I', struct.pack('<f', f))[0]:08x}"

# ==============================================================================
# LOAD WEIGHTS
# ==============================================================================

def load_weights(filepath: str):
    """
    Returns: weights[layer_idx][neuron_o][input_i]

    Reverse-engineers generate_weights_mem():
      for o in range(out_dim):
        for block in range(blocks_per_neuron):
          line = 32 floats for inputs [block*32 .. block*32+31], stored REVERSED
    """
    with open(filepath) as fh:
        lines = [ln.strip() for ln in fh if ln.strip()]

    all_layers = []
    line_cursor = 0

    for layer_idx, cfg in enumerate(ARCHITECTURE):
        in_dim   = cfg["in"]
        out_dim  = cfg["out"]
        padded   = ((in_dim + 31) // 32) * 32
        n_blocks = padded // 32

        layer_weights = []   # shape: [out_dim][in_dim]

        for o in range(out_dim):
            neuron_w = []
            for blk in range(n_blocks):
                line = lines[line_cursor]
                line_cursor += 1

                # 256 hex chars = 32 floats, stored REVERSED in the line:
                # position of float k (0=first/lowest input index in this block):
                #   string offset = (31 - k) * 8
                block_floats = []
                for k in range(32):
                    chunk = line[(31 - k) * 8 : (31 - k) * 8 + 8]
                    block_floats.append(hex8_to_float(chunk))

                neuron_w.extend(block_floats)   # now ordered w[0], w[1], ..., w[31]

            # Trim padding zeros — keep only real input weights
            layer_weights.append(neuron_w[:in_dim])

        all_layers.append(layer_weights)
        print(f"  Layer {layer_idx}: {out_dim} neurons x {in_dim} weights "
              f"| {n_blocks} lines/neuron | {out_dim * n_blocks} lines consumed")

    if line_cursor != len(lines):
        print(f"\n[WARNING] Consumed {line_cursor} lines but file has {len(lines)}.")
        print(f"          Check that ARCHITECTURE matches your export script.")

    return all_layers

# ==============================================================================
# LOAD BIASES
# ==============================================================================

def load_biases(filepath: str):
    """Returns: biases[layer_idx][neuron_o]"""
    with open(filepath) as fh:
        lines = [ln.strip() for ln in fh if ln.strip()]

    all_biases = []
    cursor = 0
    for cfg in ARCHITECTURE:
        out_dim = cfg["out"]
        layer_b = [hex8_to_float(lines[cursor + o]) for o in range(out_dim)]
        all_biases.append(layer_b)
        cursor += out_dim

    return all_biases

# ==============================================================================
# INPUT PARSER  (mirrors clean_line() in your C code)
# ==============================================================================

def parse_input(text: str, expected: int):
    """Accept C-array literal { 0.0f, 1.0f, ... } or plain whitespace/comma floats."""
    cleaned = re.sub(r'[{};,f]', ' ', text)
    values  = []
    for tok in cleaned.split():
        try:
            values.append(float(tok))
        except ValueError:
            pass
    if len(values) != expected:
        raise ValueError(f"Got {len(values)} values, expected {expected}.")
    return values

# ==============================================================================
# INFERENCE
# ==============================================================================

def relu(x):
    return x if x > 0.0 else 0.0

def layer_forward(x, weights, biases, in_dim, out_dim, apply_relu):
    """
    y[o] = ReLU( sum(x[i] * weights[o][i], i=0..in_dim-1) + biases[o] )
    Mirrors your hardware: neuron-by-neuron MAC.
    """
    y = []
    for o in range(out_dim):
        acc = biases[o]
        for i in range(in_dim):
            acc += x[i] * weights[o][i]
        y.append(relu(acc) if apply_relu else acc)
    return y

# ==============================================================================
# OUTPUT FORMATTER  —  1024-bit rows, reversed within row (mirrors ping-pong RAM)
# ==============================================================================

def format_ping_pong_rows(activations: list, out_dim: int):
    """
    Pack activations into 1024-bit rows of 32 floats each.
    Within each row, neurons are stored high-index first (reversed):
      Row r string = hex(n[r*32+31]) hex(n[r*32+30]) ... hex(n[r*32+0])

    Matches the bit ordering used in generate_weights_mem() and your RAM.
    Returns list of (row_index, neuron_slice, hex_string).
    """
    n_rows = (out_dim + 31) // 32
    rows = []
    for r in range(n_rows):
        lo = r * 32
        hi = lo + 31
        # collect 32 values (zero-pad if out_dim not multiple of 32)
        vals = []
        for k in range(32):
            idx = lo + k
            vals.append(activations[idx] if idx < out_dim else 0.0)
        # reversed: n[31]..n[0] within this block
        hexline = "".join(float_to_hex8(vals[k]) for k in range(31, -1, -1))
        rows.append((r, lo, hi, vals, hexline))
    return rows

# ==============================================================================
# PRINT HELPERS
# ==============================================================================

def print_layer_dump(layer_idx, activations, out_dim, is_output=False):
    label = "OUTPUT LOGITS (no ReLU — argmax in SW)" if is_output else "POST-ReLU"
    sep = "=" * 74
    print(f"\n{sep}")
    print(f"  LAYER {layer_idx}  |  {label}  |  {out_dim} neurons")
    print(sep)

    # Individual neuron values
    print("\n  Neuron float values:")
    for i, v in enumerate(activations):
        print(f"    n[{i:4d}] = {v:+14.6f}   hex: {float_to_hex8(v)}")

    # Ping-pong RAM rows
    rows = format_ping_pong_rows(activations, out_dim)
    n_rows = len(rows)
    print(f"\n  Ping-pong RAM dump  ({n_rows} x 1024-bit rows):")
    print(f"  Format per row: n[hi]...n[lo]  (MSB=high neuron index, LSB=low)\n")
    for r_idx, lo, hi, vals, hexline in rows:
        actual_hi = min(hi, out_dim - 1)
        print(f"  Row {r_idx:2d}  [n{actual_hi}..n{lo}]:")
        print(f"    {hexline}")
        # Annotated breakdown
        parts = []
        for k in range(31, -1, -1):
            idx = lo + k
            if idx < out_dim:
                parts.append(f"n{idx}={float_to_hex8(vals[k])}")
        print(f"    ({' | '.join(parts)})")

# ==============================================================================
# MAIN
# ==============================================================================

def main():
    print("=" * 74)
    print("  MLP Golden Model  —  FPGA Ping-Pong RAM Verification")
    print("=" * 74)

    # Load weights & biases
    print(f"\nLoading '{WEIGHT_FILE}' ...")
    try:
        all_weights = load_weights(WEIGHT_FILE)
    except FileNotFoundError:
        print(f"[ERROR] '{WEIGHT_FILE}' not found. Run this script from the same directory.")
        sys.exit(1)

    print(f"\nLoading '{BIAS_FILE}' ...")
    try:
        all_biases = load_biases(BIAS_FILE)
        print(f"  OK")
    except FileNotFoundError:
        print(f"[ERROR] '{BIAS_FILE}' not found.")
        sys.exit(1)

    # Read input
    in_dim = ARCHITECTURE[0]["in"]
    print(f"\n{'='*74}")
    print(f"  Paste input vector ({in_dim} floats), C-array format.")
    print(f"  Press Enter twice when done.")
    print(f"{'='*74}\n")

    collected = []
    try:
        while True:
            line = input()
            if line == "" and collected:
                break
            collected.append(line)
    except EOFError:
        pass

    try:
        x = parse_input(" ".join(collected), in_dim)
    except ValueError as e:
        print(f"[ERROR] {e}")
        sys.exit(1)

    print(f"\n  Parsed {len(x)} input values OK.")

    # Show input as ping-pong rows too (useful for layer 0 debugging)
    print(f"\n  Input ping-pong RAM rows ({((in_dim+31)//32)} x 1024-bit):")
    for r_idx, lo, hi, vals, hexline in format_ping_pong_rows(x, in_dim):
        actual_hi = min(hi, in_dim - 1)
        print(f"  Row {r_idx:2d}  [x{actual_hi}..x{lo}]:")
        print(f"    {hexline}")

    # Forward pass
    print(f"\n\n{'='*74}")
    print(f"  LAYER-BY-LAYER FORWARD PASS")
    print(f"{'='*74}")

    activations = x
    for layer_idx, cfg in enumerate(ARCHITECTURE):
        is_last = (layer_idx == len(ARCHITECTURE) - 1)
        activations = layer_forward(
            activations,
            all_weights[layer_idx],
            all_biases[layer_idx],
            cfg["in"], cfg["out"],
            apply_relu=not is_last
        )
        print_layer_dump(layer_idx, activations, cfg["out"], is_output=is_last)

    predicted = activations.index(max(activations))
    print(f"\n{'='*74}")
    print(f"  FINAL PREDICTION: Class {predicted}")
    print(f"{'='*74}\n")


if __name__ == "__main__":
    main()