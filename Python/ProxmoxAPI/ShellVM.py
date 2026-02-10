import json
import sys
import time
import requests
import argparse
from proxmoxer import ProxmoxAPI
from requests.packages.urllib3.exceptions import InsecureRequestWarning

# Suppress certificate warnings
requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

CONFIG_FILE = 'config.json'
VM_PREFIX = "isolated-lab"

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

def get_active_vms(proxmox):
    """Finds all running VMs matching our lab prefix."""
    nodes = proxmox.nodes.get()
    active_vms = []

    print("[-] Scanning for active lab VMs...")
    for node in nodes:
        if node['status'] != 'online': continue
        
        node_name = node['node']
        vms = proxmox.nodes(node_name).qemu.get()
        
        for vm in vms:
            # Filter by name prefix and running status
            if vm.get('name', '').startswith(VM_PREFIX) and vm['status'] == 'running':
                active_vms.append({
                    'vmid': vm['vmid'],
                    'name': vm['name'],
                    'node': node_name
                })
    return active_vms

def execute_command(proxmox, node, vmid, cmd_string):
    """Sends command via Agent and waits for output."""
    try:
        # Wrap command in bash -c to support pipes and redirects
        # e.g. "ls -la | grep root"
        payload = ['/bin/bash', '-c', cmd_string]
        
        # 1. POST command
        res = proxmox.nodes(node).qemu(vmid).agent.exec.post(command=payload)
        pid = res['pid']
        
        # 2. POLL status
        while True:
            status = proxmox.nodes(node).qemu(vmid).agent('exec-status').get(pid=pid)
            if status['exited'] == 1:
                # Combine stdout and stderr for the user
                output = ""
                if 'out-data' in status: output += status['out-data']
                if 'err-data' in status: output += f"\n[stderr]\n{status['err-data']}"
                
                # Strip trailing newlines for cleaner shell look
                return output.strip()
            time.sleep(0.2)
            
    except Exception as e:
        return f"[Error] Agent communication failed: {e}"

def shell_session(proxmox, vm):
    """The interactive loop."""
    vmid = vm['vmid']
    node = vm['node']
    name = vm['name']
    
    print("="*60)
    print(f"Connected to {name} (ID: {vmid})")
    print("Type 'exit' to go back to menu, 'quit' to close script.")
    print("NOTE: commands are stateless. Use 'cd /folder && ls' to browse.")
    print("="*60)

    while True:
        try:
            # mimic a prompt: root@isolated-lab-100:~# 
            cmd = input(f"\033[92mroot@{name}\033[0m:~# ")
            
            if not cmd.strip(): continue
            if cmd.lower() == 'exit': break
            if cmd.lower() == 'quit': sys.exit(0)
            if cmd.lower() == 'clear': 
                print("\033c", end="")
                continue

            # Execute
            output = execute_command(proxmox, node, vmid, cmd)
            if output:
                print(output)
                
        except KeyboardInterrupt:
            print("\nType 'exit' to leave shell.")
        except Exception as e:
            print(f"Shell Error: {e}")

def main():
    config = load_config()
    proxmox = connect_proxmox(config)

    while True:
        vms = get_active_vms(proxmox)
        
        if not vms:
            print("[!] No running lab VMs found.")
            sys.exit(0)

        print("\nAvailable VMs:")
        print(f"{'#':<4} {'VMID':<10} {'Name':<25} {'Node'}")
        print("-" * 50)
        
        for i, vm in enumerate(vms):
            print(f"{i+1:<4} {vm['vmid']:<10} {vm['name']:<25} {vm['node']}")

        print("-" * 50)
        choice = input("Select VM # (or 'q' to quit): ")
        
        if choice.lower() == 'q': break
        
        try:
            idx = int(choice) - 1
            if 0 <= idx < len(vms):
                shell_session(proxmox, vms[idx])
            else:
                print("Invalid selection.")
        except ValueError:
            print("Please enter a number.")

if __name__ == "__main__":
    main()
