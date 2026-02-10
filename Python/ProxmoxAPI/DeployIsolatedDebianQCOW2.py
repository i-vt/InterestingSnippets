import json
import secrets
import string
import time
import sys
import subprocess
import requests
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from proxmoxer import ProxmoxAPI
from requests.packages.urllib3.exceptions import InsecureRequestWarning

# Suppress certificate warnings
requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

# --- CONFIGURATION ---
CONFIG_FILE = 'config.json'
QCOW2_PATH = '/root/debian-13-generic-amd64-daily.qcow2' 
INTERNAL_BRIDGE = 'vmbr99' 
VM_PREFIX = "isolated-lab"
SUBNET_BASE = "192.168.99" 

def load_config():
    try:
        with open(CONFIG_FILE, 'r') as f:
            return json.load(f)
    except FileNotFoundError:
        sys.exit(f"Error: {CONFIG_FILE} not found.")

def get_node_and_storage(proxmox):
    nodes = proxmox.nodes.get()
    node_name = next((n['node'] for n in nodes if n['status'] == 'online'), None)
    if not node_name:
        sys.exit("Error: No online nodes found.")

    disk_store = None
    storage_list = proxmox.nodes(node_name).storage.get()
    for s in storage_list:
        sid = s['storage']
        if 'images' in s.get('content', ''):
            if disk_store is None or 'lvm' in sid or 'thin' in sid:
                disk_store = sid
    
    if not disk_store:
        sys.exit("Error: No storage found for VM images.")
    return node_name, disk_store

def ensure_internal_network(proxmox, node):
    networks = proxmox.nodes(node).network.get()
    existing = next((net for net in networks if net['iface'] == INTERNAL_BRIDGE), None)
    if existing: return

    print(f"[-] Creating isolated network: {INTERNAL_BRIDGE}...")
    try:
        proxmox.nodes(node).network.post(
            iface=INTERNAL_BRIDGE, type='bridge', autostart=1, bridge_ports='', 
            comments='Created by Python Script - Internal Only'
        )
        proxmox.nodes(node).network.put()
        time.sleep(5) 
    except Exception as e:
        print(f"Error creating network: {e}")

def run_ssh_import(config, vmid, storage):
    """Imports disk using SSH Key authentication (No Password Prompt)."""
    cmd = [
        "ssh", 
        "-o", "StrictHostKeyChecking=no",
        "-i", config['SSH_KEY_PATH'],  # Use key from config
        f"{config['SSH_USER']}@{config['PROXMOX_HOST']}",
        f"qm importdisk {vmid} {QCOW2_PATH} {storage}"
    ]

    try:
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"[VM {vmid}] SSH Error: {result.stderr}")
            return False
        return True
    except Exception as e:
        print(f"[VM {vmid}] SSH Execution Failed: {e}")
        return False

def wait_for_agent(proxmox, node, vmid, timeout=60):
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            proxmox.nodes(node).qemu(vmid).agent.get('info')
            return True
        except Exception:
            time.sleep(2)
    return False

def run_vm_command(proxmox, node, vmid, command):
    try:
        exec_res = proxmox.nodes(node).qemu(vmid).agent.exec.post(command=command)
        pid = exec_res['pid']
        while True:
            status = proxmox.nodes(node).qemu(vmid).agent('exec-status').get(pid=pid)
            if status['exited'] == 1:
                if 'out-data' in status: return status['out-data'].strip()
                return "Done"
            time.sleep(0.5)
    except Exception:
        return None

