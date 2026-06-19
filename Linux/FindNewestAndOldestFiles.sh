#!/usr/bin/env bash
# find_extremes.sh — report the newest and oldest entry (file or dir)
#                    in any directory, ranked by modification time.
#
# Requires: GNU find (standard on Linux).
#           macOS users: brew install findutils and use gfind, or install
#           coreutils so 'find' supports -printf.

set -uo pipefail

# ── helpers ──────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: $(basename "$0") [-r] [DIRECTORY]

Find the newest and oldest entry by modification time.

  -r   Recurse into subdirectories (default: immediate children only)
  -h   Show this help

DIRECTORY defaults to the current working directory if omitted.
EOF
    exit 0
}

die() { echo "Error: $*" >&2; exit 1; }

# Format an epoch timestamp → human-readable date.
# Tries GNU 'date -d' first, falls back to BSD 'date -r' (macOS).
fmt_date() {
    local ts="$1"
    date -d "@${ts}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null \
        || date -r  "${ts}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null \
        || echo "(epoch ${ts})"
}

entry_type() { [[ -d "$1" ]] && echo "dir" || echo "file"; }

# ── argument parsing ──────────────────────────────────────────────────────────

RECURSIVE=false

while getopts ":rh" opt; do
    case "$opt" in
        r) RECURSIVE=true ;;
        h) usage ;;
        *) die "Unknown option: -$OPTARG  (run with -h for help)" ;;
    esac
done
shift $((OPTIND - 1))

TARGET_DIR="${1:-.}"
[[ -d "$TARGET_DIR" ]] || die "'$TARGET_DIR' is not a valid directory."

# ── collect entries ───────────────────────────────────────────────────────────

FIND_ARGS=("$TARGET_DIR" "-mindepth" "1")
[[ "$RECURSIVE" == false ]] && FIND_ARGS+=("-maxdepth" "1")

# -printf "%T@ %p\n"  →  "<float epoch>  <path>"
# sort -n  →  ascending by time (oldest first, newest last)
mapfile -t SORTED < <(
    find "${FIND_ARGS[@]}" -printf "%T@ %p\n" 2>/dev/null | sort -n
)

COUNT="${#SORTED[@]}"
(( COUNT > 0 )) || { echo "No entries found in '$TARGET_DIR'."; exit 0; }

# ── extract oldest / newest ───────────────────────────────────────────────────

OLDEST_LINE="${SORTED[0]}"
NEWEST_LINE="${SORTED[$((COUNT - 1))]}"

# Strip leading "timestamp " to get just the path
OLDEST_PATH="${OLDEST_LINE#* }"
NEWEST_PATH="${NEWEST_LINE#* }"

# Integer seconds only (strip sub-second fraction and the path)
OLDEST_TS="${OLDEST_LINE%%.*}"
NEWEST_TS="${NEWEST_LINE%%.*}"

# ── output ────────────────────────────────────────────────────────────────────

SCOPE="immediate children only"
[[ "$RECURSIVE" == true ]] && SCOPE="all entries (recursive)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "  Directory : %s\n"  "$TARGET_DIR"
printf "  Scope     : %s\n"  "$SCOPE"
printf "  Entries   : %d scanned\n" "$COUNT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo
printf "  %-8s %s\n"      "Oldest:"  "$OLDEST_PATH"
printf "  %-8s %s  [%s]\n" ""        "$(fmt_date "$OLDEST_TS")"  "$(entry_type "$OLDEST_PATH")"

echo
printf "  %-8s %s\n"      "Newest:"  "$NEWEST_PATH"
printf "  %-8s %s  [%s]\n" ""        "$(fmt_date "$NEWEST_TS")"  "$(entry_type "$NEWEST_PATH")"
echo
