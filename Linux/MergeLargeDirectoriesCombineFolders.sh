#!/usr/bin/env bash
set -e

TARGET="public"
SRC1="step_images"
SRC2="converted_images"

echo "Creating target folder if it does not exist..."
mkdir -p "$TARGET"

move_files() {
  local SRC="$1"

  if [ -d "$SRC" ]; then
    echo "Moving files from $SRC -> $TARGET"
    find "$SRC" -type f -exec mv -t "$TARGET" -- {} +
  else
    echo "Skipping $SRC (folder does not exist)"
  fi
}

move_files "$SRC1"
move_files "$SRC2"

echo "Cleaning up empty source folders..."
rmdir "$SRC1" 2>/dev/null || true
rmdir "$SRC2" 2>/dev/null || true

echo "Done ✅"
