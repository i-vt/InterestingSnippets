from Crypto.Cipher import AES
import os

def save_to_file(data, filename):
    with open(filename, 'wb') as f:
        f.write(data)

def generate_key_iv(key_size=32):  # Default to 256 bits key
    key = os.urandom(key_size)
    iv = os.urandom(AES.block_size)
    save_to_file(key, "aes_key.bin")
    save_to_file(iv, "aes_iv.bin")
    print(f"Key and IV generated and saved to 'aes_key.bin' and 'aes_iv.bin'.")

if __name__ == "__main__":
    generate_key_iv()
