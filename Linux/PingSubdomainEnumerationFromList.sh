#!/bin/bash
host1=".example.com"
input_file="subdomains.txt"
log_file="successful_pings.log"

# Ensure the input file exists
if [[ ! -f "$input_file" ]]; then
  echo "Error: Input file '$input_file' not found."
  exit 1
fi

# Create or clear the log file
> "$log_file"

# Function to handle pinging
ping_subdomain() {
  local subdomain=$1
  local value1="$subdomain$host1"
  if ping -c 1 "$value1" > /dev/null 2>&1; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $value1" >> "$log_file"
  fi
}

export -f ping_subdomain
export host1
export log_file

# Use xargs to process in parallel
cat "$input_file" | xargs -I {} -P 10 bash -c 'ping_subdomain "$@"' _ {}

echo "Script completed. Check $log_file for successful pings."
