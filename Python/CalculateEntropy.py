import sys
import math
from collections import Counter

def calculate_entropy(file_path):
    with open(file_path, 'rb') as f:
        data = f.read()

    total = len(data)
    print(f"Total bytes: {total}")  # DEBUG

    if total == 0:
        return 0.0

    byte_counts = Counter(data)
    print(f"Byte counts: {byte_counts}")  # DEBUG

    entropy = 0.0
    for count in byte_counts.values():
        p = count / total
        print(f"p={p}, count={count}")  # DEBUG
        entropy -= p * math.log2(p)

    return entropy

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python entropy_calc.py <input_file>")
        sys.exit(1)

    input_file = sys.argv[1]

    entropy_value = calculate_entropy(input_file)

    print(f"Entropy: {entropy_value}\n")
