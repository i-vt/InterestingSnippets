import json
import sys
import time
import argparse
import requests
from proxmoxer import ProxmoxAPI
from requests.packages.urllib3.exceptions import InsecureRequestWarning

# Suppress certificate warnings
requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

CONFIG_FILE = 'config.json'

def load_config():
    try:
        with open(CONFIG_FILE, 'r') as f:
            return json.load(f)
    except FileNotFoundError:
        sys.exit(f"Error: {CONFIG_FILE} not found.")

def connect_proxmox(config):
    try:
        return ProxmoxAPI(
            config['PROXMOX_HOST'],
            user=config['PROXMOX_USER'],
            token_name=config['TOKEN_ID'],
            token_value=config['TOKEN_SECRET'],
            verify_ssl=False,
            port=config['PROXMOX_PORT']
        )
    except Exception as e:
        sys.exit(f"Connection Failed: {e}")

def find_vm(proxmox, vmid):
    """Scans all nodes to find where the VM lives."""
    nodes = proxmox.nodes.get()
    for node in nodes:
        node_name = node['node']
        try:
            # Check if VM exists on this node
            proxmox.nodes(node_name).qemu(vmid).status.current.get()
            return node_name
        except Exception:
            continue
    return None

def stop_and_delete(proxmox, node, vmid):
    print(f"[-] specific VM {vmid} found on node '{node}'")
    
    # 1. Check Status
    status = proxmox.nodes(node).qemu(vmid).status.current.get()
    if status['status'] == 'running':
        print(f"[-] VM {vmid} is running. Stopping...")
        try:
            # Try graceful shutdown first
            proxmox.nodes(node).qemu(vmid).status.shutdown.post()
            
            # Wait 10s then force stop if needed
            for _ in range(10):
                s = proxmox.nodes(node).qemu(vmid).status.current.get()
                if s['status'] == 'stopped': break
                time.sleep(1)
            else:
                print(f"[!] Shutdown timed out. Forcing STOP.")
                proxmox.nodes(node).qemu(vmid).status.stop.post()
                time.sleep(2)
        except Exception as e:
            print(f"[!] Error stopping VM: {e}")

    # 2. Delete
    print(f"[-] Deleting VM {vmid} and all disks...")
    try:
        task = proxmox.nodes(node).qemu(vmid).delete()
        print(f"[+] VM {vmid} Deleted Successfully. Task ID: {task}")
    except Exception as e:
        print(f"[!] Delete Failed: {e}")

def main():
    parser = argparse.ArgumentParser(description='Delete a Proxmox VM by ID')
    parser.add_argument('vmid', type=int, help=' The ID of the VM to delete')
    args = parser.parse_args()

    config = load_config()
    proxmox = connect_proxmox(config)

    print(f"[-] Searching for VM {args.vmid}...")
    node = find_vm(proxmox, args.vmid)

    if node:
        stop_and_delete(proxmox, node, args.vmid)
    else:
        print(f"[!] Error: VM {args.vmid} not found on any active node.")

if __name__ == "__main__":
    main()
