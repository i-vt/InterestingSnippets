#!/bin/bash
# ufw-allow-ip-port.sh
# Usage: sudo ./ufw-allow-ip-port.sh <IP_ADDRESS> <PORT>

# Exit if not run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root. Try: sudo $0 <IP> <PORT>"
   exit 1
fi

# Check args
if [[ $# -ne 2 ]]; then
   echo "Usage: $0 <IP_ADDRESS> <PORT>"
   exit 1
fi

IP=$1
PORT=$2

echo "Allowing inbound access on port $PORT from $IP..."
ufw allow from "$IP" to any port "$PORT"

echo "Allowing outbound access to $IP on port $PORT..."
ufw allow out to "$IP" port "$PORT"

echo "Reloading UFW..."
ufw reload

echo "Done. Current UFW status:"
ufw status verbose
