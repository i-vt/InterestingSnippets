#!/usr/bin/env python3

import hashlib
import base64
from Cryptodome.Cipher import AES
import argparse
import sys

def main():
    parser = argparse.ArgumentParser(description="Decrypt mRemoteNG passwords.")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("-f", "--file", help="name of file containing mRemoteNG password")
    group.add_argument("-s", "--string", help="base64 string of mRemoteNG password")
    parser.add_argument("-p", "--password", help="Custom password", default="mR3m")

    if len(sys.argv) < 2:
        parser.print_help(sys.stderr)
        sys.exit(1)

    args = parser.parse_args()
    encrypted_data = ""

    try:
        if args.file:
            with open(args.file, 'r') as f:
                encrypted_data = f.read().strip()
        elif args.string:
            encrypted_data = args.string
        else:
            print("Please use either the file (-f, --file) or string (-s, --string) flag")
            sys.exit(1)

        encrypted_data = base64.b64decode(encrypted_data)
        salt = encrypted_data[:16]
        associated_data = encrypted_data[:16]
        nonce = encrypted_data[16:32]
        ciphertext = encrypted_data[32:-16]
        tag = encrypted_data[-16:]
        key = hashlib.pbkdf2_hmac("sha1", args.password.encode(), salt, 1000, dklen=32)

        cipher = AES.new(key, AES.MODE_GCM, nonce=nonce)
        cipher.update(associated_data)

        plaintext = cipher.decrypt_and_verify(ciphertext, tag)
        print("Password: {}".format(plaintext.decode("utf-8")))

    except (ValueError, KeyError, base64.binascii.Error) as e:
        print("Decryption failed. Reason: {}".format(str(e)))
        print("Password: <decryption error>")

if __name__ == "__main__":
    main()
