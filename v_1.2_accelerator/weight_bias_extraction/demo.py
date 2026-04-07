import struct
import numpy as np

def hex_to_float32(hex_str):
    """32-bit hex string'i (IEEE-754) FP32'ye çevirir."""
    try:
        f_val = struct.unpack('<f', struct.pack('<I', int(hex_str, 16)))[0]
        return np.float32(f_val)
    except ValueError:
        return np.float32(0.0)

def float32_to_hex(f):
    """FP32 değerini 32-bit hex string'e çevirir."""
    return f"{struct.unpack('<I', struct.pack('<f', f))[0]:08x}"

def main():
    print("=========================================================")
    print("    1024-bit (32x FP32) Vektörel Hex Hesap Makinesi      ")
    print("=========================================================\n")
    
    print("Lütfen yapmak istediğiniz işlemi seçin:")
    print("  1 - Vektörel Çarpma (Element-wise Multiply)")
    print("  2 - Vektörel Toplama (Element-wise Add)")
    
    secim = input("\nSeçiminiz (1 veya 2): ").strip()
    
    if secim not in ['1', '2']:
        print("\n[HATA] Geçersiz seçim! Lütfen 1 veya 2 girin.")
        return

    islem_adi = "ÇARPMA" if secim == '1' else "TOPLAMA"
    print(f"\n--- {islem_adi} MODU AKTİF ---")

    str1 = input("1. Hex Stringi yapıştırın (256 karakter): ").strip()
    str2 = input("2. Hex Stringi yapıştırın (256 karakter): ").strip()

    # Uzunluk kontrolü
    if len(str1) != 256 or len(str2) != 256:
        print(f"\n[HATA] Girdiğiniz stringler tam olarak 256 karakter olmalıdır!")
        print(f"1. String: {len(str1)} karakter")
        print(f"2. String: {len(str2)} karakter")
        return

    # Stringleri 8 karakterlik (32-bit) parçalara böl
    chunks1 = [str1[i:i+8] for i in range(0, 256, 8)]
    chunks2 = [str2[i:i+8] for i in range(0, 256, 8)]

    result_hex_list = []

    # Eleman eleman (pointwise) işlem
    for idx, (c1, c2) in enumerate(zip(chunks1, chunks2)):
        f1 = hex_to_float32(c1)
        f2 = hex_to_float32(c2)
        
        # Seçime göre işlemi yap (Zorla Single Precision)
        if secim == '1':
            f_res = np.float32(f1 * f2)
        else:
            f_res = np.float32(f1 + f2)
        
        # --- DONANIM TAKLİDİ (No Negative Zero) ---
        if f_res == 0.0:
            f_res = np.float32(0.0)
            
        res_hex = float32_to_hex(f_res)
        result_hex_list.append(res_hex)

    # Sonuçları tekrar 256 karakterlik tek bir string'e birleştir
    final_string = "".join(result_hex_list)

    print(f"\n==================== SONUÇ ({islem_adi}) ====================")
    print(final_string)
    print("=========================================================\n")

if __name__ == "__main__":
    main()