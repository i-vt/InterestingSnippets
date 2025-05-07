#!/bin/bash

# Read MemTotal and MemAvailable from /proc/meminfo
mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
mem_available=$(grep MemAvailable /proc/meminfo | awk '{print $2}')

# Calculate used memory
mem_used=$((mem_total - mem_available))

# Calculate percentage (no decimals)
mem_used_percent=$(( (mem_used * 100) / mem_total ))

# Output
printf "RAM:%02d%%\n" "$mem_used_percent"
