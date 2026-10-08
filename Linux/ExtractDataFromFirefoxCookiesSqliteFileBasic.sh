#!/bin/bash

# =====================================================
# Firefox cookies.sqlite extractor (Blue Team Edition)
# Output:
#   - CSV (default)
#   - JSON (single file if -d used)
#   - JSON per-website files if no -d specified
# Requires: sqlite3, jq (for JSON mode)
# =====================================================

usage() {
    echo "Usage: $0 -f /path/to/cookies.sqlite [-d domain_filter] [-o csv|json]"
    exit 1
}

# Defaults
OUTPUT_FORMAT="csv"
DOMAIN_FILTER=""

# Parse arguments
while getopts "f:d:o:" opt; do
    case $opt in
        f) COOKIE_DB="$OPTARG" ;;
        d) DOMAIN_FILTER="$OPTARG" ;;
        o) OUTPUT_FORMAT="$OPTARG" ;;
        *) usage ;;
    esac
done

[ -z "$COOKIE_DB" ] && usage

if [ ! -f "$COOKIE_DB" ]; then
    echo "[!] File not found: $COOKIE_DB"
    exit 1
fi

# Create forensic working copy
WORK_DB="cookies_working_copy.sqlite"
cp "$COOKIE_DB" "$WORK_DB"
echo "[+] Working copy created"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Base SQL query
SQL_BASE="
SELECT
    host,
    name,
    value,
    datetime(creationTime/1000000,'unixepoch') AS created,
    datetime(lastAccessed/1000000,'unixepoch') AS last_accessed,
    datetime(expiry,'unixepoch') AS expiry,
    isSecure,
    isHttpOnly
FROM moz_cookies
"

# Apply filter if provided
if [ -n "$DOMAIN_FILTER" ]; then
    SQL_BASE="$SQL_BASE WHERE host LIKE '%$DOMAIN_FILTER%'"
fi

SQL_BASE="$SQL_BASE ORDER BY host, lastAccessed DESC;"

# =============================
# CSV OUTPUT (Default)
# =============================
if [ "$OUTPUT_FORMAT" = "csv" ]; then

    OUTPUT="cookies_${TIMESTAMP}.csv"
    sqlite3 -header -csv "$WORK_DB" "$SQL_BASE" > "$OUTPUT"

    echo "[+] CSV output saved to: $OUTPUT"

# =============================
# JSON OUTPUT
# =============================
elif [ "$OUTPUT_FORMAT" = "json" ]; then

    if ! command -v jq &> /dev/null; then
        echo "[!] jq is required for JSON mode."
        rm -f "$WORK_DB"
        exit 1
    fi

    sqlite3 -json "$WORK_DB" "$SQL_BASE" > raw.json

    # -------------------------------------------------
    # CASE 1: Domain filter specified → Single JSON
    # -------------------------------------------------
    if [ -n "$DOMAIN_FILTER" ]; then

        OUTPUT="cookies_${DOMAIN_FILTER}_${TIMESTAMP}.json"

        jq '
        group_by(.host) |
        map({
            website: .[0].host,
            cookies: map({
                name,
                value,
                created,
                last_accessed,
                expiry,
                isSecure,
                isHttpOnly
            })
        })
        ' raw.json > "$OUTPUT"

        echo "[+] JSON output saved to: $OUTPUT"

    # -------------------------------------------------
    # CASE 2: No filter → Separate file per website
    # -------------------------------------------------
    else

        OUTPUT_DIR="cookies_json_${TIMESTAMP}"
        mkdir -p "$OUTPUT_DIR"

        echo "[+] Creating individual JSON files per website..."

        # Extract unique hosts
        jq -r '.[].host' raw.json | sort -u | while read -r HOST; do

            # Sanitize filename
            SAFE_HOST=$(echo "$HOST" | sed 's/[^a-zA-Z0-9._-]/_/g')

            jq --arg host "$HOST" '
                map(select(.host == $host)) |
                {
                    website: $host,
                    cookies: map({
                        name,
                        value,
                        created,
                        last_accessed,
                        expiry,
                        isSecure,
                        isHttpOnly
                    })
                }
            ' raw.json > "${OUTPUT_DIR}/${SAFE_HOST}.json"

        done

        echo "[+] JSON files saved in directory: $OUTPUT_DIR"
    fi

    rm -f raw.json

else
    echo "[!] Invalid output format. Use csv or json."
fi

# Cleanup
rm -f "$WORK_DB"
