#!/bin/bash

# Directory to save PCAPs
LOG_DIR="/root/logs"

# Interface to capture from
INTERFACE="eth0"

# Duration of each capture in seconds (10 minutes)
CAPTURE_DURATION=600

# Ensure the log directory exists
mkdir -p "$LOG_DIR"

# Infinite loop to run tcpdump every 10 minutes
while true; do
    TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
    FILENAME="$LOG_DIR/capture_$TIMESTAMP.pcap"

    echo "Starting capture: $FILENAME"

    /usr/bin/tcpdump -i "$INTERFACE" -w "$FILENAME" -G "$CAPTURE_DURATION" -W 1 -nn -s 0 &
    wait

    echo "Finished capture: $FILENAME"
done

