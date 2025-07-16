import hashlib
import os
import argparse

class HashFile:
    def __init__(self, path_passed):
        self.filepath = path_passed

    def md5(self):
        hash_md5 = hashlib.md5()
        with open(self.filepath, "rb") as f:
            for chunk in iter(lambda: f.read(4096), b""):
                hash_md5.update(chunk)
        return hash_md5.hexdigest()

    def sha256(self):
        hash_sha256 = hashlib.sha256()
        bytearr = bytearray(128 * 1024)
        memview = memoryview(bytearr)
        with open(self.filepath, 'rb', buffering=0) as file:
            for n in iter(lambda: file.readinto(memview), 0):
                hash_sha256.update(memview[:n])
        return hash_sha256.hexdigest()

    def filesize(self):
        st = os.stat(self.filepath)
        return st.st_size

    def all(self) -> list:
        return [self.md5(), self.sha256(), self.filesize(), self.filepath]

def main():
    parser = argparse.ArgumentParser(description="Compute MD5, SHA256, and file size of a given file.")
    parser.add_argument("filepath", help="Path to the file")
    parser.add_argument("--md5", action="store_true", help="Compute MD5 hash")
    parser.add_argument("--sha256", action="store_true", help="Compute SHA256 hash")
    parser.add_argument("--size", action="store_true", help="Get file size")
    parser.add_argument("--all", action="store_true", help="Show all info")

    args = parser.parse_args()

    hasher = HashFile(args.filepath)

    if args.all:
        md5_hash, sha256_hash, size, path = hasher.all()
        print(f"File: {path}")
        print(f"MD5: {md5_hash}")
        print(f"SHA256: {sha256_hash}")
        print(f"Size: {size} bytes")
    else:
        if args.md5:
            print(f"MD5: {hasher.md5()}")
        if args.sha256:
            print(f"SHA256: {hasher.sha256()}")
        if args.size:
            print(f"Size: {hasher.filesize()} bytes")

if __name__ == "__main__":
    main()
