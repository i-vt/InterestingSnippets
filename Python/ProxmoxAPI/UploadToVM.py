import json
import sys
import os
import base64
import time
import argparse
import requests
from proxmoxer import ProxmoxAPI
from requests.packages.urllib3.exceptions import InsecureRequestWarning

requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

CONFIG_FILE = 'config.json'
# We must use smaller chunks because the command line length is limited
CHUNK_SIZE = 10 * 1024  

def load_config():
    try:
        with open(CONFIG_FILE, 'r') as f: return json.load(f)
    except FileNotFoundError: sys.exit(f"Error: {CONFIG_FILE} not found.")

def connect_proxmox(config):
    return ProxmoxAPI(
        config['PROXMOX_HOST'],
        user=config['PROXMOX_USER'],
        token_name=config['TOKEN_ID'],
        token_value=config['TOKEN_SECRET'],
        verify_ssl=False,
        port=config['PROXMOX_PORT']
    )

def execute_command(proxmox, node, vmid, cmd):
    try:
        res = proxmox.nodes(node).qemu(vmid).agent.exec.post(command=cmd)
        pid = res['pid']
        while True:
            status = proxmox.nodes(node).qemu(vmid).agent('exec-status').get(pid=pid)
            if status['exited'] == 1:
                return status['exitcode'] == 0
            time.sleep(0.1)
    except Exception as e:
        print(f"Cmd Failed: {e}")
        return False

def upload_file(proxmox, node, vmid, local_path, remote_path):
    if not os.path.exists(local_path):
        sys.exit(f"Error: Local file '{local_path}' not found.")

    print(f"[-] Uploading '{local_path}' via Base64 injection...")

    # 1. Truncate/Create the file first
    cmd = ['/bin/bash', '-c', f'true > {remote_path}']
    execute_command(proxmox, node, vmid, cmd)

    with open(local_path, 'rb') as f:
        while True:
            chunk = f.read(CHUNK_SIZE)
            if not chunk: break
            
            # Encode chunk to base64
            b64_data = base64.b64encode(chunk).decode('utf-8')
            
            # Append chunk to remote file
            # command: echo "base64blob" | base64 -d >> /path/to/file
            cmd_str = f'echo "{b64_data}" | base64 -d >> {remote_path}'
            cmd = ['/bin/bash', '-c', cmd_str]
            
            success = execute_command(proxmox, node, vmid, cmd)
            if not success:
                print(f"[!] Chunk upload failed.")
                return

            sys.stdout.write(".")
            sys.stdout.flush()

    print(f"\n[+] Upload Complete: {remote_path}")

def main():
    parser = argparse.ArgumentParser(description='Upload file via Agent Exec')
    parser.add_argument('vmid', type=int)
    parser.add_argument('local_path')
    parser.add_argument('remote_path')
    args = parser.parse_args()

    config = load_config()
    proxmox = connect_proxmox(config)
    
    # Find Node
    node = next((n['node'] for n in proxmox.nodes.get() 
                 if proxmox.nodes(n['node']).qemu(args.vmid).status.current.get().get('status') == 'running'), None)
    
    if not node: sys.exit("VM not found/running.")

    upload_file(proxmox, node, args.vmid, args.local_path, args.remote_path)

if __name__ == "__main__":
    main()
