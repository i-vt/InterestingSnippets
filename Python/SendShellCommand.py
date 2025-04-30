import subprocess

def run_shell_command(command):
    """
    Executes a shell command and prints the result.

    Args:
        command (str): The shell command to execute.

    Returns:
        dict: A dictionary containing 'success' (bool), 'stdout' (str), and 'stderr' (str).
    """
    try:
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            shell=True
        )

        if result.returncode == 0:
            print("Command succeeded with output:")
            print(result.stdout)
            return {"success": True, "stdout": result.stdout, "stderr": ""}
        else:
            print("Command failed with error:")
            print(result.stderr)
            return {"success": False, "stdout": "", "stderr": result.stderr}

    except Exception as e:
        print(f"An error occurred: {e}")
        return {"success": False, "stdout": "", "stderr": str(e)}

# run_shell_command('ls -l /nonexistent_directory')
