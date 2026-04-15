import argparse
import serial
import sys

def main():
    ap = argparse.ArgumentParser(description="Listen to FPGA hardcoded inference test.")
    ap.add_argument("--port", required=True, help="Serial port (e.g., /dev/ttyUSB0 or COM5)")
    ap.add_argument("--baud", type=int, default=115200, help="Baudrate (default: 115200)")
    args = ap.parse_args()

    expected_labels = ["Class 0", "Class 1", "Class 3", "Class 4"]
    count = 0

    try:
        with serial.Serial(
            port=args.port,
            baudrate=args.baud,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=None # Block forever until bytes arrive
        ) as ser:
            
            ser.reset_input_buffer()
            print(f"Listening on {args.port} at {args.baud} baud...")
            print(">>> PLEASE PRESS RESET ON THE FPGA NOW <<<")
            print("-" * 40)

            while True:
                # Read 1 byte
                data = ser.read(1)
                if data:
                    val = int.from_bytes(data, 'little')
                    
                    # 0xFF is our custom end marker
                    if val == 255:
                        print("-" * 40)
                        print("Received END marker (0xFF). Test complete!")
                        break
                    
                    # Print the prediction
                    if count < len(expected_labels):
                        print(f"Expected: {expected_labels[count]} | FPGA Predicted: {val}")
                    else:
                        print(f"Extra byte received: {val}")
                    
                    count += 1

    except serial.SerialException as e:
        print(f"Serial error: {e}")
        sys.exit(1)
    except KeyboardInterrupt:
        print("\nTest manually interrupted.")
        sys.exit(0)

if __name__ == "__main__":
    main()