#!/bin/bash
set -euo pipefail

# ── Usage ──────────────────────────────────────────────
# ./deploy.sh <repo_ssh_url> <zip_file> [commit_message]
#
# Examples:
#   ./deploy.sh git@github.com:i-vt/EraseableChatApp.git ~/Downloads/update.zip
#   ./deploy.sh git@github.com:user/repo.git ./build.zip "v2.0 release"

REPO_URL="${1:?Usage: $0 <repo_ssh_url> <zip_file> [commit_message]}"
ZIP_FILE="${2:?Usage: $0 <repo_ssh_url> <zip_file> [commit_message]}"
COMMIT_MSG="${3:-Deploy update $(date '+%Y-%m-%d %H:%M:%S')}"
BRANCH="${BRANCH:-main}"

# Resolve zip to absolute path before we cd anywhere
ZIP_FILE="$(realpath "$ZIP_FILE")"

if [[ ! -f "$ZIP_FILE" ]]; then
  echo "Error: zip file not found: $ZIP_FILE"
  exit 1
fi

# Extract repo name from URL for the temp directory
REPO_NAME="$(basename "$REPO_URL" .git)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "── Cloning $REPO_NAME ($BRANCH) ──"
git clone --branch "$BRANCH" --single-branch "$REPO_URL" "$WORK_DIR/$REPO_NAME"
cd "$WORK_DIR/$REPO_NAME"

# Remove everything except .git so the zip becomes the new truth
find . -maxdepth 1 ! -name '.git' ! -name '.' -exec rm -rf {} +

echo "── Extracting $ZIP_FILE ──"
unzip -o "$ZIP_FILE"

echo "── Staging changes ──"
git add -A

if git diff --cached --quiet; then
  echo "Nothing changed — skipping push."
  exit 0
fi

echo "── Committing ──"
git commit -m "$COMMIT_MSG"

echo "── Pushing to $BRANCH ──"
git push origin "$BRANCH"

echo "── Done ──"
