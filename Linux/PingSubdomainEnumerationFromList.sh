#!/bin/bash
host1=".example.com"
input_file="subdomains.txt"
log_file="successful_pings.log"

# Ensure the input file exists
if [[ ! -f "$input_file" ]]; then
  echo "Error: Input file '$input_file' not found."
  exit 1
fi

# Read each subdomain from the input file
while IFS= read -r subdomain; do
  value1="$subdomain$host1"
  if ping -c 1 "$value1" > /dev/null 2>&1; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $value1" >> "$log_file"
  fi
done < "$input_file"

echo "Script completed. Check $log_file for successful pings."
