#!/bin/bash

# Check if a directory is provided as an argument
if [ $# -eq 0 ]; then
  echo "Usage: $0 <directory_path>"
  exit 1
fi

# The directory to scan
root_dir="$1"

# Check if the directory exists
if [ ! -d "$root_dir" ]; then
  echo "Directory not found: $root_dir"
  exit 1
fi

# Use find to recursively list all files and directories
find "$root_dir" -type f -exec bash -c '
  file="$1"
  # Use stat to fetch the modification time and format it
  mod_time=$(stat --format=%y "$file")

  # Extract date, time, and convert the date to day of the week
  date=$(date -d "$mod_time" +%Y%m%d)
  time=$(date -d "$mod_time" +%H%M:%S)
  day_of_week=$(date -d "$mod_time" +%A)

  # Print the result in the desired format
  echo "$file|$date|$time|$day_of_week"
' bash {} \;
