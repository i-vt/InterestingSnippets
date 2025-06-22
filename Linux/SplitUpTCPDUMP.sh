#!/bin/bash

# Directory to store pcap files
OUTPUT_DIR="/var/log/pcap"
# Interface to capture on
INTERFACE="eth0"
# File prefix
FILE_PREFIX="capture"
# Capture duration per file in seconds (10 minutes = 600 seconds)
ROTATE_TIME=600

# Ensure output directory exists
if [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR"
    if [ $? -ne 0 ]; then
        echo "Failed to create directory $OUTPUT_DIR"
        exit 1
    fi
fi

# Start capturing packets
tcpdump -i "$INTERFACE" \
        -w "$OUTPUT_DIR/${FILE_PREFIX}_%Y-%m-%d_%H-%M-%S.pcap" \
        -G "$ROTATE_TIME" \
        -nn -s 0
