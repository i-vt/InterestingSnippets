import argparse
from Crypto.Cipher import AES
from Crypto.Util.Padding import pad, unpad
import base64

def aes_encrypt_string(plaintext, key, iv):
    cipher = AES.new(key, AES.MODE_CBC, iv)
    padded_data = pad(plaintext.encode(), AES.block_size)
    ciphertext = cipher.encrypt(padded_data)
    return base64.b64encode(ciphertext).decode()

def aes_decrypt_string(ciphertext, key, iv):
    cipher = AES.new(key, AES.MODE_CBC, iv)
    decrypted_data = cipher.decrypt(base64.b64decode(ciphertext))
    return unpad(decrypted_data, AES.block_size).decode()

def aes_encrypt_file(input_file, output_file, key, iv):
    cipher = AES.new(key, AES.MODE_CBC, iv)
    with open(input_file, 'rb') as f:
        file_data = f.read()
    padded_data = pad(file_data, AES.block_size)
    ciphertext = cipher.encrypt(padded_data)
    with open(output_file, 'wb') as f:
        f.write(ciphertext)

def aes_decrypt_file(input_file, output_file, key, iv):
    cipher = AES.new(key, AES.MODE_CBC, iv)
    with open(input_file, 'rb') as f:
        ciphertext = f.read()
    decrypted_data = cipher.decrypt(ciphertext)
    unpadded_data = unpad(decrypted_data, AES.block_size)
    with open(output_file, 'wb') as f:
        f.write(unpadded_data)

def read_file_content(filepath):
    """Reads and decodes content of a file."""
    try:
        with open(filepath, 'rb') as f:
            return f.read()
    except FileNotFoundError:
        print(f"Error: File not found - {filepath}")
        exit(1)

def main():
    parser = argparse.ArgumentParser(description="AES encryption and decryption tool for strings and files.")
    
    parser.add_argument("--keyfile", required=True, help="Path to the file containing the key (16, 24, or 32 bytes).")
    parser.add_argument("--ivfile", required=True, help="Path to the file containing the IV (16 bytes).")

    subparsers = parser.add_subparsers(dest="command", help="Commands")

    # String mode subparser
    string_parser = subparsers.add_parser("string", help="Encrypt or decrypt a string.")
    string_parser.add_argument("--action", choices=["encrypt", "decrypt"], required=True, help="Action to perform.")
    string_parser.add_argument("--text", required=True, help="The string to encrypt or decrypt.")

    # File mode subparser
    file_parser = subparsers.add_parser("file", help="Encrypt or decrypt a file.")
    file_parser.add_argument("--action", choices=["encrypt", "decrypt"], required=True, help="Action to perform.")
    file_parser.add_argument("--input", required=True, help="Path to the input file.")
    file_parser.add_argument("--output", required=True, help="Path to the output file.")

    args = parser.parse_args()

    key = read_file_content(args.keyfile)
    iv = read_file_content(args.ivfile)

    if len(key) not in [16, 24, 32]:
        print("Error: Key must be 16, 24, or 32 bytes long.")
        exit(1)
    if len(iv) != 16:
        print("Error: IV must be 16 bytes long.")
        exit(1)

    if args.command == "string":
        if args.action == "encrypt":
            result = aes_encrypt_string(args.text, key, iv)
            print(f"Encrypted String: {result}")
        elif args.action == "decrypt":
            try:
                result = aes_decrypt_string(args.text, key, iv)
                print(f"Decrypted String: {result}")
            except Exception as e:
                print(f"Decryption failed: {e}")
    elif args.command == "file":
        if args.action == "encrypt":
            aes_encrypt_file(args.input, args.output, key, iv)
            print(f"File encrypted: {args.output}")
        elif args.action == "decrypt":
            try:
                aes_decrypt_file(args.input, args.output, key, iv)
                print(f"File decrypted: {args.output}")
            except Exception as e:
                print(f"Decryption failed: {e}")

if __name__ == "__main__":
    main()
