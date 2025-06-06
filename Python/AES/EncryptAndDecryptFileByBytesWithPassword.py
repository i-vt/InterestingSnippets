import uuid
import os
import random
from cryptography.hazmat.primitives.kdf.scrypt import Scrypt
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

# Constants
SALT_SIZE = 16  # 128-bit salt
KEY_SIZE = 32   # 256-bit AES key
NONCE_SIZE = 12 # Recommended size for AESGCM

def derive_key(password: str, salt: bytes) -> bytes:
    kdf = Scrypt(salt=salt, length=KEY_SIZE, n=2**14, r=8, p=1)
    return kdf.derive(password.encode())

def encrypt_file(input_file: str, output_file: str, password: str):
    salt = os.urandom(SALT_SIZE)
    nonce = os.urandom(NONCE_SIZE)
    key = derive_key(password, salt)

    with open(input_file, 'rb') as f:
        data = f.read()

    aesgcm = AESGCM(key)
    encrypted = aesgcm.encrypt(nonce, data, None)

    with open(output_file, 'wb') as f:
        f.write(salt + nonce + encrypted)

def decrypt_file(encrypted_file: str, output_file: str, password: str):
    with open(encrypted_file, 'rb') as f:
        salt = f.read(SALT_SIZE)
        nonce = f.read(NONCE_SIZE)
        ciphertext = f.read()

    key = derive_key(password, salt)
    aesgcm = AESGCM(key)
    decrypted = aesgcm.decrypt(nonce, ciphertext, None)

    with open(output_file, 'wb') as f:
        f.write(decrypted)
def secure_delete(file_path, passes=3):
  # Just FYI, on SSD this might not work - but on HDD works like magic
    if not os.path.isfile(file_path):
        raise FileNotFoundError(f"No such file: {file_path}")

    try:
        length = os.path.getsize(file_path)
        with open(file_path, 'ba+', buffering=0) as f:
            for i in range(passes):
                f.seek(0)
                f.write(os.urandom(length))
                f.flush()
                os.fsync(f.fileno())

        os.remove(file_path)
        print(f"Securely deleted: {file_path}")
    except Exception as e:
        raise RuntimeError(f"Failed to securely delete {file_path}: {e}")
# Generate a random UUID (UUID4)
generated_uuid = str(uuid.uuid4())

print("Generated UUID:", generated_uuid)
# Encrypt
encrypt_file("myfile.txt", "myfile.encrypted", generated_uuid)
secure_delete("myfile.txt")
# Decrypt
decrypt_file("myfile.encrypted", "myfile_decrypted.txt", generated_uuid)
secure_delete("myfile.encrypted")
