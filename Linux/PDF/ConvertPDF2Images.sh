#!/bin/bash

# Usage: ./convert.sh input.pdf output_prefix

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 input.pdf output_prefix"
    exit 1
fi

INPUT="$1"
OUTPUT="$2"

# Update package lists
sudo apt update

# Install poppler-utils (contains pdftoppm)
sudo apt install -y poppler-utils

# Convert PDF to PNG images (e.g., output_prefix-1.png, output_prefix-2.png, ...)
pdftoppm "$INPUT" "$OUTPUT" -png
