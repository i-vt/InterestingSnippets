#!/usr/bin/env bash

# Description: Convert a PDF into images and reassemble into a PDF
# Tested on: Debian 13

set -e

# -----------------------------
# Functions
# -----------------------------
check_and_install() {
    package=$1
    if ! dpkg -s "$package" >/dev/null 2>&1; then
        echo "[*] Installing $package..."
        sudo apt-get update
        sudo apt-get install -y "$package"
    else
        echo "[*] $package already installed."
    fi
}

# -----------------------------
# Dependency checks
# -----------------------------
echo "[*] Checking dependencies..."
check_and_install poppler-utils   # provides pdftoppm
check_and_install imagemagick     # provides convert

# -----------------------------
# Input validation
# -----------------------------
if [ $# -lt 1 ]; then
    echo "Usage: $0 input.pdf [output.pdf]"
    exit 1
fi

INPUT_PDF="$1"
OUTPUT_PDF="${2:-reassembled.pdf}"

BASENAME=$(basename "$INPUT_PDF" .pdf)
TMP_DIR="${BASENAME}_imgs"

# -----------------------------
# Conversion: PDF -> Images
# -----------------------------
echo "[*] Converting PDF to images..."
mkdir -p "$TMP_DIR"
pdftoppm -png "$INPUT_PDF" "$TMP_DIR/page"

# -----------------------------
# Reassembly: Images -> PDF
# -----------------------------
echo "[*] Reassembling images into PDF..."
convert "$TMP_DIR/page-"*.png "$OUTPUT_PDF"

echo "[*] Done!"
echo " - Input PDF:  $INPUT_PDF"
echo " - Output PDF: $OUTPUT_PDF"
echo " - Temp images stored in: $TMP_DIR"
