#!/usr/bin/env bash
# ip_info.sh — look up geolocation / ISP info for a list of IP addresses.
#
# Reads IPs (one per line) from FILE, queries the ip-api.com batch API
# (up to 100 IPs per request, no API key needed), and prints an aligned
# table: IP | COUNTRY | REGION | CITY | ISP | ORG | AS | REVERSE DNS
#
# Blank lines and anything after '#' are ignored, duplicate IPs are
# queried once. Private / reserved / invalid IPs show the API's message
# (e.g. "private range") in the country column. Reverse DNS is resolved
# locally (PTR lookup via getent/dig) since the batch API omits it.
#
# Requires: curl, jq, and getent or dig for reverse DNS (optional —
#           without them the REVERSE DNS column just shows '-').
# Note: ip-api.com's free tier is HTTP-only and rate-limited
#       (15 batch requests/minute). The script paces itself using the
#       X-Rl / X-Ttl response headers and retries on HTTP 429.

set -uo pipefail

API_URL="http://ip-api.com/batch"
FIELDS="status,message,query,country,regionName,city,isp,org,as"
BATCH_SIZE=100
MAX_RETRIES=3

# ── helpers ──────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: $(basename "$0") FILE

Fetch geolocation/ISP info for each IP address listed in FILE
(one per line; use '-' to read from stdin).

Output columns: IP | COUNTRY | REGION | CITY | ISP | ORG | AS | REVERSE DNS
Data source:    ip-api.com (free, no key, HTTP only)

  -h   Show this help
EOF
    exit "${1:-0}"
}

die()  { echo "Error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "required tool '$1' is not installed."; }

# ── argument parsing ──────────────────────────────────────────────────────────

[[ "${1:-}" == "-h" ]] && usage
FILE="${1:-}"
[[ -n "$FILE" ]] || usage 1
[[ "$FILE" == "-" ]] && FILE=/dev/stdin
[[ -r "$FILE" ]] || die "'$FILE' is not readable."

need curl
need jq

# ── load IPs: strip comments/whitespace, drop blanks and duplicates ──────────

mapfile -t IPS < <(
    sed -e 's/#.*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$FILE" \
    | awk 'NF && !seen[$0]++'
)

TOTAL=${#IPS[@]}
(( TOTAL > 0 )) || { echo "No IPs found."; exit 0; }

ROWS=$(mktemp); HDRS=$(mktemp); BODY=$(mktemp); RDNS=$(mktemp)
trap 'rm -f "$ROWS" "$HDRS" "$BODY" "$RDNS"' EXIT

# ── API access ────────────────────────────────────────────────────────────────

hdr_value() {  # $1=header name → value (case-insensitive, CRLF-safe)
    awk -v name="$1" 'BEGIN{IGNORECASE=1} $0 ~ "^"name":" {gsub(/\r/,""); print $2}' "$HDRS"
}

# Respect the rate limit announced by the API: X-Rl = requests left in
# the current window, X-Ttl = seconds until the window resets.
pace() {
    local rl ttl
    rl=$(hdr_value "X-Rl");  ttl=$(hdr_value "X-Ttl")
    if [[ -n "$rl" && "$rl" -le 1 && -n "$ttl" ]]; then
        echo "  …rate limit window nearly used, waiting ${ttl}s…" >&2
        sleep "$ttl"
    fi
}

fetch_batch() {  # $1=JSON array payload → appends TSV rows to $ROWS
    local payload="$1" attempt=1 code ttl
    while (( attempt <= MAX_RETRIES )); do
        code=$(curl -sS --max-time 30 \
                    -D "$HDRS" -o "$BODY" -w '%{http_code}' \
                    -H 'Content-Type: application/json' \
                    -X POST "${API_URL}?fields=${FIELDS}" \
                    --data "$payload" 2>/dev/null) || code=000
        if [[ "$code" == 200 ]]; then
            jq -r '
                .[] | [
                    .query,
                    (if .status=="success" then .country    else (.message // "lookup failed") end),
                    (if .status=="success" then .regionName else "-" end),
                    (if .status=="success" then .city       else "-" end),
                    (if .status=="success" then .isp        else "-" end),
                    (if .status=="success" then .org        else "-" end),
                    (if .status=="success" then ."as"       else "-" end)
                ] | map(. // "-" | tostring | gsub("[\t\r\n]"; " "))
                  | @tsv
            ' "$BODY" >> "$ROWS" || die "failed to parse API response."
            pace
            return 0
        fi
        if [[ "$code" == 429 ]]; then
            ttl=$(hdr_value "X-Ttl")
            echo "  …rate limited (HTTP 429), waiting ${ttl:-60}s…" >&2
            sleep "${ttl:-60}"
        else
            echo "  …API returned HTTP $code, retrying ($attempt/$MAX_RETRIES)…" >&2
            sleep 2
        fi
        ((attempt++))
    done
    die "API request failed after $MAX_RETRIES attempts (last HTTP code: $code)."
}

# ── query in chunks of $BATCH_SIZE ────────────────────────────────────────────

for (( start=0; start<TOTAL; start+=BATCH_SIZE )); do
    chunk=("${IPS[@]:start:BATCH_SIZE}")
    end=$(( start + ${#chunk[@]} ))
    echo "Querying IPs $((start+1))–$end of $TOTAL…" >&2
    payload=$(printf '%s\n' "${chunk[@]}" | jq -R -c -s 'split("\n")[:-1]')
    fetch_batch "$payload"
done

# ── reverse DNS: local PTR lookups (no API needed) ───────────────────────────

echo "Resolving reverse DNS locally…" >&2
for ip in "${IPS[@]}"; do
    name=""
    if command -v getent >/dev/null 2>&1; then
        name=$(getent hosts "$ip" | awk '{print $2; exit}')
    fi
    if [[ -z "$name" ]] && command -v dig >/dev/null 2>&1; then
        name=$(dig +short +time=3 +tries=1 -x "$ip" 2>/dev/null | head -1)
        name="${name%.}"   # dig prints FQDNs with a trailing dot
    fi
    printf '%s\t%s\n' "$ip" "${name:--}" >> "$RDNS"
done

# ── render: autosized columns (longest cell per column sets the width) ───────

{
    printf 'IP\tCOUNTRY\tREGION\tCITY\tISP\tORG\tAS\n'
    cat "$ROWS"
} | awk -F '\t' '
    NR == FNR { rdns[$1] = $2; next }          # first file: IP → hostname
    {   $(NF + 1) = (FNR == 1 ? "REVERSE DNS" : ($1 in rdns ? rdns[$1] : "-"))
        for (i = 1; i <= NF; i++) {
            cell[FNR, i] = $i
            if (length($i) > w[i]) w[i] = length($i)
        }
        nf = NF; n = FNR
    }
    END {
        for (r = 1; r <= n; r++) {
            for (i = 1; i <= nf; i++)
                printf (i < nf ? "%-" w[i] "s | " : "%s\n"), cell[r, i]
            if (r == 1) {   # rule under the header
                for (i = 1; i <= nf; i++) {
                    line = sprintf("%" w[i] "s", ""); gsub(/ /, "-", line)
                    printf (i < nf ? line "-+-" : line "\n"), ""
                }
            }
        }
    }' "$RDNS" -
