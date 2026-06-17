#!/usr/bin/env bash
#
# replace.sh — recursively replace a string in (1) file contents,
#              (2) filenames, and (3) folder names. The search and
#              replacement strings are taken from the command line.
#
# For every in-content occurrence that is (or would be) replaced, the
# script prints CONTEXT characters of text before and after the match.
#
# Usage:
#   ./replace.sh [-n] SEARCH REPLACE [TARGET_DIR]
#     -n          dry run: show what WOULD change, change nothing
#     SEARCH      literal string to find (required)
#     REPLACE     literal string to substitute (required)
#     TARGET_DIR  directory to process (default: current directory)
#
# Matching is LITERAL, not regex/glob: SEARCH and REPLACE may contain
# spaces, dots, slashes, asterisks, brackets, etc.
#
set -euo pipefail

CONTEXT=30   # characters of context shown on each side of a match

usage() {
    cat >&2 <<USAGE
Usage: $0 [-n] SEARCH REPLACE [TARGET_DIR]
  -n          dry run (show changes, modify nothing)
  SEARCH      literal string to find (required)
  REPLACE     literal string to substitute (required)
  TARGET_DIR  directory to process (default: current directory)
USAGE
    exit 2
}

DRY_RUN=0
case "${1:-}" in
    -n)        DRY_RUN=1; shift ;;
    -h|--help) usage ;;
esac

[[ $# -ge 2 ]] || usage
SEARCH="$1"
REPLACE="$2"
TARGET="${3:-.}"

[[ -n "$SEARCH" ]] || { echo "Error: SEARCH must not be empty." >&2; exit 2; }
[[ -d "$TARGET" ]] || { echo "Error: '$TARGET' is not a directory." >&2; exit 1; }
command -v perl >/dev/null 2>&1 || { echo "Error: perl is required but not found." >&2; exit 1; }

SELF="$(readlink -f "$0")"

echo "Search : $SEARCH"
echo "Replace: $REPLACE"
echo "Target : $TARGET"
[[ $DRY_RUN -eq 1 ]] && echo "Mode   : DRY RUN (no changes will be made)"
echo

# ---------------------------------------------------------------------------
# 1. File contents: show context around each match, then replace it.
#    Binary files and the .git directory are skipped.
# ---------------------------------------------------------------------------
echo "== File contents =="
content_any=0
while IFS= read -r -d '' file; do
    [[ "$(readlink -f "$file")" == "$SELF" ]] && continue
    content_any=1
    echo "$file"

    # Print CONTEXT chars before + [match] + CONTEXT chars after, per occurrence.
    SEARCH="$SEARCH" CONTEXT="$CONTEXT" perl -0777 -ne '
        my $s = $ENV{SEARCH};
        my $L = $ENV{CONTEXT};
        while (/\Q$s\E/g) {
            my ($b, $e) = ($-[0], $+[0]);
            my $bs = $b - $L; $bs = 0 if $bs < 0;
            my $before = substr($_, $bs, $b - $bs);
            my $match  = substr($_, $b, $e - $b);
            my $after  = substr($_, $e, $L);
            my $lead = ($bs > 0)          ? "..." : "";
            my $tail = ($e + $L < length) ? "..." : "";
            for ($before, $match, $after) { s/\r/\\r/g; s/\n/\\n/g; s/\t/\\t/g; }
            printf "    %s%s[%s]%s%s\n", $lead, $before, $match, $after, $tail;
        }
    ' "$file"

    if [[ $DRY_RUN -eq 0 ]]; then
        SEARCH="$SEARCH" REPLACE="$REPLACE" perl -0777 -i -pe '
            BEGIN { $s = $ENV{SEARCH}; $r = $ENV{REPLACE}; }
            s/\Q$s\E/$r/g;
        ' "$file"
    fi
done < <(grep -rIlZF --exclude-dir=.git -e "$SEARCH" "$TARGET" 2>/dev/null || true)
[[ $content_any -eq 0 ]] && echo "(no files contain the search string)"

# ---------------------------------------------------------------------------
# 2. Rename files and folders (deepest first; literal substring match).
# ---------------------------------------------------------------------------
echo
echo "== Renaming files and folders =="
rename_any=0
while IFS= read -r -d '' path; do
    [[ "$(readlink -f "$path")" == "$SELF" ]] && continue
    base="$(basename "$path")"
    [[ "$base" == *"$SEARCH"* ]] || continue        # literal "contains?" test
    dir="$(dirname "$path")"
    newbase="${base//"$SEARCH"/"$REPLACE"}"          # literal substitution
    [[ "$base" == "$newbase" ]] && continue
    newpath="$dir/$newbase"
    if [[ -e "$newpath" ]]; then
        echo "skipped (target exists): $path -> $newpath" >&2
        continue
    fi
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "would rename: $path -> $newpath"
    else
        mv -- "$path" "$newpath"
        echo "renamed:      $path -> $newpath"
    fi
    rename_any=1
done < <(find "$TARGET" -depth -not -path '*/.git/*' -print0)
[[ $rename_any -eq 0 ]] && echo "(nothing to rename)"

echo
echo "Done."
