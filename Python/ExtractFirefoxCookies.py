import argparse
import configparser
import json
import os
import shutil
import sqlite3
import sys
import hashlib
from pathlib import Path
import tempfile
from datetime import datetime


# ------------------------------------------------------------
# Utility Functions
# ------------------------------------------------------------

def sha256_file(path):
    """Return SHA256 hash of a file"""
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(8192):
            h.update(chunk)
    return h.hexdigest()


def firefox_time(ts):
    """Convert Firefox microsecond timestamp to UTC datetime"""
    if not ts:
        return None
    return datetime.utcfromtimestamp(ts / 1_000_000).isoformat()


# ------------------------------------------------------------
# Firefox Profile Discovery
# ------------------------------------------------------------

def get_firefox_root():
    if sys.platform.startswith("win"):
        return Path(os.environ["APPDATA"]) / "Mozilla" / "Firefox"
    elif sys.platform.startswith("linux"):
        return Path.home() / ".mozilla" / "firefox"
    elif sys.platform == "darwin":
        return Path.home() / "Library/Application Support/Firefox"
    else:
        raise RuntimeError("Unsupported OS")


def find_default_profile():
    firefox_root = get_firefox_root()
    profiles_ini = firefox_root / "profiles.ini"

    if not profiles_ini.exists():
        raise FileNotFoundError("profiles.ini not found")

    config = configparser.ConfigParser()
    config.read(profiles_ini, encoding="utf-8")

    # New format
    for section in config.sections():
        if section.startswith("Install"):
            default_path = config.get(section, "Default", fallback=None)
            if default_path:
                profile_path = firefox_root / default_path
                if (profile_path / "cookies.sqlite").exists():
                    return profile_path

    # Old format
    for section in config.sections():
        if section.startswith("Profile"):
            if config.get(section, "Default", fallback="0") == "1":
                path = config.get(section, "Path", fallback=None)
                is_relative = config.get(section, "IsRelative", fallback="1") == "1"
                profile_path = (firefox_root / path) if is_relative else Path(path)
                if (profile_path / "cookies.sqlite").exists():
                    return profile_path

    raise FileNotFoundError("No Firefox profile with cookies.sqlite found")


# ------------------------------------------------------------
# Cookie Extraction (Extended Fields)
# ------------------------------------------------------------

def load_cookies(db_path, domain=None):
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    cur = conn.cursor()

    query = """
    SELECT host, name, value, path, expiry,
           isSecure, isHttpOnly, sameSite,
           creationTime, lastAccessed
    FROM moz_cookies
    """

    if domain:
        query += " WHERE host LIKE ?"
        cur.execute(query, (f"%{domain}%",))
    else:
        cur.execute(query)

    rows = cur.fetchall()
    conn.close()
    return rows


# ------------------------------------------------------------
# Netscape Export
# ------------------------------------------------------------

def export_netscape(cookies, output_file):
    with open(output_file, "w", encoding="utf-8") as f:
        f.write("# Netscape HTTP Cookie File\n")
        for c in cookies:
            host, name, value, path, expiry, secure, *_ = c
            include_subdomain = "TRUE" if host.startswith(".") else "FALSE"
            secure_flag = "TRUE" if secure else "FALSE"
            expiry = expiry if expiry else 0

            f.write(
                f"{host}\t{include_subdomain}\t{path}\t"
                f"{secure_flag}\t{expiry}\t{name}\t{value}\n"
            )


# ------------------------------------------------------------
# Main
# ------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Advanced Firefox Cookie Extractor (Red/Blue Training)"
    )

    parser.add_argument("--domain", help="Filter cookies by domain")
    parser.add_argument("--all", action="store_true", help="Show all cookies")
    parser.add_argument("--out", help="Save cookies to JSON")
    parser.add_argument("--netscape", help="Export cookies in Netscape format")
    parser.add_argument("--hash", action="store_true", help="Display SHA256 of original DB")

    args = parser.parse_args()

    if not args.domain and not args.all:
        parser.error("Use --domain or --all")

    profile = find_default_profile()
    cookies_db = profile / "cookies.sqlite"

    if args.hash:
        print(f"[+] SHA256 (original DB): {sha256_file(cookies_db)}")

    # Work on a temp copy (safe acquisition)
    with tempfile.NamedTemporaryFile(delete=False) as tmp:
        tmp_path = Path(tmp.name)

    shutil.copy(cookies_db, tmp_path)

    try:
        cookies = load_cookies(tmp_path, args.domain)
    finally:
        tmp_path.unlink(missing_ok=True)

    # Netscape export
    if args.netscape:
        export_netscape(cookies, args.netscape)
        print(f"[+] Netscape cookies saved to {args.netscape}")

    # JSON export
    if args.out:
        data = []
        for c in cookies:
            data.append({
                "host": c[0],
                "name": c[1],
                "value": c[2],
                "path": c[3],
                "expiry": c[4],
                "isSecure": c[5],
                "isHttpOnly": c[6],
                "sameSite": c[7],
                "creationTime": firefox_time(c[8]),
                "lastAccessed": firefox_time(c[9])
            })

        with open(args.out, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)

        print(f"[+] Saved {len(cookies)} cookies to {args.out}")

    # Console output
    if not args.out and not args.netscape:
        for c in cookies:
            print(
                f"{c[0]}\t{c[1]}={c[2]} "
                f"(Created: {firefox_time(c[8])})"
            )


if __name__ == "__main__":
    main()
