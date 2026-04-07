import struct
import numpy as np

# -------------------------------------------------------------------------
# Yardımcı Fonksiyonlar (Artık np.float32 kullanıyor)
# -------------------------------------------------------------------------
def hex_to_float32(hex_str):
    """32-bit IEEE-754 hex string değerini Single Precision numpy float32'ye çevirir."""
    f_val = struct.unpack('<f', struct.pack('<I', int(hex_str, 16)))[0]
    return np.float32(f_val)

def float32_to_hex(f):
    """Numpy float32 değerini 32-bit IEEE-754 hex string'e çevirir."""
    return f"{struct.unpack('<I', struct.pack('<f', f))[0]:08x}"

def adder_tree_sum(vals):
    """
    FPGA'deki Adder Tree (Toplayıcı Ağaç) yapısını simüle eder.
    Sayıları ardışık değil, ikili gruplar halinde (binary tree) ve 
    her adımda 32-bit single precision sınırlarına kırparak toplar.
    """
    if len(vals) == 0:
        return np.float32(0.0)
    
    tree = list(vals)
    while len(tree) > 1:
        next_level = []
        for i in range(0, len(tree), 2):
            if i + 1 < len(tree):
                # İkisini topla ve zorla 32-bit'e kırp
                next_level.append(np.float32(tree[i] + tree[i+1]))
            else:
                next_level.append(tree[i])
        tree = next_level
    return tree[0]

# -------------------------------------------------------------------------
# Parametreler ve Input Verisi
# -------------------------------------------------------------------------
INPUT_DIM = 122
PAD_DIM = 128          # 32'nin katı (122 -> 128)
LAYER_0_NEURONS = 256
LINES_PER_NEURON = PAD_DIM // 32  # Nöron başına 4 satır

# C kodundan aldığımız input verisi
input_data = [
    0.000000, 1.000000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 
    0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 
    0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 
    0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 
    0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 
    0.000000, 1.000000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 
    0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 
    0.000000, 0.000000, 0.000000, 1.000000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 
    0.000000, 0.000000, 0.000000, -0.110249, -0.007762, -0.004919, -0.014089, -0.089486, -0.007736, -0.095076, 
    -0.027023, -0.809262, -0.011664, -0.036652, -0.024437, -0.012385, -0.026180, -0.018610, -0.041221, 0.000000, 
    -0.002817, -0.097531, 1.265346, -0.244204, -0.637209, -0.631929, 2.746403, 2.715365, -1.412415, -0.016930, 
    -0.374560, 0.734343, -0.954389, -1.071933, -0.121485, -0.480197, -0.289103, -0.639532, -0.624871, 2.874410, 
    2.753914
]

# Inputu padding yapıp tamamen np.float32 tipine dönüştürüyoruz
input_padded = [np.float32(val) for val in input_data] + [np.float32(0.0)] * (PAD_DIM - len(input_data))

def generate_rtl_reference():
    try:
        with open("weight_init.mem", "r") as fw:
            weight_lines = fw.read().splitlines()
        
        with open("bias_init.mem", "r") as fb:
            bias_lines = fb.read().splitlines()
    except FileNotFoundError:
        print("HATA: 'weight_init.mem' veya 'bias_init.mem' dosyası bulunamadı.")
        return

    output_file = "layer0_rtl_reference.txt"
    
    with open(output_file, "w") as fout:
        fout.write("=================================================================\n")
        fout.write("     RTL SIMULATION REFERENCE - LAYER 0 (SINGLE PRECISION)       \n")
        fout.write("=================================================================\n\n")

        for neuron_idx in range(LAYER_0_NEURONS):
            w_lines = weight_lines[neuron_idx * LINES_PER_NEURON : (neuron_idx + 1) * LINES_PER_NEURON]
            bias_hex = bias_lines[neuron_idx]
            
            neuron_weights = []
            for line in w_lines:
                chunk_hex = [line[i:i+8] for i in range(0, len(line), 8)]
                chunk_hex.reverse()
                chunk_floats = [hex_to_float32(h) for h in chunk_hex]
                neuron_weights.extend(chunk_floats)

            bias_val = hex_to_float32(bias_hex)

            # MATEMATİKSEL İŞLEMLER (Tamamen FP32)
            
            # 1. Çarpma işlemleri (Her bir MAC için zorla fp32 kırpması yapılıyor)
            products = [np.float32(i_val * w_val) for i_val, w_val in zip(input_padded, neuron_weights)]
            
            # 2. Sum (Adder Tree yapısı ile toplama)
            sum_val = adder_tree_sum(products)
            
            # 3. Sum + Bias (Yine fp32 kırpması)
            sum_bias_val = np.float32(sum_val + bias_val)
            
            # 4. Nöron Çıktısı (ReLU - fp32 üzerinden)
            relu_val = np.float32(max(np.float32(0.0), sum_bias_val))

            # Çıktı metnini hazırla
            output_str = f"Neuron [{neuron_idx:03d}]:\n"
            output_str += f"  Sum       : {sum_val:>12.6f}  (Hex: {float32_to_hex(sum_val)})\n"
            output_str += f"  Sum+Bias  : {sum_bias_val:>12.6f}  (Hex: {float32_to_hex(sum_bias_val)})\n"
            output_str += f"  ReLU(Out) : {relu_val:>12.6f}  (Hex: {float32_to_hex(relu_val)})\n"
            output_str += "-" * 65 + "\n"

            if neuron_idx < 5:
                print(output_str, end="")
            
            fout.write(output_str)
            
        print(f"\n[BASARILI] Tum {LAYER_0_NEURONS} noronun FP32 verisi '{output_file}' dosyasina kaydedildi.")

if __name__ == "__main__":
    generate_rtl_reference()