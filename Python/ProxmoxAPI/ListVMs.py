import json
import sys
from proxmoxer import ProxmoxAPI
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
CONFIG_FILE = './config.json'

def get_proxmox_connection():
    try:
        with open(CONFIG_FILE, 'r') as f:
            config = json.load(f)
        return ProxmoxAPI(
            config['PROXMOX_HOST'],
            user=config['PROXMOX_USER'],
            token_name=config['TOKEN_ID'],
            token_value=config['TOKEN_SECRET'],
            verify_ssl=False,
            port=config['PROXMOX_PORT']
        )
    except Exception as e:
        print(f"Error connecting: {e}")
        sys.exit(1)

def main():
    proxmox = get_proxmox_connection()
    
    print(f"{'VMID':<10} {'NAME':<20} {'STATUS':<15} {'NODE':<15}")
    print("-" * 60)

    # valid resource types: vm, storage, node, sdn
    for vm in proxmox.cluster.resources.get(type='vm'):
        vmid = vm.get('vmid')
        name = vm.get('name', 'N/A')
        status = vm.get('status', 'unknown')
        node = vm.get('node')
        
        print(f"{vmid:<10} {name:<20} {status:<15} {node:<15}")

if __name__ == "__main__":
    main()
