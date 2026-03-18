import os
import requests

def install_7zip():
    base_path = r"C:\ProgramData\sevenZip"
    seven_zip_exe = os.path.join(base_path, "7z.exe")

    # Check if 7z already exists
    if not os.path.exists(seven_zip_exe):

        # Create directory if missing
        if not os.path.exists(base_path):
            os.makedirs(base_path)

        # Download 7-Zip standalone binary
        url = "https://www.7-zip.org/a/7zr.exe"

        try:
            response = requests.get(url)

            with open(seven_zip_exe, 'wb') as f:
                f.write(response.content)

            # Set folder as hidden + system
            st(base_path)

        except Exception:
            return None
