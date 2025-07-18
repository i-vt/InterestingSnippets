import os

def ensure_folder_exists(path):
    """
    Creates the folder at the given path if it does not already exist.

    Args:
        path (str): The directory path to ensure exists.
    """
    if not os.path.exists(path):
        os.makedirs(path)
        print(f"Created directory: {path}")
    else:
        print(f"Directory already exists: {path}")
