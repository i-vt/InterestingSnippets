import json
import sys
import base64
import time
import argparse
import requests
from proxmoxer import ProxmoxAPI
from requests.packages.urllib3.exceptions import InsecureRequestWarning

requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

CONFIG_FILE = 'config.json'

def load_config():
    try:
        with open(CONFIG_FILE, 'r') as f: return json.load(f)
    except: sys.exit("Config Error")

def connect_proxmox(config):
    return ProxmoxAPI(
        config['PROXMOX_HOST'],
        user=config['PROXMOX_USER'],
        token_name=config['TOKEN_ID'],
        token_value=config['TOKEN_SECRET'],
        verify_ssl=False,
        port=config['PROXMOX_PORT']
    )

def download_file(proxmox, node, vmid, remote_path, local_path):
    print(f"[-] Downloading {remote_path}...")

    # Command: cat file | base64 -w 0 (no line wrapping)
    cmd = ['/bin/bash', '-c', f'cat {remote_path} | base64 -w 0']

    try:
        # Execute
        res = proxmox.nodes(node).qemu(vmid).agent.exec.post(command=cmd)
        pid = res['pid']

        # Wait
        while True:
            status = proxmox.nodes(node).qemu(vmid).agent('exec-status').get(pid=pid)
            if status['exited'] == 1:
                if status['exitcode'] != 0:
                    print(f"[!] Error reading file inside VM.")
                    return
                
                # Get the base64 string from stdout
                b64_data = status.get('out-data', '')
                if not b64_data:
                    print("[!] File appears empty or read failed.")
                    return

                # Decode and Save
                with open(local_path, 'wb') as f:
                    f.write(base64.b64decode(b64_data))
                
                print(f"[+] Download saved to: {local_path}")
                return
            time.sleep(0.5)

    except Exception as e:
        print(f"[!] Download Failed: {e}")

def main():
    parser = argparse.ArgumentParser(description='Download file via Agent Exec')
    parser.add_argument('vmid', type=int)
    parser.add_argument('remote_path')
    parser.add_argument('local_path')
    args = parser.parse_args()

    config = load_config()
    proxmox = connect_proxmox(config)

    node = next((n['node'] for n in proxmox.nodes.get() 
                 if proxmox.nodes(n['node']).qemu(args.vmid).status.current.get().get('status') == 'running'), None)
    
    if not node: sys.exit("VM not found/running.")

    download_file(proxmox, node, args.vmid, args.remote_path, args.local_path)

if __name__ == "__main__":
    main()
