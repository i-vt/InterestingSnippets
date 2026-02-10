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

def attach_network(proxmox, node, vmid, vnet, interface="net1"):
    """
    Attaches a bridge (VNet) to a specific VM network interface.
    """
    print(f"Attaching VNet '{vnet}' to VM {vmid} on interface {interface}...")
    
    # Construct the network device string
    # Format: model=<model>,bridge=<bridge>
    # Example: virtio,bridge=vnat
    net_config_string = f"virtio,bridge={vnet}"
    
    try:
        # We use .config.post() to update configuration
        # This requires the specific Node name where the VM lives
        proxmox.nodes(node).qemu(vmid).config.post(**{
            interface: net_config_string
        })
        print(f"Success! {interface} configured with bridge '{vnet}'.")
        print("Note: You may need to reboot the VM or bring up the interface inside the OS.")
    except Exception as e:
        print(f"Failed to attach network: {e}")

def main():
    proxmox = get_proxmox_connection()

    # --- INPUTS ---
    # You can change these or make them command line arguments
    TARGET_VMID = 100         # Change this to your VM ID
    TARGET_VNET = "vnat"      # Options: 'vnat' or 'vhost' (from previous script)
    INTERFACE_ID = "net1"     # Keeping net1 to avoid breaking management (net0)

    # 1. Find the node the VM is running on automatically
    target_node = None
    for vm in proxmox.cluster.resources.get(type='vm'):
        if int(vm.get('vmid')) == TARGET_VMID:
            target_node = vm.get('node')
            break
            
    if not target_node:
        print(f"Error: VM {TARGET_VMID} not found in cluster.")
        sys.exit(1)

    # 2. Attach the network
    attach_network(proxmox, target_node, TARGET_VMID, TARGET_VNET, INTERFACE_ID)

if __name__ == "__main__":
    main()
