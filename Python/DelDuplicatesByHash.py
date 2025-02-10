import os
import hashlib
from collections import defaultdict

def file_hash(filepath):
    """Generate a hash for a file."""
    hasher = hashlib.sha1()
    with open(filepath, 'rb') as f:
        buf = f.read(65536)
        while len(buf) > 0:
            hasher.update(buf)
            buf = f.read(65536)
    return hasher.hexdigest()

def find_duplicate_files(directory):
    """Find and group duplicate files by hash."""
    hashes = defaultdict(list)
    # Walk through all files and folders within directory
    for subdir, dirs, files in os.walk(directory):
        for file in files:
            filepath = os.path.join(subdir, file)
            file_hash_value = file_hash(filepath)
            hashes[file_hash_value].append(filepath)
    return hashes

def delete_duplicates(duplicates):
    """Delete duplicates, keeping the one with the shortest name."""
    for files in duplicates.values():
        if len(files) > 1:
            # Sort files by name length, shortest name first
            files_sorted = sorted(files, key=lambda x: (len(os.path.basename(x)), x))
            # Keep the file with the shortest name
            file_to_keep = files_sorted[0]
            # Delete the rest
            for file in files_sorted[1:]:
                os.remove(file)
                print(f"Deleted {file}")
            print(f"Kept {file_to_keep}")

if __name__ == "__main__":
    directory = '/path/to/your/directory'  # Modify this path to your target directory
    duplicates = find_duplicate_files(directory)
    delete_duplicates(duplicates)
