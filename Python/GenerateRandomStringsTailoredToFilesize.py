import os
import random
import string

def generate_file(target_mb, output_file):
    target_bytes = target_mb * 1024 * 1024  # convert MB to bytes
    chars = string.ascii_letters + string.digits

    with open(output_file, "w") as f:
        while f.tell() < target_bytes:
            # generate a random string (adjust length as desired)
            rand_str = ''.join(random.choices(chars, k=1024))  # 1 KB chunk
            f.write(rand_str + "\n")

    print(f"Done! File '{output_file}' reached at least {target_mb} MB.")
    print(f"Final size: {os.path.getsize(output_file) / (1024*1024):.2f} MB")

if __name__ == "__main__":
    generate_file(10, "random_output.txt")   # change 10 to X MB
