import os
import random

def secure_delete(file_path, passes=3):
    """
    FYI: on SSDs this might not work, flash storage may not honor overwrites due to wear leveling.
    """
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
