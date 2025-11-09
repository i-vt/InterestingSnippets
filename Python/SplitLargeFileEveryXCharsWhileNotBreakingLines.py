#!/usr/bin/env python3
import sys
import os

def count_chunks(lines, chunk_size):
    """
    Count how many chunks will be created (dry run).
    """
    current_size = 0
    chunk_count = 0
    has_content = False
    
    for line in lines:
        line_length = len(line)
        
        if current_size + line_length > chunk_size and has_content:
            chunk_count += 1
            current_size = 0
            has_content = False
        
        current_size += line_length
        has_content = True
    
    # Count the last chunk if there's remaining content
    if has_content:
        chunk_count += 1
    
    return chunk_count

def split_file(input_file, chunk_size=5000, prefix="split_"):
    with open(input_file, "r", encoding="utf-8") as f:
        lines = f.readlines()
    
    # First pass: count total chunks to determine padding width
    total_chunks = count_chunks(lines, chunk_size)
    padding_width = len(str(total_chunks))
    
    print(f"📊 Will create {total_chunks} files with {padding_width}-digit padding\n")
    
    chunk = []
    current_size = 0
    file_count = 1
    
    for line in lines:
        line_length = len(line)
        
        # If adding this line exceeds the limit, write current chunk to a file
        if current_size + line_length > chunk_size and chunk:
            output_name = f"{prefix}{file_count:0{padding_width}d}.txt"
            with open(output_name, "w", encoding="utf-8") as out:
                out.writelines(chunk)
            print(f"✅ Wrote {output_name} ({current_size:,} chars)")
            
            file_count += 1
            chunk = []
            current_size = 0
        
        chunk.append(line)
        current_size += line_length
    
    # Write remaining lines
    if chunk:
        output_name = f"{prefix}{file_count:0{padding_width}d}.txt"
        with open(output_name, "w", encoding="utf-8") as out:
            out.writelines(chunk)
        print(f"✅ Wrote {output_name} ({current_size:,} chars)")
    
    print(f"\n✅ Successfully split into {file_count} files")

def main():
    if len(sys.argv) < 2:
        print("Usage: split_file.py <input_file> [chunk_size] [prefix]")
        print("\nExamples:")
        print("  split_file.py input.txt")
        print("  split_file.py input.txt 10000")
        print("  split_file.py input.txt 10000 part_")
        sys.exit(1)
    
    input_file = sys.argv[1]
    chunk_size = int(sys.argv[2]) if len(sys.argv) > 2 else 5000
    prefix = sys.argv[3] if len(sys.argv) > 3 else "split_"
    
    if not os.path.isfile(input_file):
        print(f"❌ Error: '{input_file}' not found.")
        sys.exit(1)
    
    print(f"📂 Input file: {input_file}")
    print(f"📏 Chunk size: {chunk_size:,} characters")
    print(f"🏷️  Prefix: {prefix}\n")
    
    split_file(input_file, chunk_size, prefix)

if __name__ == "__main__":
    main()
