#!/bin/sh

read -p "Enter IP addresses separated by ' ': " -a ips
read -p "Enter subfolder for results: " folder
read -p "Enter seconds to wait between probes: " wait_seconds
read -p "Enter count of pings per probe: " ping_count

ping_and_log() {
    local ip=$1
    local path=$2
    local count=$3
    echo "Pinging $ip..."
    {
        echo "$(date --rfc-3339=seconds) Pinging $ip"
        ping $ip -c $count | grep "transmitted" || echo "Ping failed for $ip"
        echo
    } >> "$path"
}


mkdir -p "$folder"
while true; do
    for ip in "${ips[@]}"; do
        path="$folder/$(date --rfc-3339=seconds)"
        touch "$path"
        ping_and_log $ip $path $ping_count
    done
    sleep $wait_seconds
done
