import re
import struct

# --- CONFIGURATION ---
HEADER_FILE = "MLP_weights_folded.h" 
WEIGHTS_OUT = "weight_init.mem"
BIAS_OUT = "bias_init.mem"

# Network architecture (Input Dim, Output Dim)
ARCHITECTURE = {
    "layer0": {"in": 122, "out": 256},
    "layer1": {"in": 256, "out": 128},
    "layer2": {"in": 128, "out": 64},
    "layer3": {"in": 64,  "out": 32},
    "layer4": {"in": 32,  "out": 5}
}

def float_to_hex(f):
    """Converts a standard Python float to a 32-bit IEEE-754 hex string."""
    # Pack as little-endian float, unpack as little-endian unsigned int
    packed = struct.pack('<f', f)
    unpacked = struct.unpack('<I', packed)[0]
    return f"{unpacked:08x}"

def parse_c_header(filepath):
    """Parses the C header and extracts weights and biases into dictionaries."""
    with open(filepath, 'r') as file:
        content = file.read()

    # Regex to find arrays: const float name[size] = { values };
    pattern = re.compile(r'const\s+float\s+(\w+)_(\w+)\[\d+\]\s*=\s*\{(.*?)\};', re.DOTALL)
    matches = pattern.findall(content)

    data = {"weights": {}, "biases": {}}
    
    for layer_name, param_type, values_str in matches:
        # Clean up the string, split by comma, remove 'f' suffix and whitespace
        raw_values = [v.replace('f', '').strip() for v in values_str.split(',')]
        # Filter out empty strings that might occur from trailing commas
        floats = [float(v) for v in raw_values if v]
        
        data[param_type][layer_name] = floats
        print(f"Extracted {len(floats)} values for {layer_name}_{param_type}")

    return data

def generate_weights_mem(weights_dict):
    """Transposes, pads, and packs weights into 1024-bit hex strings."""
    mem_lines = []
    
    for i in range(5):
        layer_name = f"layer{i}"
        if layer_name not in weights_dict:
            continue
            
        weights = weights_dict[layer_name]
        in_dim = ARCHITECTURE[layer_name]["in"]
        out_dim = ARCHITECTURE[layer_name]["out"]
        
        # Hardware requirement: pack in multiples of 32
        padded_in_dim = ((in_dim + 31) // 32) * 32
            
        for neuron_idx in range(out_dim): # The 'o' loop in C
            neuron_weights = []
            
            # 1. Gather all weights for THIS specific neuron (Transposition)
            for in_idx in range(in_dim): # The 'i' loop in C
                # Stride exactly like the C code: i * out_dim + o
                flat_index = (in_idx * out_dim) + neuron_idx
                neuron_weights.append(weights[flat_index])
            
            # 2. Zero-pad to a multiple of 32
            padding_needed = padded_in_dim - in_dim
            neuron_weights.extend([0.0] * padding_needed)
            
            # 3. Chunk into blocks of 32 and format as 1024-bit lines
            for j in range(0, padded_in_dim, 32):
                block = neuron_weights[j : j + 32]
                # Hardware expects [31] [30] ... [1] [0]
                hex_block = "".join([float_to_hex(w) for w in reversed(block)])
                mem_lines.append(hex_block)
                
    return mem_lines

def generate_bias_mem(biases_dict):
    """Converts biases to 32-bit hex strings, one per line."""
    mem_lines = []
    
    for i in range(5):
        layer_name = f"layer{i}"
        if layer_name not in biases_dict:
            continue
            
        for bias in biases_dict[layer_name]:
            mem_lines.append(float_to_hex(bias))
            
    return mem_lines

if __name__ == "__main__":
    print("Parsing C Header...")
    network_data = parse_c_header(HEADER_FILE)
    
    print("\nGenerating weights_init.mem...")
    weights_mem = generate_weights_mem(network_data["weights"])
    with open(WEIGHTS_OUT, 'w') as f:
        f.write('\n'.join(weights_mem))
    print(f"-> Wrote {len(weights_mem)} lines (1024-bit) to {WEIGHTS_OUT}")
    
    print("\nGenerating bias_init.mem...")
    bias_mem = generate_bias_mem(network_data["biases"])
    with open(BIAS_OUT, 'w') as f:
        f.write('\n'.join(bias_mem))
    print(f"-> Wrote {len(bias_mem)} lines (32-bit) to {BIAS_OUT}")
    
    print("\nExtraction complete! Your MACs are ready to be fed.")