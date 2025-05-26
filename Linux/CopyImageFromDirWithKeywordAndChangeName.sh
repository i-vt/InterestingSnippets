#!/bin/bash

# Usage: ./copy_images_with_uuid.sh /path/to/source /path/to/target keyword

SOURCE_DIR="$1"
TARGET_DIR="$2"
KEYWORD="$3"

if [[ -z "$SOURCE_DIR" || -z "$TARGET_DIR" || -z "$KEYWORD" ]]; then
  echo "Usage: $0 /path/to/source /path/to/target keyword"
  exit 1
fi

# Create target directory if it doesn't exist
mkdir -p "$TARGET_DIR"

# Find .jpg files whose directory path includes the keyword
find "$SOURCE_DIR" -type f -iname "*.jpg" | while read -r FILE; do
  DIR_PATH=$(dirname "$FILE")
  if [[ "$DIR_PATH" == *"$KEYWORD"* ]]; then
    UUID=$(uuidgen)
    cp "$FILE" "$TARGET_DIR/$UUID.jpg"
  fi
done

echo "Matching .jpg files copied with UUID filenames."
