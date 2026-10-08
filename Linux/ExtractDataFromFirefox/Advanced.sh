#!/usr/bin/env bash
#
# GetData.sh — extract cookies, history, bookmarks, downloads, form history
#              and logins from a (possibly offline) Firefox profile.
#
# Usage:
#   ./GetData.sh                       # auto-detect default profile under ~/.mozilla/firefox
#   ./GetData.sh -p /path/to/profile   # specific profile dir (or parent tree to search)
#   ./GetData.sh -p /path -o outdir    # custom output dir
#   ./GetData.sh --master-password PW  # if the profile has a master password
#
# Outputs CSVs into the output dir (default: ./firefox_export).

set -euo pipefail

# ---------------------------------------------------------------- defaults
PROFILE_ARG=""
OUTDIR="firefox_export"
MASTER_PW=""
FFDECRYPT="${FFDECRYPT:-}"   # allow env override: path to firefox_decrypt.py or binary

log()  { printf '[*] %s\n' "$*"; }
ok()   { printf '[+] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }
die()  { printf '[-] %s\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,12p' "$0" | sed 's/^#\s\?//'
    exit "${1:-0}"
}

# ---------------------------------------------------------------- args
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--profile)         PROFILE_ARG="${2:?missing value for $1}"; shift 2 ;;
        -o|--outdir)          OUTDIR="${2:?missing value for $1}"; shift 2 ;;
        --master-password)    MASTER_PW="${2:?missing value for $1}"; shift 2 ;;
        -h|--help)            usage 0 ;;
        *)                    die "unknown argument: $1 (see --help)" ;;
    esac
done

# ---------------------------------------------------------------- dependency checks
log "Checking dependencies..."

command -v python3 >/dev/null || die "python3 not found — sudo apt install python3"

# python3 sqlite3 module
python3 -c "import sqlite3" 2>/dev/null || die "python3 sqlite3 module missing — sudo apt install python3"

# libnss3 (needed to decrypt logins)
if ! ldconfig -p 2>/dev/null | grep -q 'libnss3\.so'; then
    warn "libnss3 not found."
    if command -v apt >/dev/null; then
        log "Installing libnss3..."
        sudo apt install -y libnss3 || die "libnss3 install failed"
    else
        die "libnss3 missing and no apt available"
    fi
fi
ok "libnss3 present"

# firefox_decrypt: PATH -> env override -> common clone locations -> download repo
REPO_URL="https://github.com/unode/firefox_decrypt"
CLONE_DIR="$HOME/Downloads/firefox_decrypt-main"

find_firefox_decrypt() {
    [[ -n "$FFDECRYPT" && -e "$FFDECRYPT" ]] && return 0
    if command -v firefox_decrypt >/dev/null; then
        FFDECRYPT="$(command -v firefox_decrypt)"; return 0
    fi
    for c in "$CLONE_DIR/firefox_decrypt.py" \
             "$HOME/Downloads/firefox_decrypt/firefox_decrypt.py" \
             "$HOME/firefox_decrypt/firefox_decrypt.py"; do
        if [[ -f "$c" ]]; then FFDECRYPT="$c"; return 0; fi
    done
    return 1
}

download_firefox_decrypt() {
    log "Downloading firefox_decrypt from $REPO_URL ..."
    mkdir -p "$(dirname "$CLONE_DIR")"

    if command -v git >/dev/null; then
        rm -rf "$CLONE_DIR"
        git clone --depth 1 "$REPO_URL" "$CLONE_DIR" || return 1
    else
        # no git: fetch the tarball via curl or wget
        local tarball="$CLONE_DIR.tar.gz"
        if command -v curl >/dev/null; then
            curl -fsSL "$REPO_URL/archive/refs/heads/main.tar.gz" -o "$tarball" || return 1
        elif command -v wget >/dev/null; then
            wget -q "$REPO_URL/archive/refs/heads/main.tar.gz" -O "$tarball" || return 1
        else
            warn "neither git, curl nor wget available"
            return 1
        fi
        rm -rf "$CLONE_DIR"
        tar xzf "$tarball" -C "$(dirname "$CLONE_DIR")" || return 1
        rm -f "$tarball"
    fi

    [[ -f "$CLONE_DIR/firefox_decrypt.py" ]] || return 1
    FFDECRYPT="$CLONE_DIR/firefox_decrypt.py"
    return 0
}

