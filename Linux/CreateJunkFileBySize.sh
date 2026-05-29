#!/usr/bin/env bash
#
# makefile.sh - Create a file of a given size, filled with empty space or random data.
#
# Usage:
#   ./makefile.sh [--real | --random] <size> [output_file]
#
# Flags, size, and output file may appear in any order.
# Size accepts a number followed by an optional unit (B, KB, MB, GB).
# No unit means bytes. Units are base-1024 (KB = 1024 bytes, etc.).
# If no output file is given, one is auto-named (e.g. file_5MB_random.bin).
#
# Fill modes:
#   (default)   Sparse file of null bytes. Instant, ~0 disk used until written.
#   --real      Null bytes physically written to disk (allocates every byte).
#   --random    Random bytes from /dev/urandom (always physically written).
#
# Examples:
#   ./makefile.sh 5MB --random            # any order works
#   ./makefile.sh --random 5MB rand.bin
#   ./makefile.sh --real 100KB data.bin

set -euo pipefail

usage() {
    echo "Usage: $0 [--real | --random] <size> [output_file]" >&2
    echo "  size: number + optional unit B|KB|MB|GB (default B), e.g. 5MB" >&2
    echo "  flags and size may appear in any order" >&2
    exit 1
}

MODE="sparse"
SIZE_ARG=""
OUTFILE=""

# Scan every argument; classify by shape rather than position.
for arg in "$@"; do
    case "$arg" in
        --real)   MODE="real"   ;;
        --random) MODE="random" ;;
        --help|-h) usage ;;
        --*)      echo "Error: unknown option '$arg'" >&2; usage ;;
        *)
            if [[ "$arg" =~ ^[0-9]+([BbKkMmGg][Bb]?)?$ ]]; then
                [[ -z "$SIZE_ARG" ]] || { echo "Error: size given twice ('$SIZE_ARG', '$arg')" >&2; usage; }
                SIZE_ARG="$arg"
            else
                [[ -z "$OUTFILE" ]] || { echo "Error: too many filenames ('$OUTFILE', '$arg')" >&2; usage; }
                OUTFILE="$arg"
            fi
            ;;
    esac
done

[[ -n "$SIZE_ARG" ]] || { echo "Error: no size given" >&2; usage; }

# Parse the size into bytes.
[[ "$SIZE_ARG" =~ ^([0-9]+)([BbKkMmGg][Bb]?)?$ ]]
NUM="${BASH_REMATCH[1]}"
UNIT="${BASH_REMATCH[2]^^}"

case "$UNIT" in
    ""|"B")    BYTES=$(( NUM ))                       ;;
    "K"|"KB")  BYTES=$(( NUM * 1024 ))                ;;
    "M"|"MB")  BYTES=$(( NUM * 1024 * 1024 ))         ;;
    "G"|"GB")  BYTES=$(( NUM * 1024 * 1024 * 1024 ))  ;;
esac

# Default output name if none supplied.
# Generate a UUID, trying the common sources in turn.
gen_uuid() {
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen
    elif [[ -r /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid
    else
        # Last-resort fallback: build a UUID-shaped string from $RANDOM.
        printf '%04x%04x-%04x-%04x-%04x-%04x%04x%04x\n' \
            $RANDOM $RANDOM $RANDOM $(( (RANDOM & 0x0fff) | 0x4000 )) \
            $(( (RANDOM & 0x3fff) | 0x8000 )) $RANDOM $RANDOM $RANDOM
    fi
}

UUID="$(gen_uuid)"

if [[ -z "$OUTFILE" ]]; then
    OUTFILE="file_${SIZE_ARG}_${MODE}_${UUID}.bin"
else
    # Insert the UUID at the end of the name, before the extension if present.
    if [[ "$OUTFILE" == *.* ]]; then
        OUTFILE="${OUTFILE%.*}_${UUID}.${OUTFILE##*.}"
    else
        OUTFILE="${OUTFILE}_${UUID}"
    fi
fi

# Write BYTES bytes from a given source into $OUTFILE.
write_bytes() {
    local src="$1"
    dd if="$src" of="$OUTFILE" bs=1M \
       count=$(( BYTES / 1048576 )) status=none 2>/dev/null || true
    local rem=$(( BYTES % 1048576 ))
    if [[ $rem -gt 0 ]]; then
        dd if="$src" bs=1 count="$rem" status=none >> "$OUTFILE"
    fi
}

case "$MODE" in
    sparse)
        truncate -s "$BYTES" "$OUTFILE"
        ;;
    real)
        if command -v fallocate >/dev/null 2>&1; then
            fallocate -l "$BYTES" "$OUTFILE"
        else
            : > "$OUTFILE"
            write_bytes /dev/zero
        fi
        ;;
    random)
        : > "$OUTFILE"
        write_bytes /dev/urandom
        ;;
esac

echo "Created '$OUTFILE' ($BYTES bytes, $MODE)"
