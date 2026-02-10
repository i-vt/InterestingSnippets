import requests
import urllib3
import json
import sys
import os

# Suppress SSL warnings for self-signed certs
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

CONFIG_FILE = "config.json"

def load_config():
    """Loads configuration from the json file."""
    if not os.path.exists(CONFIG_FILE):
        print(f"❌ Error: {CONFIG_FILE} not found.")
        sys.exit(1)
        
    try:
        with open(CONFIG_FILE, 'r') as f:
            return json.load(f)
    except json.JSONDecodeError:
        print(f"❌ Error: {CONFIG_FILE} is not valid JSON.")
        sys.exit(1)

def test_proxmox_connection():
    # 1. Load Configuration
    config = load_config()
    
    # 2. Extract variables
    try:
        host = config["PROXMOX_HOST"]
        port = config.get("PROXMOX_PORT", 8006) # Default to 8006 if missing
        user = config["PROXMOX_USER"]
        token_id = config["TOKEN_ID"]
        token_secret = config["TOKEN_SECRET"]
    except KeyError as e:
        print(f"❌ Error: Missing key {e} in {CONFIG_FILE}")
        sys.exit(1)

    # 3. Construct URL and Auth Header
    # Header format: PVEAPIToken=USER@REALM!TOKENID=UUID
    auth_header = f"PVEAPIToken={user}!{token_id}={token_secret}"
    base_url = f"https://{host}:{port}/api2/json"
    
    headers = {
        "Authorization": auth_header,
        "Content-Type": "application/json"
    }

    print(f"Testing connection to {base_url}...")
    print(f"User: {user} | Token ID: {token_id}")

    # 4. Make the Request
    try:
        response = requests.get(f"{base_url}/version", headers=headers, verify=False)
        
        if response.status_code == 200:
            data = response.json()
            print("\n✅ Success! Connection established.")
            print(f"Proxmox Version: {data['data']['version']}-{data['data']['release']}")
            print(f"Repo ID: {data['data']['repoid']}")
            
        elif response.status_code == 401:
            print("\n❌ Authentication Failed (401).")
            print("Please verify the following in config.json:")
            print(f"1. Is TOKEN_SECRET correct? (Currently ends in ...{token_secret[-4:]})")
            print(f"2. Does the Token ID '{token_id}' exist for user '{user}'?")
            
        else:
            print(f"\n⚠️ Request failed: {response.status_code}")
            print(response.text)

    except requests.exceptions.ConnectionError:
        print(f"\n❌ Could not connect to https://{host}:{port}")
        print("Check if the host is reachable and the port is correct.")
    except Exception as e:
        print(f"\n❌ Unexpected Error: {e}")

if __name__ == "__main__":
    test_proxmox_connection()
