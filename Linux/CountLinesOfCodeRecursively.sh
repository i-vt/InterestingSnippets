#!/usr/bin/env bash
#
# count_loc.sh — recursively count lines of code, grouped by language.
#
# Usage:
#   ./count_loc.sh [directory ...]      (defaults to the current directory)
#
# How it works:
#   * Uses an ALLOWLIST of well-known source-code extensions, so media,
#     binaries, docs, and data files are excluded by construction.
#   * Prunes VCS metadata, dependency, build-output, and cache directories.
#   * Counts physical lines (wc -l), i.e. blank lines and comments included.
#
# Notes:
#   * .m is attributed to Objective-C (change it below if you use MATLAB).
#   * Data/markup formats (json, yaml, xml, md, ...) are intentionally
#     excluded; add lines to EXT_TABLE if you want them counted.
#   * Minified assets (*.min.js, *.min.css) are skipped.

set -eu

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "Usage: ${0##*/} [directory ...]"
    echo "Recursively counts lines of code, grouped by language."
    exit 0
fi

# ---------------------------------------------------------------------------
# Configuration — edit these tables/lists to taste
# ---------------------------------------------------------------------------

# extension:Language  (one per line; extensions match case-insensitively)
EXT_TABLE='# --- C, C++, Objective-C ---
c:C
h:C/C++
cpp:C++
cc:C++
cxx:C++
hpp:C++
hh:C++
hxx:C++
m:Objective-C
mm:Objective-C
# --- JVM ---
java:Java
kt:Kotlin
kts:Kotlin
scala:Scala
groovy:Groovy
gradle:Gradle
# --- .NET ---
cs:C#
fs:F#
fsi:F#
fsx:F#
vb:VB.NET
# --- Systems ---
go:Go
rs:Rust
swift:Swift
zig:Zig
nim:Nim
d:D
asm:Assembly
s:Assembly
# --- Scripting ---
py:Python
pyw:Python
rb:Ruby
php:PHP
pl:Perl
pm:Perl
lua:Lua
r:R
jl:Julia
tcl:Tcl
# --- Shells ---
sh:Shell
bash:Shell
zsh:Shell
ksh:Shell
fish:Shell
ps1:PowerShell
psm1:PowerShell
bat:Batch
cmd:Batch
# --- Web / frontend ---
js:JavaScript
mjs:JavaScript
cjs:JavaScript
jsx:JavaScript
ts:TypeScript
tsx:TypeScript
mts:TypeScript
cts:TypeScript
vue:Vue
svelte:Svelte
astro:Astro
html:HTML
htm:HTML
css:CSS
scss:Sass
sass:Sass
less:Less
# --- Functional ---
hs:Haskell
lhs:Haskell
ml:OCaml
mli:OCaml
clj:Clojure
cljs:Clojure
cljc:Clojure
ex:Elixir
exs:Elixir
erl:Erlang
hrl:Erlang
elm:Elm
lisp:Lisp
el:Emacs-Lisp
scm:Scheme
rkt:Racket
# --- Other ---
sql:SQL
dart:Dart
proto:Protobuf
graphql:GraphQL
gql:GraphQL
tf:Terraform
f:Fortran
f90:Fortran
f95:Fortran
f03:Fortran'

# Exact filenames that are code but have no extension
SPECIAL_TABLE='Makefile:Make
makefile:Make
GNUmakefile:Make
Dockerfile:Docker
Containerfile:Docker
Rakefile:Ruby
Gemfile:Ruby
Vagrantfile:Ruby
Jenkinsfile:Groovy'

# Directory names pruned wherever they appear in the tree
EXCLUDE_DIRS=(
    .git .hg .svn
    node_modules bower_components vendor
    __pycache__ .venv venv .tox .mypy_cache .pytest_cache .ruff_cache
    dist build out target obj coverage
    .gradle .idea .vscode .next .nuxt .svelte-kit .cache .terraform
    Pods DerivedData "cmake-build-*"
)

