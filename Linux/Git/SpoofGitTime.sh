#!/usr/bin/env bash
set -euo pipefail

# ---- Default variable values (override via CLI flags) ----
REPO="contribution-graph"
README_CONTENT="Auto-generated repository"
REPO_DESCRIPTION="Commit graph activity"
COMMIT_MESSAGE="Initial commit"
FAKE_DATE="1999-01-01T00:00:00"
PRIVATE=false
START_DATE=""
END_DATE=""

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --user USER          GitHub username (prompted if omitted)
  --token TOKEN        GitHub personal access token (prompted if omitted)
  --repo NAME          Name of the repository to create (default: $REPO)
  --readme TEXT        Content written to README.md
  --description TEXT   Repository description
  --message TEXT       Commit message
  --date ISO_DATE      Backdated commit timestamp (default: $FAKE_DATE)
  --start-date DATE    Range start for a random commit date (requires --end-date)
  --end-date DATE      Range end for a random commit date (requires --start-date)
  --private            Create the repository as private
  -h, --help           Show this help

DATE accepts anything 'date -d' understands, e.g. 2020-01-01 or "2020-06-15 14:30:00".
If both range flags are given, a random timestamp between them (inclusive) is used
instead of --date, and overrides it.
EOF
}

# ---- Parse arguments ----
while [[ $# -gt 0 ]]; do
    case "$1" in
        --user)        GITHUB_USER="$2"; shift 2 ;;
        --token)       GITHUB_TOKEN="$2"; shift 2 ;;
        --repo)        REPO="$2"; shift 2 ;;
        --readme)      README_CONTENT="$2"; shift 2 ;;
        --description) REPO_DESCRIPTION="$2"; shift 2 ;;
        --message)     COMMIT_MESSAGE="$2"; shift 2 ;;
        --date)        FAKE_DATE="$2"; shift 2 ;;
        --start-date)  START_DATE="$2"; shift 2 ;;
        --end-date)    END_DATE="$2"; shift 2 ;;
        --private)     PRIVATE=true; shift ;;
        -h|--help)     usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

# ---- Resolve the commit date ----
if [[ -n "$START_DATE" || -n "$END_DATE" ]]; then
    # A range was requested: both bounds are mandatory
    if [[ -z "$START_DATE" || -z "$END_DATE" ]]; then
        echo "❌ --start-date and --end-date must be given together." >&2
        exit 1
    fi
    START_EPOCH=$(date -d "$START_DATE" +%s)
    END_EPOCH=$(date -d "$END_DATE" +%s)
    if [[ "$START_EPOCH" -gt "$END_EPOCH" ]]; then
        echo "❌ --start-date must not be after --end-date." >&2
        exit 1
    fi
    RANDOM_EPOCH=$(shuf -i "$START_EPOCH-$END_EPOCH" -n 1)
    FAKE_DATE=$(date -u -d "@$RANDOM_EPOCH" +%Y-%m-%dT%H:%M:%S)
    echo "🎲 Random commit date: $FAKE_DATE"
fi

# ---- Credentials: use CLI args when provided, otherwise prompt ----
if [[ -z "${GITHUB_USER:-}" ]]; then
    read -rp "Enter your GitHub username: " GITHUB_USER
fi
if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    read -rsp "Enter your GitHub personal access token: " GITHUB_TOKEN
    echo
fi
GITHUB_USER="${GITHUB_USER//[[:space:]]/}"
GITHUB_TOKEN="${GITHUB_TOKEN//[[:space:]]/}"

# Helper: escape a string for embedding in JSON
json_escape() {
    sed 's/\\/\\\\/g; s/"/\\"/g' <<< "$1"
}

# Step 1: Create the repo on GitHub
echo "Creating GitHub repository..."

RESPONSE=$(curl -s -w $'\n%{http_code}' -X POST https://api.github.com/user/repos \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$(json_escape "$REPO")\",\"private\":$PRIVATE,\"description\":\"$(json_escape "$REPO_DESCRIPTION")\"}")

HTTP_CODE=$(tail -n1 <<< "$RESPONSE")
BODY=$(sed '$d' <<< "$RESPONSE")

if [[ "$HTTP_CODE" -eq 201 ]]; then
    echo "✅ Repository '$REPO' created!"
else
    MSG=$(grep -oP '"message"\s*:\s*"\K[^"]+' <<< "$BODY" | head -1)
    echo "❌ Failed to create repository: ${MSG:-unknown error}" >&2
    exit 1
fi

# Step 2: Clone the new repo
GIT_REPO_URL="https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${REPO}.git"
git clone "$GIT_REPO_URL"
cd "$REPO"

# Step 3: Create README.md
printf '%s\n' "$README_CONTENT" > README.md

# Step 4: Commit the README with the (possibly random) timestamp
git add README.md
git commit -m "$COMMIT_MESSAGE" --date="$FAKE_DATE"

# Step 5: Push the commit
git branch -M main
git push -u origin main

echo "Repo '$REPO' pushed!"
echo "View it here: https://github.com/$GITHUB_USER/$REPO"
