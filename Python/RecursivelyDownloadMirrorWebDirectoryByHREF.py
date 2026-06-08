#!/usr/bin/env python3
"""
Mirror a Python http.server tree — zero external dependencies.

On the remote device (e.g. 10.1.1.1), run:
    python3 -m http.server 2020

Files are fetched through the OS's native tools:
  • Windows PowerShell  → Invoke-WebRequest
  • Windows cmd.exe     → curl  (bundled since Win 10 1803)
  • Linux / macOS / BSD → wget  (falls back to curl)
"""

import os
import platform
import shutil
import subprocess
from html.parser import HTMLParser
from urllib.parse import urljoin
from urllib.request import urlopen


# ── HTML link extractor (replaces bs4) ──────────────────────────────────────

class LinkParser(HTMLParser):
    """Collects every <a href=...> value from an HTML page."""

    def __init__(self):
        super().__init__()
        self.links = []

    def handle_starttag(self, tag, attrs):
        if tag == 'a':
            for name, value in attrs:
                if name == 'href' and value:
                    self.links.append(value)


# ── OS / shell detection ─────────────────────────────────────────────────────

def get_os_type():
    return platform.system().lower()


def find_command_interface():
    os_type = get_os_type()
    interpreters = {
        'windows': ['powershell.exe', 'cmd.exe'],
        'linux':   ['zsh', 'bash', 'dash', 'sh'],
        'darwin':  ['zsh', 'bash', 'sh'],
        'openbsd': ['ksh', 'sh'],
        'freebsd': ['sh', 'csh'],
    }
    if os_type not in interpreters:
        raise ValueError(f"Unsupported OS: {os_type}")
    for interp in interpreters[os_type]:
        path = shutil.which(interp)
        if path:
            return path
    raise RuntimeError(f"No suitable command interface found for {os_type}")


# ── Download command builder ─────────────────────────────────────────────────

def build_download_command(url, dest, interface_path):
    """Return the shell one-liner that saves *url* to *dest*."""
    iname = os.path.basename(interface_path).lower()

    if 'powershell' in iname:
        return f'Invoke-WebRequest -Uri "{url}" -OutFile "{dest}"'

    if 'cmd' in iname:                        # Windows cmd — ships with curl
        return f'curl -s -o "{dest}" "{url}"'

    # POSIX shells: prefer wget, fall back to curl
    if shutil.which('wget'):
        return f'wget -q -O "{dest}" "{url}"'
    if shutil.which('curl'):
        return f'curl -s -o "{dest}" "{url}"'

    raise RuntimeError("Neither wget nor curl found — install one and retry.")


# ── Command executor ─────────────────────────────────────────────────────────

def execute_command(command, interface_path):
    """Run *command* via *interface_path* without flashing a console window."""
    iname = os.path.basename(interface_path).lower()

    if 'cmd' in iname:
        flag = '/c'
    elif 'powershell' in iname:
        flag = '-Command'
    else:
        flag = '-c'

    print(f"[*] Executing: {command}")

    startupinfo = None
    if get_os_type() == 'windows':
        startupinfo = subprocess.STARTUPINFO()
        startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW

    result = subprocess.run(
        [interface_path, flag, command],
        capture_output=True,
        text=True,
        encoding='utf-8',
        errors='replace',
        startupinfo=startupinfo,
    )

    if result.stdout:
        print(f"    stdout: {result.stdout.strip()}")
    if result.stderr:
        print(f"    stderr: {result.stderr.strip()}")

    return result


# ── Core logic ───────────────────────────────────────────────────────────────

def list_entries(url):
    """Return absolute URLs for every entry in an http.server directory page."""
    with urlopen(url) as resp:
        html = resp.read().decode('utf-8', errors='replace')

    parser = LinkParser()
    parser.feed(html)

    base = url if url.endswith('/') else url + '/'
    entries = []
    for href in parser.links:
        # Skip parent-dir link, pure anchors, and query-string-only hrefs
        if not href or href == '../' or href.startswith('#') or href.startswith('?'):
            continue
        entries.append(urljoin(base, href))
    return entries


def download_from_server(url, dest_dir='.', _iface=None):
    """Recursively mirror the http.server tree rooted at *url* into *dest_dir*."""
    if _iface is None:
        _iface = find_command_interface()
        print(f"[+] Using command processor : {_iface}\n")

    os.makedirs(dest_dir, exist_ok=True)

    for entry_url in list_entries(url):
        if entry_url.endswith('/'):                     # sub-directory → recurse
            dir_name  = entry_url.rstrip('/').split('/')[-1]
            local_dir = os.path.join(dest_dir, dir_name)
            print(f"[>] Directory : {dir_name}/")
            download_from_server(entry_url, local_dir, _iface)
        else:                                           # file → download
            file_name = entry_url.split('/')[-1]
            dest_path = os.path.join(dest_dir, file_name)
            print(f"[*] Downloading : {file_name}")
            cmd    = build_download_command(entry_url, dest_path, _iface)
            result = execute_command(cmd, _iface)
            if result.returncode == 0:
                print(f"[+] Saved       : {dest_path}\n")
            else:
                print(f"[!] FAILED      : {file_name} (exit {result.returncode})\n")


# ── Entry point ──────────────────────────────────────────────────────────────

if __name__ == '__main__':
    SERVER_URL = 'http://10.1.1.1:2020'
    download_from_server(SERVER_URL)
