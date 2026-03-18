import subprocess

def extract_archive(archive_path, output_dir):
    seven_zip_path = r"C:\ProgramData\sevenZip\7z.exe"
    archive_password = "123412341234AAa"

    powershell_cmd = (
        f'Start-Process -Wait -WindowStyle Hidden '
        f'-FilePath "{seven_zip_path}" '
        f'-ArgumentList '
        f'\'x\', '
        f'\'"{archive_path}"\', '
        f'\'-o"{output_dir}"\', '
        f'\'-p{archive_password}\', '
        f"'-y'"
    )

    try:
        subprocess.run(
            ["powershell", "-Command", powershell_cmd],
            capture_output=True,
            text=True,
            check=True,
            creationflags=subprocess.CREATE_NO_WINDOW,
        )
    except subprocess.CalledProcessError:
        return None
