import os

def get_all_file_paths(start_dir="./"):
    """
    Walk through a directory and return a list of absolute file paths.
    
    :param start_dir: Directory to start searching from
    :return: List of absolute file paths
    """
    all_files = []

    for root, dirs, files in os.walk(start_dir):
        for file in files:
            full_path = os.path.abspath(os.path.join(root, file))
            all_files.append(full_path)

    return all_files


# Example usage
files = get_all_file_paths("./")
print(files)
