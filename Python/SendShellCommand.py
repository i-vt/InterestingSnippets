import subprocess

command = 'ls -l /nonexistent_directory'

try:
    result = subprocess.run(
        command,
        capture_output=True,
        text=True,
        shell=True
    )

    stdout = result.stdout
    stderr = result.stderr

    if result.returncode == 0:
        print("Command succeeded with output:")
        print(stdout)
    else:
        print("Command failed with error:")
        print(stderr)

except Exception as e:
    print(f"An error occurred: {e}")
