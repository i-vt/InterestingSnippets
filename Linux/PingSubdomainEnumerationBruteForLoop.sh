#!/bin/bash
host1=".example.com"
chars="abcdefghijklmnopqrstuvwxyz0123456789"
log_file="successful_pings.log"

for c1 in {a..z} {0..9}; do
  for c2 in {a..z} {0..9}; do
    for c3 in {a..z} {0..9}; do
      value1="$c1$c2$c3$host1"
      if ping -c 1 "$value1" > /dev/null 2>&1; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - $value1" >> "$log_file"
      fi
    done
  done
done

echo "Script completed. Check $log_file for successful pings."