def deploy_single_vm(proxmox, config, node, storage, vmid):
    """The worker function for thread execution."""
    try:
        username = "debian"
        alphabet = string.ascii_letters + string.digits
        password = ''.join(secrets.choice(alphabet) for _ in range(16))
        vm_name = f"{VM_PREFIX}-{vmid}"
        
        # Calculate Static IP
        last_octet = vmid % 255
        if last_octet == 0: last_octet = 254
        static_ip = f"{SUBNET_BASE}.{last_octet}/24"

        print(f"[*] Starting VM {vmid} (IP: {static_ip})...")

        # 1. Create VM Shell
        vm_config = {
            'vmid': vmid, 'name': vm_name, 'memory': 2048, 'cores': 2, 'sockets': 1,
            'net0': f'virtio,bridge={INTERNAL_BRIDGE}', 'scsihw': 'virtio-scsi-pci',
            'ide2': f'{storage}:cloudinit', 'ostype': 'l26', 'serial0': 'socket', 
            'vga': 'serial0', 'agent': 1,
            'description': f"Cloud Image Deployment\nUser: {username}\nPass: {password}"
        }
        proxmox.nodes(node).qemu.create(**vm_config)

        # 2. Configure Cloud-Init
        proxmox.nodes(node).qemu(vmid).config.post(
            ciuser=username, cipassword=password, ipconfig0=f'ip={static_ip}'
        )

        # 3. Import Disk (SSH)
        if not run_ssh_import(config, vmid, storage):
            return None

        # 4. Attach & Resize
        proxmox.nodes(node).qemu(vmid).config.post(
            scsi0=f"{storage}:vm-{vmid}-disk-0,ssd=1,discard=on", boot="order=scsi0"
        )
        proxmox.nodes(node).qemu(vmid).resize.put(disk='scsi0', size='+2G')

        # 5. Start
        time.sleep(1)
        proxmox.nodes(node).qemu(vmid).status.start.post()

        # 6. Verify Agent
        if wait_for_agent(proxmox, node, vmid):
            check_ip = run_vm_command(proxmox, node, vmid, ['/usr/bin/hostname', '-I'])
            return {"vmid": vmid, "status": "SUCCESS", "ip": check_ip, "user": username, "pass": password}
        else:
            return {"vmid": vmid, "status": "WARN: Agent Timeout", "ip": static_ip, "user": username, "pass": password}

    except Exception as e:
        return {"vmid": vmid, "status": f"FAILED: {str(e)}"}

def main():
    # Parse Command Line Arguments
    parser = argparse.ArgumentParser(description='Deploy parallel Proxmox VMs')
    parser.add_argument('count', type=int, nargs='?', default=1, help='Number of VMs to create')
    args = parser.parse_args()
    
    config = load_config()
    
    # Initialize API
    try:
        proxmox = ProxmoxAPI(
            config['PROXMOX_HOST'], user=config['PROXMOX_USER'],
            token_name=config['TOKEN_ID'], token_value=config['TOKEN_SECRET'],
            verify_ssl=False, port=config['PROXMOX_PORT']
        )
    except Exception as e:
        sys.exit(f"Connection Failed: {e}")

    node, disk_store = get_node_and_storage(proxmox)
    ensure_internal_network(proxmox, node)

    # Calculate VM IDs beforehand to avoid race conditions
    print(f"[-] Calculating IDs for {args.count} VMs...")
    cluster_resources = proxmox.cluster.resources.get(type='vm')
    existing_ids = [int(vm['vmid']) for vm in cluster_resources]
    start_id = max(existing_ids) + 1 if existing_ids else 100
    
    vm_ids = [start_id + i for i in range(args.count)]
    
    print(f"[-] Launching Parallel Deployment for IDs: {vm_ids}")
    
    # Run Parallel Execution
    results = []
    with ThreadPoolExecutor(max_workers=5) as executor:
        # Submit all tasks
        future_to_vmid = {
            executor.submit(deploy_single_vm, proxmox, config, node, disk_store, vmid): vmid 
            for vmid in vm_ids
        }
        
        # Process results as they finish
        for future in as_completed(future_to_vmid):
            res = future.result()
            if res:
                results.append(res)
                print(f"[+] VM {res.get('vmid')} finished: {res.get('status')}")

    print("\n" + "="*60)
    print("FINAL REPORT")
    print("="*60)
    for r in sorted(results, key=lambda x: x.get('vmid', 0)):
        if "FAILED" in r['status']:
             print(f"VM {r.get('vmid', 'Unknown')}: FAILED deployment")
        else:
            print(f"VM {r['vmid']} | IP: {r['ip']}")
            print(f"User: {r['user']} | Pass: {r['pass']}")
        print("-" * 60)

if __name__ == "__main__":
    main()
