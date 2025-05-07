#!/bin/bash

# Get CPU idle percentage and compute usage
idle=$(sar 1 1 | grep "Average" | awk '{print $8}')

# Calculate CPU usage (integer only, no decimals)
usage=$(echo "100 - $idle" | bc | awk '{printf "%d", $1}')

# Format it to always have two digits
printf "CPU:%02d%%\n" "$usage"
