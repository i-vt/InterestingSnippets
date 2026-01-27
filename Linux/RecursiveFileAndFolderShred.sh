#!/bin/bash

# ------------------------------------------------------------------
# CONFIGURATION
# ------------------------------------------------------------------
CORES=$(nproc)
# -n 3: 3 passes, -z: zero final pass, -u: remove file, -v: verbose
SHRED_OPTS="-n 3 -z -u -v"

# ------------------------------------------------------------------
# SAFETY CHECKS
# ------------------------------------------------------------------
if [ -z "$1" ]; then
    echo "Usage: $0 <directories_to_shred>"
    exit 1
fi

echo "---------------------------------------------------------"
echo "PARALLEL SECURE WIPE"
echo "Targets detected: $#"
echo "Workers: $CORES (Parallel processes)"
echo "Method: DoD Short (3 passes) + Zero Fill"
echo "---------------------------------------------------------"
echo "WARNING: This will DESTROY ALL DATA in:"
for target in "$@"; do
    echo " -> $target"
done
echo "---------------------------------------------------------"
read -p "Type 'DESTROY' to continue: " CONFIRM

if [ "$CONFIRM" != "DESTROY" ]; then
    echo "Aborted."
    exit 0
fi

# ------------------------------------------------------------------
# MAIN LOOP (Handles multiple arguments like ./Rz*)
# ------------------------------------------------------------------

for TARGET_DIR in "$@"; do
    echo "Processing: $TARGET_DIR"

    if [ ! -d "$TARGET_DIR" ]; then
        echo "Warning: '$TARGET_DIR' is not a directory or does not exist. Skipping."
        continue
    fi

    # PHASE 1: PARALLEL FILE SHREDDING
    # Added '-r' (no-run-if-empty) to xargs to fix the 'missing file operand' error
    find "$TARGET_DIR" -type f -print0 | xargs -0 -r -n 1 -P "$CORES" shred $SHRED_OPTS

    # PHASE 2: RANDOMIZE AND REMOVE DIRECTORIES
    # Process depth-first to remove children before parents
    find "$TARGET_DIR" -depth -type d | while read dir; do
        
        # Check if directory is empty (files should be gone by now)
        if [ -z "$(ls -A "$dir")" ]; then
            # If it is the top-level target argument, just remove it
            if [ "$dir" == "$TARGET_DIR" ]; then
                rmdir "$dir"
                echo "Wiped root: $dir"
                continue
            fi

            # 1. Randomize Name
            NEW_NAME=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 12 | head -n 1)
            PARENT=$(dirname "$dir")
            
            # 2. Rename & Remove
            mv "$dir" "$PARENT/$NEW_NAME"
            rmdir "$PARENT/$NEW_NAME"
        else
            echo "Skipping non-empty directory: $dir (Check manually)"
        fi
    done
done

echo "---------------------------------------------------------"
echo "All targets processed."