# ---------------------------------------------------------------------------
# Validate arguments
# ---------------------------------------------------------------------------

ROOTS=( "${@:-.}" )
for r in "${ROOTS[@]}"; do
    if [[ ! -d "$r" ]]; then
        echo "error: not a directory: $r" >&2
        exit 1
    fi
done

# ---------------------------------------------------------------------------
# Build the find expressions from the tables above
# ---------------------------------------------------------------------------

prune_expr=()
for d in "${EXCLUDE_DIRS[@]}"; do
    prune_expr+=( -name "$d" -o )
done
prune_expr=( "${prune_expr[@]:0:${#prune_expr[@]}-1}" )   # drop trailing -o

name_expr=()
while IFS=: read -r ext _; do
    case "$ext" in ''|'#'*) continue ;; esac
    name_expr+=( -iname "*.$ext" -o )
done <<<"$EXT_TABLE"
while IFS=: read -r base _; do
    case "$base" in ''|'#'*) continue ;; esac
    name_expr+=( -name "$base" -o )
done <<<"$SPECIAL_TABLE"
name_expr=( "${name_expr[@]:0:${#name_expr[@]}-1}" )      # drop trailing -o

# ---------------------------------------------------------------------------
# Count: find code files -> wc -l -> aggregate -> sort -> pretty-print
# ---------------------------------------------------------------------------

find "${ROOTS[@]}" \
    \( -type d \( "${prune_expr[@]}" \) -prune \) -o \
    \( -type f \( "${name_expr[@]}" \) \
       ! -iname '*.min.js' ! -iname '*.min.css' \
       -exec wc -l {} + \) \
| awk -v ext_table="$EXT_TABLE" -v special_table="$SPECIAL_TABLE" '
    BEGIN {
        n = split(ext_table, rows, "\n")
        for (i = 1; i <= n; i++) {
            if (rows[i] == "" || substr(rows[i], 1, 1) == "#") continue
            p = index(rows[i], ":")
            if (p == 0) continue
            ext_lang[tolower(substr(rows[i], 1, p - 1))] = substr(rows[i], p + 1)
        }
        n = split(special_table, rows, "\n")
        for (i = 1; i <= n; i++) {
            if (rows[i] == "" || substr(rows[i], 1, 1) == "#") continue
            p = index(rows[i], ":")
            if (p == 0) continue
            special_lang[tolower(substr(rows[i], 1, p - 1))] = substr(rows[i], p + 1)
        }
    }
    {
        # Parse "  <count> <filename>" lines emitted by wc -l.
        line = $0
        sub(/^[ \t]+/, "", line)
        p = index(line, " ")
        if (p == 0) next
        count = substr(line, 1, p - 1) + 0
        fname = substr(line, p + 1)
        if (fname == "" || fname == "total") next   # skip per-batch totals

        base = fname
        sub(/^.*\//, "", base)

        if (tolower(base) in special_lang) {
            lang = special_lang[tolower(base)]
        } else {
            if (match(base, /\.[^.]*$/) == 0) next
            ext = tolower(substr(base, RSTART + 1))
            lang = (ext in ext_lang) ? ext_lang[ext] : "*." ext
        }
        lines_by[lang] += count
        files_by[lang]++
    }
    END {
        for (l in lines_by)
            printf "%s\t%d\t%d\n", l, files_by[l], lines_by[l]
    }
' \
| sort -t"$(printf '\t')" -k3,3nr \
| awk -F"\t" '
    BEGIN {
        sep = sprintf("%42s", "")
        gsub(/ /, "-", sep)
    }
    NR == 1 {
        printf "%-16s %10s %14s\n", "Language", "Files", "Lines"
        print sep
    }
    {
        files += $2
        lines += $3
        printf "%-16s %10d %14d\n", $1, $2, $3
    }
    END {
        if (NR == 0) {
            print "No code files found."
        } else {
            print sep
            printf "%-16s %10d %14d\n", "Total", files, lines
        }
    }
'
