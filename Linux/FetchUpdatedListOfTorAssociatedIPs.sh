#!/usr/bin/env bash
# update-tor-lists.sh — refresh local copies of known Tor node IP lists.
set -uo pipefail

die() { echo "Error: $*" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || die "curl is required."

fetch() { # $1=url  $2=output file
    echo "Fetching $1"
    curl -fsS --max-time 90 "$1" \
        | tr -d '\r' \
        | grep -E '^[0-9a-fA-F.:]+$' \
        | sort -u > "$2" || die "download failed: $1"
    printf '  -> %s (%s addresses)\n' "$2" "$(wc -l < "$2")"
}

fetch 'https://www.dan.me.uk/torlist/'      tor-all-nodes.txt
fetch 'https://www.dan.me.uk/torlist/?exit' tor-exit-nodes.txt
