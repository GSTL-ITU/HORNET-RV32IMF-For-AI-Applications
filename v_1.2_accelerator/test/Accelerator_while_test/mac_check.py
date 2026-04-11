import struct
import numpy as np

def hex_to_float32(h):
    """Hex string'i IEEE-754 float32 sayısına çevirir."""
    return np.float32(struct.unpack('>f', bytes.fromhex(h))[0])

def float32_to_hex(f):
    """Float32 sayısını IEEE-754 hex string'e çevirir."""
    return struct.pack('>f', f).hex().zfill(8)

def enforce_positive_zero(val):
    """Eğer değer sıfırsa (negatif veya pozitif fark etmez), kesinlikle pozitif sıfır döndürür."""
    if val == 0.0:
        return np.float32(0.0)
    return val

def sanitize_hex(h):
    """Eğer donanımdan X veya benzeri don't care durumu gelirse bunu 0'a zorlar."""
    h = h.strip()
    if 'x' in h.lower():
        return '00000000'
    return h

def process_hex_arrays(arr1_hex_str, arr2_hex_str, operation='multiply'):
    """İki virgülle ayrılmış hex string'i alır, belirtilen işleme göre item-item işler."""
    arr1 = [sanitize_hex(x) for x in arr1_hex_str.split(',')]
    arr2 = [sanitize_hex(x) for x in arr2_hex_str.split(',')]
    
    if len(arr1) != 32 or len(arr2) != 32:
        print(f"Uyarı: Array uzunlukları 32 değil! (Arr1: {len(arr1)}, Arr2: {len(arr2)})")

    result_array = []
    
    for h1, h2 in zip(arr1, arr2):
        f1 = hex_to_float32(h1)
        f2 = hex_to_float32(h2)
        
        if operation == 'multiply':
            res = np.float32(f1 * f2)
        elif operation == 'add':
            res = np.float32(f1 + f2)
        else:
            raise ValueError("Geçersiz işlem tipi!")
            
        res = enforce_positive_zero(res)
        result_array.append(res)
        
    return result_array

def print_float_array_as_hex(float_arr):
    hex_arr = [float32_to_hex(f) for f in float_arr]
    print("\nArray Sonucu (Hex):")
    print(",".join(hex_arr))

