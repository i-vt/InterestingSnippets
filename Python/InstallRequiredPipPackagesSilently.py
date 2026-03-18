import os
import subprocess

# Install required packages silently
packages = ["cryptography", "fernet", "requests"]

for package in packages:
    subprocess.run(
        ["pip", "install", package],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )

# Imports after installation
from fernet import Fernet
import requests
