import random
import argparse
import math

def generate_entropy_file(output_file, size_bytes, target_entropy):
    # Ensure entropy is within valid range
    if not (0 <= target_entropy <= 8):
        raise ValueError("Entropy must be between 0 and 8 bits per byte.")

    # Number of unique symbols needed: 2^entropy
    num_symbols = int(2 ** target_entropy)

    if num_symbols > 256:
        raise ValueError("Entropy too high — max 8.0 (256 symbols) allowed.")

    # Generate that many unique symbols from 0-255
    symbols = random.sample(range(256), num_symbols)

    # Generate uniform data
    chunk_size = len(symbols)
    full_chunks = size_bytes // chunk_size
    remaining = size_bytes % chunk_size

    data = symbols * full_chunks + random.choices(symbols, k=remaining)
    random.shuffle(data)

    with open(output_file, 'wb') as f:
        f.write(bytearray(data))

    print(f"Generated '{output_file}' with ~{target_entropy:.2f} bits/byte entropy, size {size_bytes} bytes.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate file with approximate entropy.")
    parser.add_argument("output_file", help="Output file name")
    parser.add_argument("size", help="File size (e.g., 5MB or 5242880)")
    parser.add_argument("entropy", type=float, help="Target entropy in bits per byte (e.g., 2.0)")

    args = parser.parse_args()

    # Parse size (support MB or bytes)
    size_arg = args.size.upper()
    if size_arg.endswith("MB"):
        size_bytes = int(float(size_arg[:-2]) * 1024 * 1024)
    else:
        size_bytes = int(size_arg)

    generate_entropy_file(args.output_file, size_bytes, args.entropy)
