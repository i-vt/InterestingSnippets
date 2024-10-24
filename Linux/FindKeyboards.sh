#!/bin/bash

# Function to log messages with timestamps
log_message() {
    local message=$1
    echo "$(date) - $message" >> /path/to/output_file.txt
}

# Function to check if a given event device is a keyboard
check_if_keyboard() {
    local device=$1
    
    # Use udevadm info to get the device information and grep for "keyboard"
    if udevadm info --query=all --name="$device" | grep -i "keyboard" >/dev/null; then
        log_message "$device is a keyboard."
    else
        log_message "$device is not a keyboard."
    fi
}

# Infinite loop to keep checking devices
while true; do
    # Loop through all /dev/input/event* devices
    found_device=false
    for device in /dev/input/event*; do
        if [ -e "$device" ]; then
            check_if_keyboard "$device"
            found_device=true
        fi
    done

    # If no devices were found, log a message
    if ! $found_device; then
        log_message "No input devices found."
    fi

    # Sleep for a while before checking again
    sleep 2
done
