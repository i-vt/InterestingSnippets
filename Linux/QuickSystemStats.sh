#!/bin/bash

# Fetch RAM stats
mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
mem_available=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
mem_used=$((mem_total - mem_available))
mem_used_percent=$(( (mem_used * 100) / mem_total ))

# Fetch CPU usage
idle=$(sar 1 1 | grep "Average" | awk '{print $8}')
usage=$(echo "100 - $idle" | bc | awk '{printf "%d", $1}')

# Fetch disk space
available=$(df -h / | awk 'NR==2 {print $4}')

# Fetch external IP (timeout after 2 seconds)
ip=$(curl -s --max-time 2 https://api.ipify.org)
if [ -z "$ip" ]; then
  ip="No Public IP"
fi

# Output in desired format
printf "/:%s|CPU:%02d%%|RAM:%02d%%|%s\n" "$available" "$usage" "$mem_used_percent" "$ip" 
