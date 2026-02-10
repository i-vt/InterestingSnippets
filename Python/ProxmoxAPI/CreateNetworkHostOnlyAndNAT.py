import json
import sys
from proxmoxer import ProxmoxAPI
import urllib3

# Disable SSL warnings for self-signed certificates
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

CONFIG_FILE = './config.json'

def load_config():
    try:
        with open(CONFIG_FILE, 'r') as f:
            return json.load(f)
    except Exception as e:
        print(f"Error loading config: {e}")
        sys.exit(1)

def connect_proxmox(config):
    print(f"Connecting to {config['PROXMOX_HOST']}...")
    try:
        proxmox = ProxmoxAPI(
            config['PROXMOX_HOST'],
            user=config['PROXMOX_USER'],
            token_name=config['TOKEN_ID'],
            token_value=config['TOKEN_SECRET'],
            verify_ssl=False,
            port=config['PROXMOX_PORT']
        )
        return proxmox
    except Exception as e:
        print(f"Connection failed: {e}")
        sys.exit(1)

def create_zone(proxmox, zone_id, zone_type="simple", **kwargs):
    try:
        existing_zones = proxmox.cluster.sdn.zones.get()
        if any(z['zone'] == zone_id for z in existing_zones):
            print(f"Zone '{zone_id}' already exists. Skipping.")
            return

        print(f"Creating Zone '{zone_id}'...")
        data = {'zone': zone_id, 'type': zone_type, 'ipam': 'pve'}
        data.update(kwargs)
        proxmox.cluster.sdn.zones.create(**data)
        print(f"Zone '{zone_id}' created.")
    except Exception as e:
        print(f"Failed to create zone '{zone_id}': {e}")

def create_vnet(proxmox, vnet_id, zone_id, alias=None):
    try:
        existing_vnets = proxmox.cluster.sdn.vnets.get()
        if any(v['vnet'] == vnet_id for v in existing_vnets):
            print(f"VNet '{vnet_id}' already exists. Skipping.")
            return

        print(f"Creating VNet '{vnet_id}' in Zone '{zone_id}'...")
        data = {'vnet': vnet_id, 'zone': zone_id}
        if alias:
            data['alias'] = alias
        proxmox.cluster.sdn.vnets.create(**data)
        print(f"VNet '{vnet_id}' created.")
    except Exception as e:
        print(f"Failed to create VNet '{vnet_id}': {e}")

def create_subnet(proxmox, vnet_id, cidr, gateway, snat=False):
    try:
        # Note: 'vnets' collection access requires calling the specific vnet ID
        existing_subnets = proxmox.cluster.sdn.vnets(vnet_id).subnets.get()
        
        if any(s['subnet'] == cidr for s in existing_subnets):
             print(f"Subnet '{cidr}' on '{vnet_id}' already exists. Skipping.")
             return

        print(f"Creating Subnet '{cidr}' on '{vnet_id}' (SNAT: {snat})...")
        data = {
            'type': 'subnet',
            'subnet': cidr,
            'gateway': gateway,
        }
        if snat:
            data['snat'] = 1
            
        proxmox.cluster.sdn.vnets(vnet_id).subnets.create(**data)
        print(f"Subnet '{cidr}' created.")

    except Exception as e:
        print(f"Failed to create subnet '{cidr}': {e}")

def apply_sdn(proxmox):
    print("Applying SDN configuration...")
    try:
        proxmox.cluster.sdn.put()
        print("SDN changes applied successfully.")
    except Exception as e:
        print(f"Failed to apply SDN changes: {e}")

def main():
    config = load_config()
    proxmox = connect_proxmox(config)

    # --- UPDATED NAMING CONVENTIONS ---
    # IDs must be <= 8 chars and alphanumeric (no underscores)
    
    # 1. Host Only Config
    HO_ZONE = "local"     # changed from local_z
    HO_VNET = "vhost"     # changed from vnet_host
    
    # 2. NAT Config
    NAT_ZONE = "public"   # changed from public_z
    NAT_VNET = "vnat"     # changed from vnet_nat
    NAT_CIDR = "10.10.10.0/24"
    NAT_GW   = "10.10.10.1"

    print("--- Starting SDN Configuration ---")

    # Create Host Only
    create_zone(proxmox, HO_ZONE, "simple")
    create_vnet(proxmox, HO_VNET, HO_ZONE, alias="HostOnly")

    # Create NAT
    create_zone(proxmox, NAT_ZONE, "simple")
    create_vnet(proxmox, NAT_VNET, NAT_ZONE, alias="NAT_Internet")
    
    # Create Subnet (This depends on the VNet existing successfully)
    create_subnet(proxmox, NAT_VNET, NAT_CIDR, NAT_GW, snat=True)

    # Apply
    apply_sdn(proxmox)
    
    print("--- Done ---")

if __name__ == "__main__":
    main()
