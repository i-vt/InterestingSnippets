#!/bin/bash
# =============================================================================
# HTB Academy CTF: Rename files to legitimate-looking names
# Usage: ./cloak_files.sh <target_directory> [--dry-run]
# =============================================================================
set -euo pipefail

# Legitimate-looking extensions (common in system32 / user profiles)
EXTENSIONS=(
  "dat" "dll" "sys" "log" "tmp" "bak" "cfg" "ini" "db" "bin"
  "iso" "img" "vhd" "vmdk" "qcow2"
  "zip" "tar" "gz" "bz2" "xz" "7z" "rar"
  "mp4" "mkv" "avi" "mov" "wmv"
  "mp3" "flac" "wav" "aac" "ogg"
  "jpg" "jpeg" "png" "gif" "bmp" "tiff" "webp"
  "pdf" "doc" "docx" "xls" "xlsx" "ppt" "pptx"
  "sqlite" "sqlite3" "mdb" "accdb"
  "dmp" "core" "crash"
  "pak" "obb" "cache"
  "o" "obj" "so" "a" "lib" "class"
)

# Plausible base names (system DLLs, processes, config files, etc.)
BASENAMES=(
  # Windows system DLLs / processes
  "ntdll" "kernel32" "user32" "gdi32" "advapi32" "shell32" "ole32"
  "svchost" "rundll32" "taskhostw" "winlogon" "csrss" "smss"
  "lsass" "spoolsv" "explorer" "iexplore" "firefox" "chrome"
  "updater" "sihost" "runtimebroker" "dwm" "ctfmon" "msiexec"
  "wuauclt" "searchindexer" "dllhost" "wmiadap"

  # Additional Windows internals
  "services" "lsm" "conhost" "fontdrvhost" "audiodg"
  "trustedinstaller" "sppsvc" "werfault" "wermgr"
  "backgroundtaskhost" "securityhealthservice"
  "securityhealthsystray" "devicecensus"

  # Linux / Unix daemons
  "systemd" "init" "cron" "dbus" "networkmanager"
  "udevd" "sshd" "bash" "zsh" "login" "agetty"
  "rsyslogd" "cupsd" "polkitd"

  # Generic service / updater names
  "service" "services" "daemon" "helper" "monitor"
  "agent" "worker" "scheduler" "launcher" "installer"
  "patcher" "autoupdate" "updater64" "host" "client"

  # Browsers / apps
  "edge" "msedge" "opera" "brave" "discord"
  "steam" "spotify" "teams" "slack" "zoom"

  # Database / storage
  "sqlite" "database" "storage" "index" "cache2"
  "sessionstore" "cookies" "webcache"

  # System files
  "pagefile" "hiberfil" "config" "system"
  "software" "sam" "security"

  # User / data files
  "default" "ntuser" "usrclass" "cache" "temp"
  "data" "log" "dump" "backup" "settings"
  "init" "catalog" "history"

  # Filesystem artifacts
  "thumbcache" "iconcache" "edb" "mft"
  "journal" "usnjrnl" "swapfile"

  # Generic noisy names
  "debug" "report" "archive" "old" "new"
  "copy" "copy1" "test" "sample" "misc"
)

# ---------------------------------------------------------------------------
# Generate a random legitimate filename (base_XXXX.ext)
# ---------------------------------------------------------------------------
generate_filename() {
    local base="${BASENAMES[$((RANDOM % ${#BASENAMES[@]}))]}"
    local ext="${EXTENSIONS[$((RANDOM % ${#EXTENSIONS[@]}))]}"
    # 4-digit random hex suffix to virtually eliminate collisions
    local suffix
    suffix=$(printf "%04x" $((RANDOM % 65536)))
    echo "${base}_${suffix}.${ext}"
}

# ---------------------------------------------------------------------------
# Main renaming logic
# ---------------------------------------------------------------------------
rename_files() {
    local target_dir="$1"
    local dry_run=false
    [[ "${2:-}" == "--dry-run" ]] && dry_run=true

    if [[ ! -d "$target_dir" ]]; then
        echo "[-] Error: '$target_dir' is not a directory." >&2
        exit 1
    fi

    # Process only regular, non-hidden files in the immediate directory
    while IFS= read -r -d '' file; do
        local dir
        dir=$(dirname "$file")
        local new_name

        # Retry up to 100 times to find a non-existing name
        local collision=true
        for ((i = 0; i < 100; i++)); do
            new_name=$(generate_filename)
            if [[ ! -e "$dir/$new_name" ]]; then
                collision=false
                break
            fi
        done

        if $collision; then
            echo "[-] Skipping $file: could not generate a unique name after 100 attempts." >&2
            continue
        fi

        if $dry_run; then
            echo "[DRY-RUN] $(basename "$file") -> $new_name"
        else
            # Move (rename) without overwriting existing files
            if mv -n "$file" "$dir/$new_name"; then
                echo "[+] Renamed: $(basename "$file") -> $new_name"
            else
                echo "[-] Failed to rename: $file" >&2
            fi
        fi
    done < <(find "$target_dir" -maxdepth 1 -type f ! -name '.*' -print0)
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <directory> [--dry-run]"
    echo "  Renames all files in <directory> to legitimate-looking names."
    exit 1
fi

rename_files "$1" "${2:-}"