if ! find_firefox_decrypt; then
    warn "firefox_decrypt not found — fetching it now."
    download_firefox_decrypt \
        || die "download failed — clone $REPO_URL manually and set FFDECRYPT=/path/to/firefox_decrypt.py"
fi
ok "firefox_decrypt: $FFDECRYPT"

# ---------------------------------------------------------------- locate profile
if [[ -n "$PROFILE_ARG" ]]; then
    SEARCH_ROOT="$PROFILE_ARG"
else
    SEARCH_ROOT="$HOME/.mozilla/firefox"
fi
[[ -d "$SEARCH_ROOT" ]] || die "not a directory: $SEARCH_ROOT"

if [[ -f "$SEARCH_ROOT/places.sqlite" ]]; then
    PROFILE="$SEARCH_ROOT"
else
    log "Searching for profiles under $SEARCH_ROOT ..."
    mapfile -t CANDIDATES < <(find "$SEARCH_ROOT" -maxdepth 3 -name places.sqlite -printf '%h\n' 2>/dev/null)
    [[ ${#CANDIDATES[@]} -gt 0 ]] || die "no Firefox profile (places.sqlite) found under $SEARCH_ROOT"

    PROFILE=""
    for c in "${CANDIDATES[@]}"; do
        if [[ "$c" == *default-release* ]]; then PROFILE="$c"; break; fi
    done
    # fall back: default-esr, then first found
    if [[ -z "$PROFILE" ]]; then
        for c in "${CANDIDATES[@]}"; do
            if [[ "$c" == *default-esr* ]]; then PROFILE="$c"; break; fi
        done
    fi
    [[ -n "$PROFILE" ]] || PROFILE="${CANDIDATES[0]}"

    if [[ ${#CANDIDATES[@]} -gt 1 ]]; then
        warn "Multiple profiles found; using: $PROFILE"
        printf '    %s\n' "${CANDIDATES[@]}" >&2
        warn "Override with: $0 -p <dir>"
    fi
fi
ok "Profile: $PROFILE"

mkdir -p "$OUTDIR"

# ---------------------------------------------------------------- sqlite extraction
log "Extracting cookies / history / bookmarks / downloads / form history..."

FF_PROFILE="$PROFILE" FF_OUTDIR="$OUTDIR" python3 - <<'PYEOF'
import csv, json, os, shutil, sqlite3, tempfile
from datetime import datetime, timezone

profile = os.environ["FF_PROFILE"]
outdir  = os.environ["FF_OUTDIR"]

def copy_db(name, tmpdir):
    src = os.path.join(profile, name)
    if not os.path.exists(src):
        return None
    dst = os.path.join(tmpdir, name)
    shutil.copy2(src, dst)
    for ext in ("-wal", "-shm"):
        if os.path.exists(src + ext):
            shutil.copy2(src + ext, dst + ext)
    return dst

def query(db, sql):
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    try:
        cur = con.execute(sql)
        return [d[0] for d in cur.description], cur.fetchall()
    finally:
        con.close()

def ff_time(us):
    if not us:
        return ""
    try:
        return datetime.fromtimestamp(us / 1_000_000, tz=timezone.utc).isoformat()
    except (OSError, OverflowError):
        return str(us)

def write_csv(path, cols, rows):
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f); w.writerow(cols); w.writerows(rows)
    print(f"[+] {len(rows):>6} rows -> {path}")

with tempfile.TemporaryDirectory() as tmp:
    db = copy_db("cookies.sqlite", tmp)
    if db:
        cols, rows = query(db, """
            SELECT host, name, value, path, isSecure, isHttpOnly,
                   expiry, lastAccessed, creationTime, sameSite, originAttributes
            FROM moz_cookies ORDER BY host""")
        rows = [(h, n, v, p, bool(s), bool(ho),
                 ff_time(exp * 1_000_000) if exp else "",
                 ff_time(la), ff_time(ct), ss, oa)
                for h, n, v, p, s, ho, exp, la, ct, ss, oa in rows]
        write_csv(os.path.join(outdir, "cookies.csv"), cols, rows)
    else:
        print("[-] cookies.sqlite not found")

    db = copy_db("places.sqlite", tmp)
    if db:
        cols, rows = query(db, """
            SELECT url, title, visit_count, last_visit_date
            FROM moz_places WHERE hidden = 0 ORDER BY last_visit_date DESC""")
        write_csv(os.path.join(outdir, "history.csv"), cols,
                  [(u, t or "", vc, ff_time(lvd)) for u, t, vc, lvd in rows])

        cols, rows = query(db, """
            SELECT b.title, p.url, b.dateAdded
            FROM moz_bookmarks b JOIN moz_places p ON b.fk = p.id
            WHERE b.type = 1 ORDER BY b.dateAdded""")
        write_csv(os.path.join(outdir, "bookmarks.csv"), cols,
                  [(t or "", u, ff_time(d)) for t, u, d in rows])

        try:
            cols, rows = query(db, """
                SELECT p.url, a.content AS file_uri, p.last_visit_date
                FROM moz_annos a
                JOIN moz_places p ON a.place_id = p.id
                JOIN moz_anno_attributes n ON a.anno_attribute_id = n.id
                WHERE n.name = 'downloads/destinationFileURI'""")
            write_csv(os.path.join(outdir, "downloads.csv"), cols, rows)
        except sqlite3.Error:
            pass
    else:
        print("[-] places.sqlite not found")

    db = copy_db("formhistory.sqlite", tmp)
    if db:
        cols, rows = query(db, """
            SELECT fieldname, value, timesUsed, firstUsed, lastUsed
            FROM moz_formhistory ORDER BY lastUsed DESC""")
        write_csv(os.path.join(outdir, "formhistory.csv"), cols,
                  [(f, v, t, ff_time(fu), ff_time(lu)) for f, v, t, fu, lu in rows])
PYEOF

# ---------------------------------------------------------------- logins
LOGINS_OUT="$OUTDIR/logins_decrypted.csv"

if [[ ! -f "$PROFILE/logins.json" ]]; then
    warn "logins.json not found in profile — skipping password extraction"
elif [[ ! -f "$PROFILE/key4.db" ]]; then
    warn "key4.db missing — passwords cannot be decrypted"
else
    log "Decrypting logins..."

    # build invocation: script path needs python3, binary runs directly
    if [[ "$FFDECRYPT" == *.py ]]; then
        FD_CMD=(python3 "$FFDECRYPT")
    else
        FD_CMD=("$FFDECRYPT")
    fi

    FD_ARGS=(-f csv -n -e utf-8 --non-fatal-decryption)
    [[ -n "$MASTER_PW" ]] && FD_ARGS+=(-m "printf %s '$MASTER_PW'")

    set +e
    "${FD_CMD[@]}" "${FD_ARGS[@]}" "$PROFILE" > "$LOGINS_OUT" 2>"$OUTDIR/.firefox_decrypt.err"
    rc=$?
    set -e

    if [[ $rc -eq 0 && -s "$LOGINS_OUT" ]]; then
        rows=$(( $(wc -l < "$LOGINS_OUT") - 1 ))
        ok "$rows rows -> $LOGINS_OUT"
    else
        warn "firefox_decrypt failed (rc=$rc):"
        sed 's/^/    /' "$OUTDIR/.firefox_decrypt.err" >&2 || true
        rm -f "$LOGINS_OUT"
        warn "If a master password was set, re-run with: --master-password 'pw'"
    fi
fi

# ---------------------------------------------------------------- JSON extras
for name in addons.json extension-preferences.json containers.json \
            logins-backup.json sessionstore.jsonlz4 search.json.mozlz4; do
    if [[ -f "$PROFILE/$name" ]]; then
        cp -p "$PROFILE/$name" "$OUTDIR/$name"
        ok "copied $name"
    fi
done

# ---------------------------------------------------------------- done
log "Done. Output in $OUTDIR/"
ls -la "$OUTDIR"
