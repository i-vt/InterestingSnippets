import subprocess

# Define the PowerShell command
command = ""
# Create the PowerShell command to be executed
powershell_command = ["powershell", "-Command", command]

# Run the command
process = subprocess.run(powershell_command, capture_output=True, text=True)

# Check if the command was executed successfully
if process.returncode == 0:
    print("Command executed successfully!")
    print("Output:")
    print(process.stdout)
else:
    print("Error in executing command:")
    print(process.stderr)
