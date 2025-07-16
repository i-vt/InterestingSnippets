import argparse
import os
import uuid
import datetime
from collections import defaultdict
import re


# Get string of current time as a timestamp: "yyyymmddHHMMSS"
def timestamp() -> str:
    current = datetime.datetime.now()
    return current.strftime("%Y%m%d%H%M%S")

def get_uuid():
    # Generate a random UUID (UUID4)
    generated_uuid = uuid.uuid4()
    return str(generated_uuid)

def gen_filenames(total_files: int, prefix: str = None):
    generated_uuid = get_uuid()
    current_time = timestamp()
    filenames = []
    width = len(str(total_files))  # Padding width
    for i in range(1, total_files + 1):
        chunk_number = str(i).zfill(width)
        total_str = str(total_files).zfill(width)
        filename = f"{current_time}_{generated_uuid}_{chunk_number}_{total_str}.chunk"
        if prefix:
            filename = os.path.join(prefix, filename)
        filenames.append(filename)
    return filenames

def split_file(file_path: str, chunk_size: int = 100 * 1024, output_dir=None):
    # Default is 100KB
    if output_dir is None:
        output_dir = os.path.dirname(file_path)

    file_size = os.path.getsize(file_path)
    if file_size <= chunk_size:
        print(f"File is {file_size} bytes. No splitting performed.")
        return

    total_parts = (file_size + chunk_size - 1) // chunk_size
    filenames = gen_filenames(total_parts, prefix=output_dir)

    with open(file_path, 'rb') as f:
        for i, filename in enumerate(filenames):
            chunk = f.read(chunk_size)
            if not chunk:
                break
            with open(filename, 'wb') as chunk_file:
                chunk_file.write(chunk)

    print(f"Split completed: {len(filenames)} chunks written to '{output_dir}'.")

def reassemble_file(chunks_dir: str, output_dir: str = None):
    chunk_files = [f for f in os.listdir(chunks_dir) if f.endswith(".chunk")]
    if not chunk_files:
        print("No chunk files found in the directory.")
        return

    # Updated regex: capture timestamp, UUID, chunk number, total count
    uuid_pattern = re.compile(r"(\d{14})_([a-f0-9\-]{36})_(\d+)_([0-9]+)\.chunk$")
    chunks_by_group = defaultdict(list)

    for f in chunk_files:
        match = uuid_pattern.match(f)
        if match:
            timestamp_str, file_uuid, chunk_number, total_chunks = match.groups()
            group_key = f"{timestamp_str}_{file_uuid}_{total_chunks}"
            chunks_by_group[group_key].append((int(chunk_number), f))
        else:
            print(f"Skipping unrecognized file: {f}")

    for group_key, chunks in chunks_by_group.items():
        timestamp_str, file_uuid, total_chunks = group_key.split('_')
        total_chunks = int(total_chunks)
        if len(chunks) != total_chunks:
            print(f"Skipping incomplete set for {file_uuid}: expected {total_chunks}, found {len(chunks)}")
            continue

        chunks.sort()  # Sort by chunk number
        output_name = f"{timestamp_str}_{file_uuid}.reassembled"
        output_path = os.path.join(output_dir or chunks_dir, output_name)

        with open(output_path, 'wb') as output_file:
            for _, chunk_name in chunks:
                chunk_path = os.path.join(chunks_dir, chunk_name)
                with open(chunk_path, 'rb') as chunk_file:
                    output_file.write(chunk_file.read())

        print(f"Reassembled file written: {output_path}")

class Cleanup:
    def __init__(self, directory: str, max_age_days: int = 30, max_total_size: int = 2 * 1024 * 1024 * 1024):
        self.directory = directory
        self.max_age_days = max_age_days
        self.max_total_size = max_total_size
        self.now = datetime.datetime.now()
        self.extensions = [".chunk", ".reassembled"]

    def get_target_files(self):
        files = []
        for filename in os.listdir(self.directory):
            if any(filename.endswith(ext) for ext in self.extensions):
                filepath = os.path.join(self.directory, filename)
                try:
                    stat = os.stat(filepath)
                    mtime = datetime.datetime.fromtimestamp(stat.st_mtime)
                    age_days = (self.now - mtime).days
                    size = stat.st_size
                    files.append((filepath, mtime, size, age_days))
                except FileNotFoundError:
                    continue  # File might be deleted between listdir and stat
        return files

    def delete_old_files(self, files):
        for filepath, _, _, age_days in files:
            if age_days > self.max_age_days:
                try:
                    os.remove(filepath)
                    print(f"Deleted old file: {filepath} (age: {age_days} days)")
                except FileNotFoundError:
                    continue

    def delete_to_reduce_size(self, files):
        valid_files = [
            (path, mtime, size)
            for path, mtime, size, age in files
            if age <= self.max_age_days and os.path.exists(path)
        ]
        total_size = sum(size for _, _, size in valid_files)

        if total_size > self.max_total_size:
            print(f"Total size exceeds limit ({total_size} > {self.max_total_size}), cleaning up...")
            valid_files.sort(key=lambda x: x[1])  # Sort by mtime (oldest first)
            for filepath, _, size in valid_files:
                try:
                    os.remove(filepath)
                    total_size -= size
                    print(f"Deleted to reduce size: {filepath} ({size} bytes)")
                    if total_size <= self.max_total_size:
                        break
                except FileNotFoundError:
                    continue

    def run(self):
        all_files = self.get_target_files()
        self.delete_old_files(all_files)
        updated_files = self.get_target_files()
        self.delete_to_reduce_size(updated_files)


def main():
    parser = argparse.ArgumentParser(description="File chunking utility")
    subparsers = parser.add_subparsers(dest='command', required=True)

    # Split command
    split_parser = subparsers.add_parser('split', help='Split a file into chunks')
    split_parser.add_argument('file', type=str, help='Path to the file to split')
    split_parser.add_argument('--chunk-size', type=int, default=100*1024, help='Chunk size in bytes (default: 100KB)')
    split_parser.add_argument('--output-dir', type=str, default=None, help='Directory to store chunks')

    # Reassemble command
    reassemble_parser = subparsers.add_parser('reassemble', help='Reassemble chunks into original file')
    reassemble_parser.add_argument('chunks_dir', type=str, help='Directory containing chunk files')
    reassemble_parser.add_argument('--output-dir', type=str, default=None, help='Directory to write the reassembled file')

    # Cleanup command
    cleanup_parser = subparsers.add_parser('cleanup', help='Clean up old or oversized chunk files')
    cleanup_parser.add_argument('directory', type=str, help='Directory to clean')
    cleanup_parser.add_argument('--max-age-days', type=int, default=30, help='Max age in days before deletion (default: 30)')
    cleanup_parser.add_argument('--max-total-size', type=int, default=2*1024*1024*1024, help='Max total size in bytes (default: 2GB)')

    args = parser.parse_args()

    if args.command == 'split':
        split_file(args.file, chunk_size=args.chunk_size, output_dir=args.output_dir)
    elif args.command == 'reassemble':
        reassemble_file(args.chunks_dir, output_dir=args.output_dir)
    elif args.command == 'cleanup':
        cleaner = Cleanup(args.directory, max_age_days=args.max_age_days, max_total_size=args.max_total_size)
        cleaner.run()

if __name__ == '__main__':
    main()
