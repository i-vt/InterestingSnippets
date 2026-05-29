#!/usr/bin/env bash
#
# Recursively rename files and directories whose names contain a search term,
# replacing it with a replacement term (case-insensitive, substring match).
#
# Usage:
#   ./rename.sh [-n|--dry-run] [SEARCH] [REPLACE] [ROOT]
#
# Examples:
#   ./rename.sh                              # uses the defaults below, on .
#   ./rename.sh -n                           # preview only, no changes
#   ./rename.sh F1r5tw0rd SomeOtherWord ./   # explicit terms and root
#
set -u

# ---- Argument parsing ----------------------------------------------------
DRY_RUN=0
if [[ "${1:-}" == "-n" || "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=1
    shift
fi

SEARCH="${1:-F1r5tw0rd}"
REPLACE="${2:-SomeOtherWord}"
ROOT="${3:-.}"

renamed=0
skipped=0
errors=0

# ---- Helpers -------------------------------------------------------------

# Replace SEARCH with REPLACE in the given name, case-insensitively.
# SEARCH is treated as a literal via \Q..\E, so regex metacharacters in the
# search term are matched literally instead of being interpreted.
substitute() {
    printf '%s' "$1" | SEARCH="$SEARCH" REPLACE="$REPLACE" perl -0 -pe '
        BEGIN { $s = $ENV{SEARCH}; $r = $ENV{REPLACE} }
        s/\Q$s\E/$r/gi'
}

# process <files|dirs>
process() {
    local kind="$1" find_type find_extra=()
    if [[ "$kind" == "dirs" ]]; then
        find_type="d"
        find_extra=(-depth)          # bottom-up: rename children before parents
    else
        find_type="f"
    fi

    # Process substitution (not a pipe) so the counters update in THIS shell.
    # -print0 / read -d '' keep names with spaces, quotes, or newlines intact.
    local path dir base new_base target
    while IFS= read -r -d '' path; do
        dir=$(dirname -- "$path")
        base=$(basename -- "$path")
        new_base=$(substitute "$base")

        [[ "$base" == "$new_base" ]] && continue   # nothing to change

        target="$dir/$new_base"

        if [[ -e "$target" || -L "$target" ]]; then
            printf '  SKIP (target exists): %s -> %s\n' "$path" "$target" >&2
            skipped=$((skipped + 1))
            continue
        fi

        if [[ "$DRY_RUN" -eq 1 ]]; then
            printf '  would rename: %s -> %s\n' "$path" "$target"
            renamed=$((renamed + 1))
        elif mv -n -- "$path" "$target"; then
            printf '  renamed: %s -> %s\n' "$path" "$target"
            renamed=$((renamed + 1))
        else
            printf '  ERROR renaming: %s\n' "$path" >&2
            errors=$((errors + 1))
        fi
    done < <(find "$ROOT" ${find_extra[@]+"${find_extra[@]}"} \
                  -type "$find_type" -iname "*$SEARCH*" -print0)
}

# ---- Main ----------------------------------------------------------------
echo "Search:  $SEARCH"
echo "Replace: $REPLACE"
echo "Root:    $ROOT"
[[ "$DRY_RUN" -eq 1 ]] && echo "Mode:    DRY RUN (no changes will be made)"
echo

echo "Pass 1: files..."
process files

echo "Pass 2: directories (bottom-up)..."
process dirs

echo
echo "Summary: $renamed renamed, $skipped skipped, $errors error(s)."
[[ "$errors" -gt 0 ]] && exit 1
exit 0