def main():
    print("="*60)
    print(" IEEE-754 32-Bit Donanım Doğrulama Aracı ".center(60, "="))
    print("="*60)
    print("Lütfen bir mod seçin:")
    print("1. Doğrudan Çarpma (Element-wise Multiplication)")
    print("2. Doğrudan Toplama (Element-wise Addition)")
    print("3. MAC (Multiply-Accumulate) İşlemi")
    print("4. Array İçi Toplama (32 Değerin Toplamı)")
    print("5. Array Karşılaştırma (Compare 2 Arrays)")
    
    while True:
        mode = input("\nMod Seçimi (1-5): ").strip()
        if mode in ['1', '2', '3', '4', '5']:
            break
        print("Geçersiz giriş. Lütfen 1 ile 5 arasında bir değer girin.")
        
    print("\n" + "-"*60 + "\n")

    if mode == '1' or mode == '2':
        op_name = "Çarpma" if mode == '1' else "Toplama"
        op_type = 'multiply' if mode == '1' else 'add'
        
        print(f"=== Mod {mode}: {op_name} İşlemi ===")
        input1 = input("1. Input array'i girin (Virgülle ayrılmış 32 adet hex):\n")
        input2 = input("2. Input array'i girin (Virgülle ayrılmış 32 adet hex):\n")
        
        result = process_hex_arrays(input1, input2, operation=op_type)
        print_float_array_as_hex(result)
        
        total_sum = enforce_positive_zero(np.sum(result, dtype=np.float32))
        print(f"\nBu arraydeki değerlerin genel toplamı (Hex): {float32_to_hex(total_sum)}")
        print(f"Bu arraydeki değerlerin genel toplamı (Float): {total_sum}")

    elif mode == '3':
        print("=== Mod 3: MAC (Multiply-Accumulate) İşlemi ===")
        
        while True:
            try:
                loop_count = int(input("MAC işlemi için loop sayısı giriniz (1-8 arası): "))
                if 1 <= loop_count <= 8:
                    break
                else:
                    print("Lütfen 1 ile 8 arasında bir değer girin.")
            except ValueError:
                print("Geçersiz değer, lütfen sayı giriniz.")

        accumulator_array = [np.float32(0.0) for _ in range(32)]
        
        for round_idx in range(1, loop_count + 1):
            print(f"\n--- ROUND {round_idx} ---")
            mac_in1 = input(f"Round {round_idx} - 1. Array (Hex): \n")
            mac_in2 = input(f"Round {round_idx} - 2. Array (Hex): \n")
            
            round_product = process_hex_arrays(mac_in1, mac_in2, operation='multiply')
            
            for i in range(len(accumulator_array)):
                new_val = np.float32(accumulator_array[i] + round_product[i])
                accumulator_array[i] = enforce_positive_zero(new_val)
            
            print(f"\n>> Round {round_idx} Sonrası MAC Accumulator Array (Yeni Cin) Çıktısı:")
            print_float_array_as_hex(accumulator_array)
            
            round_sum = enforce_positive_zero(np.sum(accumulator_array, dtype=np.float32))
            print(f">> Round {round_idx} MAC Sonuç Toplamı (Hex): {float32_to_hex(round_sum)}")

    elif mode == '4':
        print("=== Mod 4: Array İçi Toplama ===")
        input1 = input("Input array'i girin (Virgülle ayrılmış 32 adet hex):\n")
        
        arr_str = [sanitize_hex(x) for x in input1.split(',')]
        if len(arr_str) != 32:
            print(f"Uyarı: Array uzunluğu 32 değil! (Girilen: {len(arr_str)})")
            
        float_arr = [hex_to_float32(h) for h in arr_str]
        
        total_sum = enforce_positive_zero(np.sum(float_arr, dtype=np.float32))
        
        print(f"\n>> Array Değerlerinin Toplamı (Hex): {float32_to_hex(total_sum)}")
        print(f">> Array Değerlerinin Toplamı (Float): {total_sum}")

    elif mode == '5':
        print("=== Mod 5: Array Karşılaştırma ===")
        input1 = input("1. Input array'i girin (Örn: Altın Model Sonucu):\n")
        input2 = input("2. Input array'i girin (Örn: Simülasyon Çıktısı):\n")
        
        arr1_str = [sanitize_hex(x) for x in input1.split(',')]
        arr2_str = [sanitize_hex(x) for x in input2.split(',')]
        
        if len(arr1_str) != len(arr2_str):
            print(f"\nHATA: Array boyutları uyuşmuyor! (Arr1: {len(arr1_str)}, Arr2: {len(arr2_str)})")
        else:
            # IEEE-754 toleransını eşitlemek için (+0 / -0 durumları için filtreden geçiriyoruz)
            clean_hex1 = [float32_to_hex(enforce_positive_zero(hex_to_float32(x))) for x in arr1_str]
            clean_hex2 = [float32_to_hex(enforce_positive_zero(hex_to_float32(x))) for x in arr2_str]
            
            if clean_hex1 == clean_hex2:
                print("\n>> SONUÇ: MATCH! (İki array tamamen aynı)")
            else:
                print("\n>> SONUÇ: NOT MATCH! (Farklılıklar var)")
                print("Eşleşmeyen Değerler:")
                for i, (h1, h2) in enumerate(zip(clean_hex1, clean_hex2)):
                    if h1 != h2:
                        print(f" - Index {i:02d} | Arr1: {h1} <---> Arr2: {h2}")

    print("\n" + "="*60)
    print(" İŞLEM TAMAMLANDI ".center(60, "="))
    print("="*60)

if __name__ == "__main__":
    main()