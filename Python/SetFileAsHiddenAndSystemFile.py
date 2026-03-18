import ctypes
import os


def set_hidden_system(filepath: str) -> None:
    """
    Set file attributes to HIDDEN | SYSTEM on Windows.

    :param filepath: Path to the file
    :raises FileNotFoundError: If the file does not exist
    :raises OSError: If setting attributes fails
    """
    if not os.path.exists(filepath):
        raise FileNotFoundError(f"File not found: {filepath}")

    FILE_ATTRIBUTE_HIDDEN = 0x02
    FILE_ATTRIBUTE_SYSTEM = 0x04

    result = ctypes.windll.kernel32.SetFileAttributesW(
        str(filepath),
        FILE_ATTRIBUTE_HIDDEN | FILE_ATTRIBUTE_SYSTEM
    )

    if result == 0:
        raise OSError(f"Failed to set attributes for: {filepath}")


# Example usage
if __name__ == "__main__":
    test_file = "example.txt"

    # Create file if it doesn't exist
    if not os.path.exists(test_file):
        with open(test_file, "w") as f:
            f.write("Test file")

    try:
        set_hidden_system(test_file)
        print(f"{test_file} is now hidden + system.")
    except Exception as e:
        print(f"Error: {e}")
