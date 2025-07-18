import os

def get_file_size(filepath):
    """Returns the file size in bytes."""
    if os.path.isfile(filepath):
        return os.path.getsize(filepath)
    else:
        raise FileNotFoundError(f"No such file: {filepath}")
def get_file_size_human(filepath):
    """Returns the file size in a human-readable format."""
    if not os.path.isfile(filepath):
        raise FileNotFoundError(f"No such file: {filepath}")

    size_bytes = os.path.getsize(filepath)
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if size_bytes < 1024:
            return f"{size_bytes:.2f} {unit}"
        size_bytes /= 1024
