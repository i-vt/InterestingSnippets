#!/usr/bin/env python3
import sys
import os

def split_file(input_file, chunk_size=5000, prefix="split_"):
    with open(input_file, "r", encoding="utf-8") as f:
        lines = f.readlines()

    chunk = []
    current_size = 0
    file_count = 1

    for line in lines:
        line_length = len(line)
        # If adding this line exceeds the limit, write current chunk to a file
        if current_size + line_length > chunk_size and chunk:
            output_name = f"{prefix}{file_count:03d}.txt"
            with open(output_name, "w", encoding="utf-8") as out:
                out.writelines(chunk)
            print(f"Wrote {output_name} ({current_size} chars)")
            file_count += 1
            chunk = []
            current_size = 0

        chunk.append(line)
        current_size += line_length

    # Write remaining lines
    if chunk:
        output_name = f"{prefix}{file_count:03d}.txt"
        with open(output_name, "w", encoding="utf-8") as out:
            out.writelines(chunk)
        print(f"Wrote {output_name} ({current_size} chars)")

def main():
    if len(sys.argv) < 2:
        print("Usage: split_file.py <input_file> [chunk_size] [prefix]")
        sys.exit(1)

    input_file = sys.argv[1]
    chunk_size = int(sys.argv[2]) if len(sys.argv) > 2 else 5000
    prefix = sys.argv[3] if len(sys.argv) > 3 else "split_"

    if not os.path.isfile(input_file):
        print(f"Error: '{input_file}' not found.")
        sys.exit(1)

    split_file(input_file, chunk_size, prefix)

if __name__ == "__main__":
    main()
