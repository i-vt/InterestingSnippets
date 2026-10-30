#!/usr/bin/env python3
"""
user_files_tree.py v2 - print a directory tree that highlights user-generated files,
and export a forensic/operator triage record per file (CSV and/or JSON Lines).

Built for forensic triage of a user profile (e.g. C:\\Users\\<name>): separates
content a human likely authored/captured from downloads and machine noise.

Interest levels
---------------
  HIGH   *  user-authored/captured content (docs, photos, video, code, secrets, ...)
  MEDIUM .  user-acquired content (downloads: archives, installers, data) + forensic artifacts
  LOW       machine-generated noise (caches, logs, .tmp, Thumbs.db, ...)

Scoring (0-25, higher shows first in the BLUF brief)
---------------
  P  path       user work areas and credential dirs score high
  E  extension  credential and script types score high; bulk media scores low
  R  recency    fresh files score high
  N  name       keywords like password, token, payroll, vpn score high;
               capture prefixes (IMG_, Screenshot) and name patterns
               (double extension, SSN shape, date, version) also score
  S  size       small files score high because they exfil fast
Marks: !!! score 20-25 (grab first), !! 14-19, ! 8-13, . 3-7, blank under 3.

Usage
-----
    python user_files_tree.py "C:\\Users\\jdoe"
    python user_files_tree.py /mnt/evidence/Users/jdoe --max-depth 4
    python user_files_tree.py . --show-all --include-system
    python user_files_tree.py . --csv hits.csv --jsonl hits.jsonl --mark-recent 14
    python user_files_tree.py . --bluf brief.md --csv hits.csv
    python user_files_tree.py . --only-cats creds,media
    python user_files_tree.py . --only-cats "db,capture files" --csv db.csv

Export notes
------------
- CSV: flat, snake_case columns, utf-8-sig (Excel-safe), one row per file.
- JSONL: one nested JSON object per line (.jsonl), same underlying record.
- Score columns: score plus one column per criterion (score_path, score_extension,
  score_recency, score_name, score_size) and a score_detail summary.
- BLUF: a short brief for operators. It lists the directories and files to
  look at first, ranked by score. It uses BLUF style and ASD-STE100 rules.
- Timestamps are ISO 8601 with local timezone plus a numeric mtime_epoch column.
- Windows-only fields (change_time, ads, zone_id/host_url/referrer_url, ntfs
  attributes) are null on other platforms.
- pe_signed is a cheap presence check of the PE security directory (Authenticode
  data present), NOT a validity check; only with --signature.

Schema version: 2.0
"""

from __future__ import annotations

import argparse
import csv
import fnmatch
import json
import os
import re
import stat
import sys
import time
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

try:
    import pwd
except ImportError:  # Windows
    pwd = None

SCHEMA_VERSION = "2.1"

# ---------------------------------------------------------------------------
# Classification tables
#
# Case rule: every table key below is lowercase. Every comparison lowercases
# the value first. Classification and scoring are case-insensitive on all
# platforms, including Windows where names can arrive in any case.
# ---------------------------------------------------------------------------

# HIGH interest: content a user typically authors or captures
USER_CONTENT = {
    "documents":       {".docx", ".doc", ".odt", ".rtf", ".txt", ".md",
                        ".markdown", ".rst", ".adoc", ".tex", ".org",
                        ".pdf", ".one", ".epub"},
    "documents (macro)": {".docm", ".xlsm", ".pptm", ".potm", ".ppam", ".xltm",
                        ".docb", ".wpsm", ".xlam", ".dotm", ".sldm"},
    "spreadsheets":    {".xlsx", ".xls", ".ods", ".csv", ".tsv", ".numbers"},
    "presentations":   {".pptx", ".ppt", ".odp", ".key"},
    "images":          {".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tiff", ".tif",
                        ".heic", ".heif", ".hif", ".webp", ".raw", ".dng",
                        ".cr2", ".nef", ".orf", ".arw", ".rw2", ".pef", ".raf",
                        ".avif", ".jxl", ".svg"},
    "video":           {".mp4", ".mov", ".mkv", ".avi", ".wmv", ".webm", ".m4v",
                        ".flv", ".3gp"},
    "audio":           {".mp3", ".wav", ".flac", ".m4a", ".aac", ".ogg", ".wma"},
    "design/creative": {".psd", ".ai", ".indd", ".xd", ".fig", ".sketch",
                        ".blend", ".prproj", ".aep", ".drawio", ".xmind",
                        ".afphoto", ".afdesign", ".xcf"},
    "code/notebooks":  {".py", ".js", ".ts", ".html", ".css", ".java", ".c",
                        ".cpp", ".h", ".cs", ".go", ".rs", ".rb", ".php",
                        ".sql", ".ipynb", ".r", ".sh", ".ps1", ".bat",
                        ".cmd", ".vbs", ".hta", ".psm1", ".psd1", ".pl",
                        ".pm", ".rhai", ".cjs", ".mjs", ".mts", ".cts",
                        ".jsx", ".tsx", ".hbs", ".ejs", ".twig", ".vue",
                        ".svelte", ".scss", ".less", ".sass", ".proto",
                        ".hpp", ".cc", ".cxx", ".f90", ".groovy"},
    "email/messages":  {".eml", ".msg", ".pst", ".ost", ".mbox", ".enex",
                        ".olm"},
    "contacts":        {".vcf"},
}

# HIGH interest: credential/secret material, mostly matched by NAME because
# key files famously have no extension.
SECRET_NAMES = {
    "id_rsa", "id_dsa", "id_ecdsa", "id_ed25519", ".netrc", ".pgpass",
    ".htpasswd", "credentials", "known_hosts", "authorized_keys",
    "sitemanager.xml",
    # answer files and state files that carry deploy credentials
    "unattend.xml", "autounattend.xml", "sysprep.inf", "ntds.dit",
    "wallet.dat", ".my.cnf",
}
SECRET_EXTS = {
    ".pem", ".key", ".ppk", ".p12", ".pfx", ".kdbx", ".ovpn", ".env",
    ".gpg", ".asc",
    # crypto material and keystores
    ".p8", ".jks", ".keystore", ".cer", ".crt", ".der", ".csr", ".p7b",
    ".p7c",
    # remote access and cloud state
    ".rdp", ".tfstate", ".tfvars", ".mobileconfig",
    # password manager and wallet containers
    ".wallet", ".crypt12", ".psafe3", ".1pif", ".opvault", ".kdb",
}
SECRET_PARENT_DIRS = {".ssh", ".aws", ".gnupg", ".azure", ".kube"}

# HIGH interest: shell history is a direct map of what the user typed.
HISTORY_NAMES = {
    ".bash_history", ".zsh_history", ".python_history", ".mysql_history",
    ".psql_history", ".rediscli_history", ".lesshst", ".viminfo",
    ".nano_history", "consolehost_history.txt",
}

# Database file extensions. Grouped by family. Ranges are expanded.
# .kdb stays in SECRET_EXTS (KeePass). .pdb stays in libraries (Program
# Database symbols). .sql stays in code (it is a script, not a database).
DATABASE_EXTS = {
    # Microsoft Access and Jet
    ".accdb", ".accdc", ".accde", ".accdr", ".accdt", ".accft", ".accdw",
    ".adn", ".ade", ".adp", ".maf", ".maq", ".mar", ".mas", ".mav",
    ".maw", ".mdn", ".mdt", ".mdb",
    # SQL Server
    ".mdf", ".ndf", ".dacpac", ".dtsx", ".dsn", ".udl", ".trc",
    # MySQL and MariaDB
    ".myd", ".myi", ".frm", ".ibd", ".mrg",
    # SQLite and embedded databases
    ".sqlite", ".sqlite3", ".db", ".db3", ".db-shm", ".db-wal",
    # Oracle, dBase, FoxPro
    ".ora", ".dbf", ".dbt", ".dbv", ".dbc", ".dct", ".dcx", ".fpt",
    ".scx", ".db2",
    # Firebird and InterBase
    ".fdb", ".gdb", ".ib", ".idb",
    # Lotus Notes, GroupWise, Exchange, Outlook Express
    ".nsf", ".ns2", ".ns3", ".ns4", ".dxl", ".gwi", ".edb", ".dbx",
    # FileMaker
    ".fp3", ".fp4", ".fp5", ".fp6", ".fp7", ".fm5", ".fmp", ".fmp12",
    ".fmpsl", ".nrmlib",
    # Queries and connection files (can hold connection strings)
    ".qry", ".dqy", ".qvd", ".mwb",
    # Personal information managers and address books
    ".epim", ".abcddb", ".itdb",
    # Analytics
    ".sas7bdat",
    # Legacy and misc databases
    ".4dd", ".4dl", ".adb", ".adf", ".arc", ".alf", ".ask", ".bdf",
    ".btr", ".cat", ".cdb", ".ckp", ".cma", ".cpd", ".dad",
    ".dadiagrams", ".daschema", ".dcb", ".ddl", ".dlis", ".dp1", ".dsk",
    ".eco", ".ecx", ".exb", ".fcd", ".fic", ".fol", ".grdb", ".hdb",
    ".his", ".ihx", ".itw", ".jet", ".jtx", ".kexi", ".kexic", ".kexis",
    ".lgc", ".lwx", ".mpd", ".mud", ".nnt", ".nv", ".nv2", ".nwdb",
    ".nyf", ".odb", ".ogy", ".orx", ".owc", ".p96", ".p97", ".pan",
    ".pdm", ".pnz", ".rbf", ".rctd", ".rod", ".rodx", ".rpd", ".rsd",
    ".sbf", ".sdb", ".sdc", ".sdf", ".sis", ".spg", ".te", ".temx",
    ".tmd", ".tps", ".trm", ".udb", ".usr", ".v12", ".vis", ".vpd",
    ".vvv", ".wdb", ".wmdb", ".wrk", ".xdb", ".xld", ".xmlff", ".abs",
    ".abx", ".hjt", ".icg", ".icr", ".lut",
}

# MEDIUM interest: acquired by the user (downloads) rather than authored
USER_ADJACENT = {
    "archives":   {".zip", ".rar", ".7z", ".tar", ".gz", ".bz2", ".xz",
                   ".tgz", ".tbz2", ".cab", ".zst", ".lz", ".lzma", ".jar"},
    "installers": {".exe", ".msi", ".dmg", ".pkg", ".iso", ".apk", ".msix",
                   ".appx", ".appxbundle", ".deb", ".rpm"},
    "data/misc":  {".json", ".xml", ".yaml", ".yml", ".ovpn", ".vhd",
                   ".vhdx", ".ini", ".cfg", ".conf", ".config",
                   ".properties", ".toml", ".reg", ".evtx", ".cnf"},
    "disk images": {".img", ".vmdk", ".vdi", ".ova", ".ovf", ".e01", ".ex01",
                    ".wim"},
    "database files": DATABASE_EXTS,
    "backups":    {".bak", ".backup"},
    "capture files": {".pcap", ".pcapng"},
    # libraries and symbol stores, usually tooling
    "libraries":  {".dll", ".so", ".lib", ".a", ".pyd", ".pdb", ".csproj",
                   ".sln", ".vcxproj"},
    # browser extension packages
    "browser packages": {".crx", ".xpi"},
}

# MEDIUM interest: machine-kept records that are evidence of user activity
FORENSIC_ARTIFACTS = {".lnk", ".pf"}

# LOW interest: machine-generated noise
MACHINE_FILE_NAMES = {
    "thumbs.db", "desktop.ini", "iconcache.db", "ntuser.dat", "ntuser.ini",
    "ntuser.pol", "usrclass.dat", "ehthumbs.db", ".ds_store",
}
MACHINE_FILE_GLOBS = [
    "ntuser.dat.*", "usrclass.dat.*", "*.tmp", "*.temp", "*.log", "*.log1",
    "*.log2", "*.pf?", "*.etl", "*.dmp", "*.chk", "*.lock", "*.blf",
    "*.regtrans-ms", "*.crdownload", "*.part", "*.partial", "~$*",
    # compiled and generated artifacts
    "*.pyc", "*.pyo", "*.class", "*.o", "*.obj", "*.map", "*.rmeta",
    "*.dist-info",
]
# Fonts and icons have low triage value on a user profile.
LOW_VALUE_EXTS = {".ttf", ".otf", ".woff", ".woff2", ".eot", ".ico"}
SYSTEM_DIRS = {
    "appdata", "application data", "local settings", "$recycle.bin", "recycler",
    "system volume information", "msocache", "perflogs", "__pycache__",
    ".git", ".svn", "node_modules", ".cache", ".config",
}

# Folders that strongly imply user content lives below
USER_AREA_DIRS = {
    "desktop", "documents", "downloads", "pictures", "videos", "music",
    "saved games", "onedrive", "dropbox", "google drive", "icloud drive",
}

# Operator-facing groups. An operator picks one or more with --only-cats.
# Each group maps to the fine categories used in classification. Operators
# can also pass a fine category name directly, for example "capture files".
CATEGORY_GROUPS = {
    "creds":    {"secrets/credentials", "shell history"},
    "media":    {"images", "video", "audio", "design/creative"},
    "docs":     {"documents", "documents (macro)", "spreadsheets",
                 "presentations", "email/messages", "contacts"},
    "code":     {"code/notebooks"},
    "db":       {"database files"},
    "acquired": {"archives", "installers", "data/misc", "disk images",
                 "backups", "libraries", "browser packages",
                 "capture files"},
    "forensic": {"forensic artifacts"},
    "noise":    {"machine-generated", "fonts/icons", "unknown"},
}

ALL_CATEGORIES = {
    "secrets/credentials", "shell history", "documents",
    "documents (macro)", "spreadsheets", "presentations", "images",
    "video", "audio", "design/creative", "code/notebooks",
    "email/messages", "contacts", "archives", "installers", "data/misc",
    "disk images", "database files", "backups", "capture files",
    "libraries", "browser packages", "forensic artifacts",
    "fonts/icons", "machine-generated", "unknown-type in user folder",
    "unknown",
}


def resolve_categories(tokens: list[str]) -> set:
    """Turn operator input into a set of categories.
    Accepts group names and fine category names. Raises ValueError."""
    cats: set = set()
    for raw in tokens:
        for tok in raw.split(","):
            tok = tok.strip().lower()
            if not tok:
                continue
            if tok in CATEGORY_GROUPS:
                cats |= CATEGORY_GROUPS[tok]
            elif tok in ALL_CATEGORIES:
                cats.add(tok)
            else:
                valid = ", ".join(sorted(CATEGORY_GROUPS))
                raise ValueError(
                    f"unknown category '{tok}'. Use a group: {valid}. "
                    "Or a category name, for example 'capture files'.")
    return cats

MARK  = {"HIGH": "*", "MEDIUM": ".", "LOW": " "}
LEVEL_RANK = {"HIGH": 0, "MEDIUM": 1, "LOW": 2}
COLOR = {"HIGH": "\033[1;33m", "MEDIUM": "\033[36m", "LOW": "\033[2m",
         "DIR": "\033[1;34m", "LINK": "\033[35m", "RESET": "\033[0m"}

# ---------------------------------------------------------------------------
# Scoring model
#
# Every file gets a score from 0 to 25. Five criteria, 0 to 5 points each.
# Higher score means higher red team value and easier exfil.
# The BLUF brief sorts by this score.
#
#   P  path        where the file lives
#   E  extension   what kind of content it holds
#   R  recency     how fresh it is
#   N  name        keywords in the file name
#   S  size        small files are easy to exfil fast
# ---------------------------------------------------------------------------

# Path score: user work areas are rich. Machine paths are poor.
PATH_SCORE = {
    "desktop": 5, "documents": 5, "onedrive": 5, "dropbox": 5,
    "google drive": 5, "icloud drive": 5,
    "downloads": 4, "pictures": 4, "videos": 4, "favorites": 4,
    "music": 3, "contacts": 3, "links": 3,
}
for _d in SECRET_PARENT_DIRS:
    PATH_SCORE[_d] = 5

# Extension score by content value.
# 5 = credentials or execution. 4 = dense user data. 3 = media. 2 = tools.
# 1 = bulk media. 0 = everything else.
EXT_SCORE = {
    # credentials and keys (also see classify_file: these are HIGH anyway)
    ".pem": 5, ".key": 5, ".ppk": 5, ".p12": 5, ".pfx": 5, ".kdbx": 5,
    ".ovpn": 5, ".env": 5, ".gpg": 5, ".asc": 5, ".p8": 5, ".jks": 5,
    ".keystore": 5, ".cer": 5, ".crt": 5, ".der": 5, ".csr": 5,
    ".p7b": 5, ".p7c": 5, ".rdp": 5, ".tfstate": 5, ".tfvars": 5,
    ".mobileconfig": 5, ".wallet": 5, ".crypt12": 5, ".psafe3": 5,
    ".1pif": 5, ".opvault": 5, ".kdb": 5,
    # execution and scripting
    ".ps1": 5, ".bat": 5, ".cmd": 5, ".vbs": 5, ".hta": 5, ".py": 4,
    ".js": 4, ".sh": 4, ".psm1": 4, ".psd1": 4, ".pl": 4, ".pm": 4,
    ".cjs": 4, ".mjs": 4, ".jsx": 4, ".tsx": 4, ".vue": 4, ".svelte": 4,
    ".cs": 4, ".go": 4, ".rs": 4, ".java": 4, ".php": 4, ".rb": 4,
    ".cpp": 4, ".hpp": 4, ".cc": 4, ".rhai": 3, ".proto": 3,
    ".hbs": 3, ".ejs": 3, ".twig": 3, ".scss": 2, ".less": 2, ".sass": 2,
    ".css": 2, ".html": 2, ".htm": 2, ".groovy": 3,
    # user data with high credential density
    ".docx": 5, ".doc": 5, ".pdf": 5, ".odt": 4, ".rtf": 4, ".txt": 4,
    ".md": 4, ".markdown": 4, ".xlsx": 5, ".xls": 5, ".csv": 5,
    ".tsv": 4, ".ods": 4, ".pst": 5, ".ost": 5, ".msg": 4, ".eml": 4,
    ".mbox": 4, ".one": 4,
    # configuration and state
    ".json": 4, ".xml": 4, ".yaml": 4, ".yml": 4, ".ini": 4, ".cfg": 4,
    ".conf": 4, ".config": 4, ".properties": 4, ".toml": 4, ".reg": 4,
    ".sqlite": 4, ".sqlite3": 4, ".db": 4, ".db3": 4, ".evtx": 4,
    # packet captures and database files hold sessions and records
    ".pcap": 4, ".pcapng": 4,
    # full databases: records, queries, sometimes credentials
    ".sql": 4, ".mdf": 4, ".ndf": 4, ".edb": 4, ".nsf": 4, ".fdb": 4,
    ".gdb": 4, ".sdf": 4, ".dbf": 4, ".mdb": 4, ".accdb": 4, ".dsn": 4,
    ".udl": 4, ".dtsx": 4, ".qry": 4, ".mwb": 4, ".pdm": 4, ".ddl": 4,
    ".dbx": 4, ".abcddb": 4, ".epim": 4, ".sas7bdat": 4, ".btr": 4,
    ".qvd": 4, ".ib": 4, ".myi": 4, ".mrg": 4, ".db2": 4, ".frm": 4,
    # database sidecars, journals, and connection helpers
    ".db-shm": 3, ".db-wal": 3, ".ckp": 3, ".dadiagrams": 3, ".daschema": 3,
    ".dacpac": 3, ".dct": 3, ".dcx": 3, ".dbt": 3, ".dbv": 3, ".fpt": 3,
    ".trc": 3, ".his": 3, ".odb": 3, ".sdb": 3, ".wdb": 3, ".ns2": 3,
    ".ns3": 3, ".ns4": 3, ".dxl": 3, ".gwi": 3, ".fp3": 3, ".fp4": 3,
    ".fp5": 3, ".fp6": 3, ".fp7": 3, ".fm5": 3, ".fmp": 3, ".fmp12": 3,
    ".fmpsl": 3, ".nrmlib": 3, ".kexi": 3, ".kexic": 3, ".kexis": 3,
    ".hdb": 3, ".cat": 3, ".dbc": 3, ".scx": 3, ".sdc": 3, ".udb": 3,
    ".nwdb": 3, ".nyf": 3, ".exb": 3, ".itdb": 3, ".itw": 3,
    ".dcb": 3, ".dsk": 2, ".wmdb": 2,
    ".4dd": 3, ".4dl": 3, ".adb": 3, ".adf": 3, ".arc": 3, ".alf": 3,
    ".ask": 3, ".bdf": 3, ".cdb": 3, ".cma": 3, ".cpd": 3, ".dad": 3,
    ".dlis": 3, ".dp1": 3, ".eco": 3, ".ecx": 3, ".fcd": 3, ".fic": 3,
    ".fol": 3, ".grdb": 3, ".ihx": 3, ".jet": 3, ".jtx": 3, ".lgc": 3,
    ".lwx": 3, ".maf": 3, ".maq": 3, ".mar": 3, ".mas": 3, ".mav": 3,
    ".maw": 3, ".mdn": 3, ".mdt": 3, ".mpd": 3, ".mud": 3, ".nnt": 3,
    ".nv": 3, ".nv2": 3, ".ogy": 3, ".orx": 3, ".owc": 3, ".p96": 3,
    ".p97": 3, ".pan": 3, ".pnz": 3, ".rbf": 3, ".rctd": 3, ".rod": 3,
    ".rodx": 3, ".rpd": 3, ".rsd": 3, ".sbf": 3, ".sis": 3, ".spg": 3,
    ".te": 3, ".temx": 3, ".tmd": 3, ".tps": 3, ".trm": 3, ".usr": 3,
    ".v12": 3, ".vis": 3, ".vpd": 3, ".vvv": 3, ".wrk": 3, ".xdb": 3,
    ".xld": 3, ".xmlff": 3, ".abs": 3, ".abx": 3, ".hjt": 3, ".icg": 3,
    ".icr": 3, ".lut": 3, ".accdc": 3, ".accde": 3, ".accdr": 3,
    ".accdt": 3, ".accft": 3, ".accdw": 3, ".adn": 3, ".ade": 3,
    ".adp": 3, ".ora": 3, ".idb": 3,
    # archives bundle loot
    ".zip": 4, ".rar": 4, ".7z": 4, ".tar": 4, ".gz": 4, ".tgz": 4,
    ".jar": 4,
    # backups are old data with old credentials
    ".bak": 4, ".backup": 4,
    # media, moderate value. Camera RAW and phone formats keep full score.
    ".jpg": 3, ".jpeg": 3, ".png": 3, ".heic": 3, ".heif": 3, ".hif": 3,
    ".webp": 3, ".raw": 3, ".dng": 3, ".cr2": 3, ".nef": 3, ".orf": 3,
    ".arw": 3, ".rw2": 3, ".pef": 3, ".raf": 3, ".tif": 3, ".tiff": 3,
    ".gif": 2, ".bmp": 2, ".avif": 2, ".jxl": 2, ".svg": 3,
    ".mp3": 2, ".wav": 2, ".flac": 2,
    # tools and installers
    ".exe": 2, ".msi": 2, ".msix": 2, ".appx": 2, ".apk": 2, ".iso": 2,
    ".dmg": 2, ".pkg": 2, ".deb": 2, ".rpm": 2,
    # libraries and symbol stores
    ".dll": 2, ".so": 2, ".lib": 2, ".pyd": 2, ".pdb": 2, ".csproj": 3,
    ".sln": 3, ".vcxproj": 3,
    # browser extension packages can carry useful config
    ".crx": 3, ".xpi": 3,
    # disk images and bulk media: heavy, low density
    ".vhd": 2, ".vhdx": 2, ".vmdk": 2, ".img": 2, ".ova": 2, ".ovf": 2,
    ".e01": 2, ".ex01": 2, ".wim": 2,
    ".mp4": 1, ".mov": 1, ".mkv": 1, ".avi": 1, ".wmv": 1, ".webm": 1,
    # fonts and compiled artifacts: near zero triage value
    ".ttf": 0, ".otf": 0, ".woff": 0, ".woff2": 0, ".eot": 0, ".ico": 0,
    ".pyc": 0, ".pyo": 0, ".class": 0, ".o": 0, ".obj": 0, ".map": 0,
    ".xcf": 1,
}

# Name keywords. Match against the file name, words only.
NAME_KEYWORDS = {
    # credentials and access
    "password": 5, "passwd": 5, "pwd": 5, "credential": 5, "creds": 5,
    "cred": 5, "secret": 5, "token": 5, "apikey": 5, "api_key": 5, "api-key": 5,
    "passphrase": 5, "private": 5, "vault": 5, "wallet": 5,
    "login": 5, "logon": 5, "unlock": 5,
    # keys by any extension
    "id_rsa": 5, "id_dsa": 5, "id_ecdsa": 5, "id_ed25519": 5,
    # identity and money
    "ssn": 5, "passport": 5, "driverlicense": 4, "tax": 4, "salary": 4,
    "payroll": 5, "bank": 4, "iban": 4, "routing": 4, "card": 3,
    "invoice": 3, "contract": 4, "nda": 4,
    # business data
    "customer": 3, "client": 3, "patient": 4, "student": 3, "employee": 3,
    "hr": 3, "finance": 3, "budget": 3, "forecast": 3, "revenue": 3,
    "acquisition": 4, "merger": 4, "board": 3, "confidential": 4,
    "internal": 3, "restricted": 4, "proprietary": 4, "trade_secret": 5,
    "roadmap": 3, "strategy": 3,
    # system and access words
    "admin": 4, "administrator": 4, "root": 4, "sudo": 4, "sudoers": 5,
    "shadow": 5, "sam": 4, "ntds": 5, "backup": 4, "bak": 3, "old": 1,
    "archive": 3, "dump": 4, "export": 3, "exfil": 5,
    "vpn": 4, "wifi": 4, "wireless": 4, "portal": 3, "sso": 4, "mfa": 4,
    "otp": 5, "2fa": 4, "seed": 4, "recovery": 4, "master": 4,
    "session": 3, "sessions": 3, "cookie": 4, "cookies": 4,
    "keyring": 5, "keyrings": 5, "keys": 4, "certs": 3,
    "truststore": 4, "keystore": 5, "htaccess": 5, "htpasswd": 5,
    # less specific
    "config": 3, "setup": 2, "install": 2, "deploy": 3, "prod": 3,
    "production": 3, "dev": 2, "test": 1, "draft": 2, "final": 2,
    "review": 2, "audit": 3, "report": 3,
}

# Recency windows, in seconds: (max_age, points)
RECENCY_STEPS = [
    (86400,        5, "modified in the last day"),
    (7 * 86400,    4, "modified in the last week"),
    (30 * 86400,   3, "modified in the last month"),
    (180 * 86400,  2, "modified in the last 6 months"),
    (float("inf"), 1, "older"),
]

# Size windows: (max_bytes, points, label). Small files exfil fast.
SIZE_STEPS = [
    (10 * 1024,             5, "under 10 KiB"),
    (1024 * 1024,           4, "under 1 MiB"),
    (10 * 1024 * 1024,      3, "under 10 MiB"),
    (100 * 1024 * 1024,     2, "under 100 MiB"),
    (1024 ** 3,             1, "under 1 GiB"),
    (float("inf"),          0, "1 GiB or more"),
]


def score_path(rel: str) -> tuple[int, str]:
    """Points for the directory chain. Best matching ancestor wins."""
    parts = [p.lower() for p in rel.split("/")[:-1]]
    best = (0, "regular path")
    for p in parts:
        if p in PATH_SCORE and PATH_SCORE[p] > best[0]:
            best = (PATH_SCORE[p], f"path contains '{p}'")
    return best


# File name beginnings that mark captured media. Photos and videos the user
# took often hold documents, whiteboards, and screens.
# Score: how strong the signal is that this is user-captured content.
CAPTURE_PREFIXES = [
    (4, ("screenshot", "screen shot", "screen-shot", "screencapture",
         "capture")),          # screens show data by definition
    (3, ("img_", "img-", "pxl_", "mvimg_", "dsc", "dscf", "photo_",
         "mmexport")),          # phone and digital camera photos
    (3, ("dji_",)),             # drone photos, often map targets
    (2, ("vid_", "video_", "gopr", "insta360")),   # camera video
    (2, ("wa_", "signal-", "fb_img", "snapchat", "tiktok")),  # chat apps
]


# Name patterns. Regex checks on the lowercased file name. These catch
# naming tricks that keywords and prefixes miss. Checked after keywords and
# capture prefixes. Best match wins, same rule as the other name checks.
NAME_PATTERNS = [
    # double extension masquerade: a program hides behind a document type
    (5, re.compile(
        r"\.(pdf|jpe?g|png|gif|docx?|xlsx?|pptx?|txt|zip|rar|7z)\."
        r"(exe|scr|com|bat|cmd|vbs|vbe|js|jse|jar|msi|ps1|hta|lnk|url)$"),
     "name hides a program behind a document extension"),
    # SSN and card number shapes in the name. Card groups are 4-4-4-4 or
    # 4-6-5, so a photo timestamp does not match.
    (5, re.compile(r"\d{3}-\d{2}-\d{4}"), "name holds an SSN pattern"),
    (5, re.compile(r"\b\d{4}[ -]\d{4}[ -]\d{4}[ -]\d{4}\b|\b\d{4}[ -]\d{6}[ -]\d{5}\b"),
     "name holds a card number pattern"),
    # hidden extension: trailing dot or space before the extension
    (4, re.compile(r"[. ]$"), "name ends with a dot or space, extension is hidden"),
    (4, re.compile(r" \.[a-z0-9]{1,6}$"), "name hides the extension behind a space"),
    # hex name with no words: dropper and packed payload style
    (4, re.compile(r"^[a-f0-9]{8,32}(\.[a-z0-9]{1,5})?$"),
     "name is a hex string, dropper style"),
    # mail style name, saved from a mail client
    (3, re.compile(r"^[^ ]+@[^ ]+\.[a-z]{2,}"), "name looks like a mail address"),
    # date in the name: exports, statements, dumps
    (2, re.compile(r"\d{4}[-_.]?\d{2}[-_.]?\d{2}"), "name holds a date"),
    # version marker: working copies the user edits
    (2, re.compile(r"(?:^|[_-])v\d{1,3}\b"), "name holds a version marker"),
    # copy marker: files the user duplicated on purpose
    (1, re.compile(r"^copy of | - copy| - copy\.\w| \(\d+\)\.\w"),
     "name holds a copy marker"),
]


def score_name(name: str) -> tuple[int, str]:
    """Points for keywords, capture prefixes, and patterns in the name."""
    low = name.lower()
    best = (0, "no keyword in name")
    hits = [(pts, kw) for kw, pts in NAME_KEYWORDS.items() if kw in low]
    if hits:
        pts, kw = max(hits)
        best = (pts, f"name contains '{kw}'")
    for pts, prefixes in CAPTURE_PREFIXES:
        for prefix in prefixes:
            if low.startswith(prefix) and pts > best[0]:
                best = (pts, f"name starts with '{prefix}'")
    for pts, rx, why in NAME_PATTERNS:
        if rx.search(low) and pts > best[0]:
            best = (pts, why)
    return best


def score_record(rec: dict, now: float) -> tuple[int, dict]:
    """Score one record. Returns (total, parts). parts has one entry per
    criterion with points and the reason."""
    rel = rec["rel"]
    ext = rec["path"].suffix.lower()
    parts = {}
    p_pts, p_why = score_path(rel)
    parts["path"] = (p_pts, p_why)
    e_pts = EXT_SCORE.get(ext, 0)
    if rec["category"] == "secrets/credentials":
        e_pts = 5
    parts["extension"] = (e_pts, f"extension '{ext or '(none)'}'")
    n_pts, n_why = score_name(rec["name"])
    parts["name"] = (n_pts, n_why)

    mtime = rec["st"].st_mtime if rec["st"] is not None else None
    if mtime is None:
        parts["recency"] = (0, "no modified time")
    else:
        age = now - mtime
        for limit, pts, label in RECENCY_STEPS:
            if age <= limit:
                parts["recency"] = (pts, label)
                break
    size = rec["st"].st_size if rec["st"] is not None else None
    if size is None:
        parts["size"] = (0, "no size")
    else:
        for limit, pts, label in SIZE_STEPS:
            if size <= limit:
                parts["size"] = (pts, label)
                break
    total = sum(v[0] for v in parts.values())
    return total, parts


# Mark by score. Higher value and easier exfil means a stronger mark.
SCORE_TIERS = [
    (20, "!!!", "grab first"),
    (14, "!! ", "high value"),
    (8,  "!  ", "worth a look"),
    (3,  ".  ", "low"),
    (0,  "   ", "skip"),
]


def score_tier(score: int) -> tuple[str, str]:
    """Map a score to a mark and a label."""
    for cut, mark, label in SCORE_TIERS:
        if score >= cut:
            return mark, label
    return "   ", "skip"

CSV_COLUMNS = [
    "path_relative", "path_absolute", "name", "extension", "file_type",
    "interest", "category",
    "size_bytes", "size_human", "size_on_disk",
    "mtime", "atime", "ctime", "birth", "change_time",
    "mtime_epoch", "mtime_age_days", "timestamp_anomaly",
    "mode", "owner", "writable_by", "writable_by_current_user", "attributes",
    "ads_count", "ads", "zone_id", "host_url", "referrer_url",
    "file_id", "hardlink_count", "pe_signed", "symlink_target",
    "depth", "error", "schema_version",
    "score", "score_path", "score_extension", "score_recency",
    "score_name", "score_size", "score_detail",
]


# ---------------------------------------------------------------------------
# Pure helpers (unit-testable)
# ---------------------------------------------------------------------------

def classify_file(path: Path) -> tuple[str, str]:
    """Return (interest_level, category) for a file."""
    name = path.name.lower()
    if name in MACHINE_FILE_NAMES or any(fnmatch.fnmatch(name, g)
                                         for g in MACHINE_FILE_GLOBS):
        return "LOW", "machine-generated"

    ext = path.suffix.lower()
    parts = {p.lower() for p in path.parts}
    if ext in LOW_VALUE_EXTS:
        return "LOW", "fonts/icons"

    # secrets win over everything else: a .pem in Downloads is still a secret
    if name in SECRET_NAMES or ext in SECRET_EXTS or (parts & SECRET_PARENT_DIRS
                                                      and name in SECRET_NAMES):
        return "HIGH", "secrets/credentials"
    if name in HISTORY_NAMES:
        return "HIGH", "shell history"
    for category, exts in USER_CONTENT.items():
        if ext in exts:
            return "HIGH", category
    for category, exts in USER_ADJACENT.items():
        if ext in exts:
            return "MEDIUM", category
    if ext in FORENSIC_ARTIFACTS:
        return "MEDIUM", "forensic artifacts"
    # unknown extension, but sitting in a user area: worth a glance
    if parts & USER_AREA_DIRS:
        return "MEDIUM", "unknown-type in user folder"
    return "LOW", "unknown"


def human_size(n: int | None) -> str:
    if n is None:
        return ""
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if abs(n) < 1024 or unit == "TiB":
            return f"{n:.1f} {unit}" if unit != "B" else f"{n} B"
        n /= 1024
    return f"{n} B"  # unreachable, keeps type checkers calm


def iso_time(ts: float | None) -> str:
    if ts is None:
        return ""
    return datetime.fromtimestamp(ts, timezone.utc).astimezone().isoformat(
        timespec="seconds")


def clean_str(v):
    """Make a string safe for strict encoders (CSV, JSON, downstream tools):
    undecodable filesystem bytes become \\udcXX escapes instead of surrogates."""
    if isinstance(v, str):
        return v.encode("utf-8", errors="backslashreplace").decode("utf-8")
    return v


def parse_motw(text: str) -> dict:
    """Parse a Zone.Identifier stream body into zone_id / host_url / referrer_url."""
    out = {"zone_id": None, "host_url": "", "referrer_url": ""}
    for line in text.splitlines():
        if "=" not in line:
            continue
        k, v = line.split("=", 1)
        k, v = k.strip().lower(), v.strip()
        if k == "zoneid":
            out["zone_id"] = int(v)
        elif k == "hosturl":
            out["host_url"] = v
        elif k == "referrerurl":
            out["referrer_url"] = v
    return out


def pe_has_signature(path: Path) -> bool | None:
    """Presence (not validity) of an Authenticode security directory. None = not a PE."""
    try:
        with open(path, "rb") as fh:
            if fh.read(2) != b"MZ":
                return None
            fh.seek(0x3C)
            peoff = int.from_bytes(fh.read(4), "little")
            fh.seek(peoff)
            if fh.read(4) != b"PE\x00\x00":
                return None
            coff = fh.read(20)
            opt_size = int.from_bytes(coff[16:18], "little")
            opt = fh.read(opt_size)
            magic = int.from_bytes(opt[0:2], "little")
            if magic == 0x10B:      # PE32
                n_dir_off, dd_base = 92, 96
            elif magic == 0x20B:    # PE32+
                n_dir_off, dd_base = 108, 112
            else:
                return None
            n_dirs = int.from_bytes(opt[n_dir_off:n_dir_off + 4], "little")
            if n_dirs < 5:
                return False
            sec = opt[dd_base + 4 * 8: dd_base + 5 * 8]
            _rva, size = int.from_bytes(sec[0:4], "little"), int.from_bytes(sec[4:8], "little")
            return size > 0
    except Exception:
        return None


# ---------------------------------------------------------------------------
# Windows-only enrichments (all return None off-Windows or on any failure)
# ---------------------------------------------------------------------------

def _win_change_time(path: str) -> float | None:
    if os.name != "nt":
        return None
    try:
        import ctypes
        from ctypes import wintypes
        k32 = ctypes.windll.kernel32
        h = k32.CreateFileW(path, 0x80, 0x3, None, 3, 0x02000000, None)  # FILE_READ_ATTRIBUTES, OPEN_EXISTING
        if h in (None, -1):
            return None

        class FILE_BASIC_INFO(ctypes.Structure):
            _fields_ = [("CreationTime", ctypes.c_longlong),
                        ("LastAccessTime", ctypes.c_longlong),
                        ("LastWriteTime", ctypes.c_longlong),
                        ("ChangeTime", ctypes.c_longlong),
                        ("FileAttributes", wintypes.DWORD)]

        info = FILE_BASIC_INFO()
        ok = k32.GetFileInformationByHandleEx(h, 0, ctypes.byref(info),
                                              ctypes.sizeof(info))
        k32.CloseHandle(h)
        if not ok:
            return None
        return info.ChangeTime / 10_000_000 - 11644473600  # filetime -> epoch
    except Exception:
        return None


def _win_attributes(path: str) -> dict:
    """NTFS attribute flags that matter for triage. Empty dict off-Windows."""
    if os.name != "nt":
        return {}
    try:
        import ctypes
        F = ctypes.windll.kernel32.GetFileAttributesW(path)
        if F == 0xFFFFFFFF:
            return {}
        return {
            "hidden":        bool(F & 0x2),
            "system":        bool(F & 0x4),
            "readonly":      bool(F & 0x1),
            "compressed":    bool(F & 0x800),
            "encrypted":     bool(F & 0x4000),
            "offline":       bool(F & 0x1000),
            "cloud_stub":    bool(F & 0x400000),  # RECALL_ON_DATA_ACCESS
        }
    except Exception:
        return {}


def _win_streams(path: str) -> list | None:
    """NTFS alternate data stream names (['Zone.Identifier', ...]). None = n/a."""
    if os.name != "nt":
        return None
    try:
        import ctypes
        from ctypes import wintypes

        class FIND_STREAM_DATA(ctypes.Structure):
            _fields_ = [("StreamSize", ctypes.c_longlong),
                        ("cStreamName", wintypes.WCHAR * 296)]

        k32 = ctypes.windll.kernel32
        data = FIND_STREAM_DATA()
        h = k32.FindFirstStreamW(path, 0, ctypes.byref(data), 0)
        if h in (None, -1):
            return []
        names = []
        try:
            while True:
                raw = data.cStreamName  # like ":Zone.Identifier:$DATA"
                name = raw.split(":")[1] if raw.count(":") >= 2 else ""
                if name and name.lower() != "$data":
                    names.append(name)
                if not k32.FindNextStreamW(h, ctypes.byref(data)):
                    break
        finally:
            k32.FindClose(h)
        return names
    except Exception:
        return None


def _win_motw(path: str) -> dict | None:
    """Read and parse Zone.Identifier ADS. None = not present / not Windows."""
    if os.name != "nt":
        return None
    try:
        with open(path + ":Zone.Identifier", encoding="utf-8", errors="replace") as fh:
            return parse_motw(fh.read())
    except OSError:
        return None


# ---------------------------------------------------------------------------
# Record building (single stat per entry; single walk for all renderers)
# ---------------------------------------------------------------------------

def _writable_by(st) -> set:
    m = st.st_mode
    out = set()
    if m & stat.S_IWUSR:
        out.add("owner")
    if m & stat.S_IWGRP:
        out.add("group")
    if m & stat.S_IWOTH:
        out.add("everyone")
    return out


def build_file_record(full: Path, rel: str, depth: int, args,
                      st=None, err: str = "") -> dict:
    """Build the full triage record for one file. st is kept raw; flattening
    happens at export time so tree mode pays nothing extra for stat fields."""
    level, category = classify_file(full)
    rec = {
        "path": full, "rel": rel, "name": full.name, "depth": depth,
        "level": level, "category": category,
        "is_symlink": full.is_symlink(),
        "symlink_target": None,
        "is_junction": Path(full).is_junction() if hasattr(Path, "is_junction") else False,
        "st": st, "error": err,
        "pe_signed": None,
        "zone": None, "ads": None,
    }
    if rec["is_symlink"]:
        try:
            rec["symlink_target"] = os.readlink(full)
        except OSError:
            pass
    if err:
        return rec
    if args.signature:
        rec["pe_signed"] = pe_has_signature(full)
    return rec


def _enrich_windows(rec: dict) -> None:
    p = str(rec["path"])
    rec["win_attrs"] = _win_attributes(p)
    rec["change_time"] = _win_change_time(p)
    rec["ads"] = _win_streams(p)
    if rec["ads"] and any(a.lower() == "zone.identifier" for a in rec["ads"]):
        rec["zone"] = _win_motw(p)


def build_tree(root: Path, args):
    """Walk once. Returns nested dict: {path, rel, dirs:[sub], files:[record],
    interest: set of levels in subtree, error}."""
    root = root.resolve()

    def rec(directory: Path, rel: str, depth: int) -> dict:
        node = {"path": directory, "rel": rel, "depth": depth,
                "dirs": [], "files": [], "error": "", "sys_skipped": 0}
        if args.max_depth is not None and depth >= args.max_depth:
            return node
        try:
            entries = list(os.scandir(directory))
        except OSError as exc:
            node["error"] = exc.strerror or str(exc)
            return node

        for e in entries:
            full = Path(e.path)
            child_rel = f"{rel}/{e.name}" if rel else e.name
            try:
                st = e.stat(follow_symlinks=False)
            except OSError as exc:
                node["files"].append(build_file_record(
                    full, child_rel, depth + 1, args, st=None,
                    err=exc.strerror or str(exc)))
                continue

            is_dir = e.is_dir(follow_symlinks=False)
            is_link = e.is_symlink()
            if hasattr(Path, "is_junction") and not is_link:
                try:
                    is_link = full.is_junction()
                except OSError:
                    pass

            if is_dir and not is_link:
                if not args.include_system and e.name.lower() in SYSTEM_DIRS:
                    node["sys_skipped"] += 1
                    continue
                node["dirs"].append(rec(full, child_rel, depth + 1))
            else:
                frec = build_file_record(full, child_rel, depth + 1, args, st=st)
                if os.name == "nt":
                    _enrich_windows(frec)
                node["files"].append(frec)

        node["dirs"].sort(key=lambda d: d["path"].name.lower())
        node["files"].sort(key=lambda r: (LEVEL_RANK[r["level"]], r["name"].lower()))
        return node

    return rec(root, "", 0)


def annotate(node: dict, now: float | None = None,
             cats: set | None = None) -> None:
    """Post-order: subtree interest levels, machine-file counts, level counts,
    the red team score per record, and category selection state.
    cats is the operator's category selection from --only-cats; None = all."""
    if now is None:
        now = time.time()
    levels = {r["level"] for r in node["files"]}
    counts = Counter(r["level"] for r in node["files"])
    sel = set()
    node["machine_count"] = counts["LOW"]
    node["file_count"] = len(node["files"])
    node["sys_skipped_total"] = node["sys_skipped"]
    for r in node["files"]:
        r["score"], r["score_parts"] = score_record(r, now)
        r["selected"] = cats is None or r["category"] in cats
        sel.add("sel" if r["selected"] else "unsel")
    for d in node["dirs"]:
        annotate(d, now, cats)
        levels |= d["subtree_levels"]
        counts.update(d["level_counts"])
        sel |= d["subtree_sel"]
        node["machine_count"] += d["machine_count"]
        node["file_count"] += d["file_count"]
        node["sys_skipped_total"] += d["sys_skipped_total"]
    node["subtree_levels"] = levels
    node["level_counts"] = counts
    node["subtree_sel"] = sel


# ---------------------------------------------------------------------------
# Flattening (CSV / JSONL)
# ---------------------------------------------------------------------------

def flatten(rec: dict, args) -> dict:
    st = rec["st"]
    size = size_on_disk = None
    mtime = atime = ctime = birth = change_t = mtime_epoch = age = None
    mode = owner = anomaly = ""
    writable = writable_me = ""
    file_id = nlink = None
    attrs = []
    if st is not None:
        size = st.st_size
        size_on_disk = getattr(st, "st_blocks", None)
        size_on_disk = size_on_disk * 512 if size_on_disk is not None else None
        mtime, atime, ctime = st.st_mtime, st.st_atime, st.st_ctime
        birth = getattr(st, "st_btime", None)
        change_t = rec.get("change_time")
        mtime_epoch = int(mtime) if mtime else None
        age = round((datetime.now().timestamp() - mtime) / 86400, 2) if mtime else None
        mode = stat.filemode(st.st_mode)
        if pwd is not None:
            try:
                owner = pwd.getpwuid(st.st_uid).pw_name
            except KeyError:
                owner = str(st.st_uid)
        wb = _writable_by(st)
        writable = ";".join(sorted(wb))
        try:
            writable_me = os.access(rec["path"], os.W_OK, follow_symlinks=False)
        except OSError:
            writable_me = None
        file_id, nlink = st.st_ino, st.st_nlink
        if rec["name"].startswith("."):
            attrs.append("hidden")
        if not (st.st_mode & stat.S_IWUSR):
            attrs.append("readonly")
    attrs += [f"ntfs:{k}" for k, v in rec.get("win_attrs", {}).items() if v]

    now = datetime.now().timestamp()
    if mtime and mtime > now + 300:
        anomaly = "future-mtime"
    elif mtime and birth and mtime < birth - 300:
        anomaly = "mtime-before-birth"

    ext = rec["path"].suffix.lower()
    ftype = "symlink" if rec["is_symlink"] else (
        "junction" if rec["is_junction"] else "file")
    zone = rec["zone"] or {}
    row = {
        "path_relative": clean_str(rec["rel"]),
        "path_absolute": clean_str(str(rec["path"])),
        "name": clean_str(rec["name"]), "extension": ext, "file_type": ftype,
        "interest": rec["level"], "category": rec["category"],
        "size_bytes": size, "size_human": human_size(size),
        "size_on_disk": size_on_disk,
        "mtime": iso_time(mtime), "atime": iso_time(atime),
        "ctime": iso_time(ctime), "birth": iso_time(birth),
        "change_time": iso_time(change_t),
        "mtime_epoch": mtime_epoch, "mtime_age_days": age,
        "timestamp_anomaly": anomaly,
        "mode": mode, "owner": owner, "writable_by": writable,
        "writable_by_current_user": writable_me,
        "attributes": ";".join(attrs),
        "ads_count": len(rec["ads"]) if rec["ads"] is not None else None,
        "ads": ";".join(rec["ads"]) if rec["ads"] else None,
        "zone_id": zone.get("zone_id"), "host_url": zone.get("host_url"),
        "referrer_url": zone.get("referrer_url"),
        "file_id": file_id, "hardlink_count": nlink,
        "pe_signed": rec["pe_signed"],
        "symlink_target": rec["symlink_target"],
        "depth": rec["depth"], "error": rec["error"],
        "schema_version": SCHEMA_VERSION,
    }
    score = rec.get("score")
    if score is None:
        score, rec["score_parts"] = score_record(
            rec, datetime.now().timestamp())
        rec["score"] = score
    parts = rec["score_parts"]
    row["score"] = score
    row["score_path"] = parts["path"][0]
    row["score_extension"] = parts["extension"][0]
    row["score_recency"] = parts["recency"][0]
    row["score_name"] = parts["name"][0]
    row["score_size"] = parts["size"][0]
    row["score_detail"] = "; ".join(
        f"{k}={v[0]} ({v[1]})" for k, v in parts.items())
    if args.mark_recent is not None:
        row["recent"] = bool(mtime and age is not None
                             and 0 <= age <= args.mark_recent)
    return row


def iter_records(node: dict):
    yield from node["files"]
    for d in node["dirs"]:
        yield from iter_records(d)


# ---------------------------------------------------------------------------
# Renderers
# ---------------------------------------------------------------------------

TIER_COLOR = {0: "\033[1;31m", 1: "\033[1;31m", 2: "\033[1;33m",
              3: "\033[36m", 4: "\033[2m", 5: "\033[2m"}


def score_tier_index(score: int) -> int:
    """Position in SCORE_TIERS, 0 = hottest. Used for color and sort."""
    for i, (cut, _m, _l) in enumerate(SCORE_TIERS):
        if score >= cut:
            return i
    return len(SCORE_TIERS) - 1


def render_tree(node: dict, args, stats: Counter, prefix: str = "") -> None:
    cats = getattr(args, "_cats", None)
    entries = []
    for d in node["dirs"]:
        if cats is not None and d["subtree_sel"] == {"unsel"}:
            stats["dirs filtered"] += 1
            entries.append(("filtered", d))
        elif args.only_interesting and d["subtree_levels"] == {"LOW"}:
            stats["dirs collapsed"] += 1
            entries.append(("collapsed", d))
        else:
            entries.append(("dir", d))
    hot_first = sorted(node["files"],
                       key=lambda r: (-(r.get("score") or 0),
                                      r["name"].lower()))
    for r in hot_first:
        if r["level"] == "LOW" and not args.show_all:
            continue
        if cats is not None and not r["selected"] and not args.show_all:
            continue
        entries.append(("file", r))

    for i, (kind, item) in enumerate(entries):
        last = i == len(entries) - 1
        connector = "└── " if last else "├── "
        if kind == "collapsed":
            line = f"{prefix}{connector}{item['path'].name}/  (machine-only, {item['machine_count']} files)"
            if args.color:
                line = f"{COLOR['LOW']}{line}{COLOR['RESET']}"
            print(line)
        elif kind == "filtered":
            line = f"{prefix}{connector}{item['path'].name}/  (not in selected categories, {item['file_count']} files)"
            if args.color:
                line = f"{COLOR['LOW']}{line}{COLOR['RESET']}"
            print(line)
        elif kind == "dir":
            tag = "  [user area]" if item["path"].name.lower() in USER_AREA_DIRS else ""
            line = f"{prefix}{connector}{item['path'].name}/{tag}"
            if args.color:
                line = f"{COLOR['DIR']}{line}{COLOR['RESET']}"
            print(line)
            if item["error"]:
                print(f"{prefix}{'    ' if last else '│   '}└── <error: {item['error']}>")
                continue
            render_tree(item, args, stats,
                        prefix + ("    " if last else "│   "))
        else:
            level = item["level"]
            if item["is_symlink"] or item["is_junction"]:
                tgt = item["symlink_target"] or "?"
                line = f"{prefix}{connector}@ {item['name']} -> {tgt}" + \
                       ("  [broken]" if item["st"] is None and item["error"] == "" and
                        item["is_symlink"] else "")
                if args.color:
                    line = f"{COLOR['LINK']}{line}{COLOR['RESET']}"
                print(line)
                continue
            note = f"  <- {item['category']}" if level != "LOW" else ""
            score = item.get("score") or 0
            mark, _label = score_tier(score)
            line = f"{prefix}{connector}{mark} {score:>2} {item['name']}{note}"
            if args.color and level != "LOW":
                line = f"{TIER_COLOR[score_tier_index(score)]}{line}{COLOR['RESET']}"
            print(line)


def write_csv(path: Path, rows: list[dict]) -> None:
    cols = CSV_COLUMNS + (["recent"] if rows and "recent" in rows[0] else [])
    with path.open("w", newline="", encoding="utf-8-sig") as fh:
        writer = csv.DictWriter(fh, fieldnames=cols, extrasaction="ignore")
        writer.writeheader()
        for r in rows:
            clean = {k: ("" if v is None else v) for k, v in r.items()}
            writer.writerow(clean)


def write_jsonl(path: Path, rows: list[dict]) -> None:
    with path.open("w", encoding="utf-8") as fh:
        for r in rows:
            fh.write(json.dumps(r, ensure_ascii=False, default=str) + "\n")


# ---------------------------------------------------------------------------
# BLUF brief
#
# Text rules for this section (and for all comments in this file):
#   - Bottom line first. Details after.
#   - Use short sentences. Use simple words.
#   - Use the imperative for actions ("Open Downloads.").
#   - Do not use contractions. Do not use jargon.
# ---------------------------------------------------------------------------

BLUF_MAX_DIRS = 5     # max directories in the LOOK AT list
BLUF_MAX_FILES = 12   # max files in the REVIEW list
BIG_FILE_BYTES = 100 * 1024 * 1024


def _age_phrase(ts: float | None) -> str:
    """Short relative time phrase. Empty string if no time is known."""
    if ts is None:
        return ""
    secs = int(time.time() - ts)
    if secs < 0:
        return ""
    if secs < 3600:
        return f"Modified {max(secs // 60, 1)} minutes ago."
    if secs < 86400:
        return f"Modified {secs // 3600} hours ago."
    if secs < 86400 * 30:
        return f"Modified {secs // 86400} days ago."
    return f"Modified on {datetime.fromtimestamp(ts, timezone.utc).date().isoformat()}."


def _collect_dir_stats(recs):
    """Per directory: score and count of interesting files, by parent rel path."""
    dir_stats: dict[str, dict] = {}
    for rec in recs:
        if rec["level"] == "LOW":
            continue
        parent = str(Path(rec["rel"]).parent)
        if parent == ".":
            parent = ""
        slot = dir_stats.setdefault(parent, {"count": 0, "secret": 0,
                                             "high": 0, "medium": 0,
                                             "score": 0, "hot20": 0, "hot14": 0,
                                             "best": 0, "newest": None})
        slot["count"] += 1
        sc = rec.get("score") or 0
        slot["score"] += sc
        if sc > slot["best"]:
            slot["best"] = sc
        if sc >= 20:
            slot["hot20"] += 1
        if sc >= 14:
            slot["hot14"] += 1
        if rec["level"] == "HIGH":
            slot["high"] += 1
        else:
            slot["medium"] += 1
        if rec["category"] == "secrets/credentials":
            slot["secret"] += 1
        mtime = rec["st"].st_mtime if rec["st"] is not None else None
        if mtime is not None and (slot["newest"] is None or mtime > slot["newest"]):
            slot["newest"] = mtime
    return dir_stats


def _collect_skip_dirs(tree: dict):
    """Directories that hold only machine files."""
    skips = []

    def rec(node: dict) -> None:
        for d in node["dirs"]:
            if d["subtree_levels"] == {"LOW"}:
                skips.append((d["rel"], d["machine_count"]))
            else:
                rec(d)
    rec(tree)
    return skips


def render_bluf(tree: dict, args) -> str:
    """Build the BLUF brief. Returns plain text with markdown headers."""
    cats = getattr(args, "_cats", None)
    recs = list(iter_records(tree))
    if cats is not None:
        recs = [r for r in recs if r["selected"]]
    views = [flatten(r, args) for r in recs]
    interesting = [v for v in views if v["interest"] != "LOW"]
    dirs = _collect_dir_stats(recs)
    # bulk folders full of fresh files must not beat folders with secrets:
    # rank by grab-first count, then near-grab count, then best file, then total
    ranked_dirs = sorted(dirs.items(),
                         key=lambda kv: (kv[1]["hot20"], kv[1]["hot14"],
                                         kv[1]["best"], kv[1]["score"]),
                         reverse=True)
    secrets = [v for v in interesting if v["category"] == "secrets/credentials"]
    unsigned = [v for v in interesting if v.get("pe_signed") is False]
    macros = [v for v in interesting if v["category"] == "documents (macro)"]
    future = [v for v in interesting if v.get("timestamp_anomaly") == "future-mtime"]
    stomp = [v for v in interesting
             if v.get("timestamp_anomaly") == "mtime-before-birth"]
    big = [v for v in views
           if v.get("size_bytes") and v["size_bytes"] >= BIG_FILE_BYTES]
    recent = ([v for v in interesting if v.get("recent")]
              if args.mark_recent is not None else [])

    # 1. Bottom line
    lines = ["# BLUF BRIEF", ""]
    if cats is not None:
        lines.append(f"Filter active: {args.only_cats}. Only these categories are counted.")
        lines.append("")
    root_name = str(tree["path"])
    if not interesting:
        lines.append(f"Scan of {root_name} shows no user content.")
        lines.append("Skip this profile.")
    else:
        top = ranked_dirs[0]
        best = max(interesting, key=lambda v: v["score"])
        lines.append(f"Scan of {root_name} shows {len(interesting)} files for review.")
        lines.append(f"The directory '{top[0] or '.'}' has the highest total score ({top[1]['score']}).")
        lines.append(f"Top file: {best['path_relative']} (score {best['score']}/25).")
        warn_count = sum(1 for group in (secrets, unsigned, macros, future, stomp, big, recent)
                         if group)
        lines.append(f"{warn_count} warning {'type is' if warn_count == 1 else 'types are'} active.")
        if secrets:
            lines.append(f"Get the secrets first: {secrets[0]['path_relative']}.")
    lines.append("")
    lines.append("Score key: P = path, E = extension, R = recency, "
                 "N = name signal (keyword, capture prefix, pattern), "
                 "S = size. Max 25.")
    lines.append("")

    # 2. Look at these directories
    lines.append("## LOOK AT THESE DIRECTORIES")
    if not ranked_dirs:
        lines.append("No directory has user content.")
    for i, (rel, st) in enumerate(ranked_dirs[:BLUF_MAX_DIRS], 1):
        name = rel or "."
        notes = []
        if st["secret"]:
            notes.append(f"{st['secret']} secret file{'s' if st['secret'] != 1 else ''}")
        if st["high"] - st["secret"]:
            n = st["high"] - st["secret"]
            notes.append(f"{n} user file{'s' if n != 1 else ''}")
        if st["medium"]:
            notes.append(f"{st['medium']} acquired file{'s' if st['medium'] != 1 else ''}")
        tail = _age_phrase(st["newest"])
        hot = f"{st['hot20']} grab-first, " if st["hot20"] else ""
        lines.append(f"{i}. {name} - {hot}total score {st['score']}, "
                     f"{', '.join(notes)}. {tail}".rstrip())
    extra = len(ranked_dirs) - BLUF_MAX_DIRS
    if extra > 0:
        lines.append(f"{extra} more directories have user content.")
    lines.append("")

    # 3. Review these files, hottest first
    lines.append("## REVIEW THESE FILES")
    if not interesting:
        lines.append("No files need review.")
    hot = sorted(interesting,
                 key=lambda v: (-v["score"],
                                -(v.get("mtime_epoch") or 0)))
    for v in hot[:BLUF_MAX_FILES]:
        mark, _ = score_tier(v["score"])
        p = v["score_path"], v["score_extension"], v["score_recency"], \
            v["score_name"], v["score_size"]
        crit = f"P{p[0]} E{p[1]} R{p[2]} N{p[3]} S{p[4]}"
        lines.append(f"{mark} [{v['score']:>2}/25] {v['path_relative']} - {crit}")
    extra_f = len(interesting) - BLUF_MAX_FILES
    if extra_f > 0:
        if args.csv or args.jsonl:
            lines.append(f"{extra_f} more files are interesting. See the full export.")
        else:
            lines.append(f"{extra_f} more files are interesting. Run again with --csv to get the full list.")
    lines.append("")

    # 4. Warnings
    lines.append("## WARNINGS")
    warns = []
    grab_first = [v for v in interesting if v["score"] >= 20]
    if grab_first:
        names = ", ".join(v["path_relative"] for v in grab_first[:3])
        more = f" and {len(grab_first) - 3} more" if len(grab_first) > 3 else ""
        warns.append(f"{len(grab_first)} files score 20 or more: {names}{more}. Get them first.")
    if secrets:
        names = ", ".join(v["path_relative"] for v in secrets[:3])
        more = f" and {len(secrets) - 3} more" if len(secrets) > 3 else ""
        warns.append(f"The profile has {len(secrets)} secret files: {names}{more}. Get them first.")
    if unsigned:
        names = ", ".join(v["path_relative"] for v in unsigned[:3])
        more = f" and {len(unsigned) - 3} more" if len(unsigned) > 3 else ""
        noun = "program" if len(unsigned) == 1 else "programs"
        verb = "has" if len(unsigned) == 1 else "have"
        tail = "Check it." if len(unsigned) == 1 else "Check them."
        warns.append(f"{len(unsigned)} {noun} {verb} no signature data: {names}{more}. {tail}")
    if macros:
        names = ", ".join(v["path_relative"] for v in macros[:3])
        more = f" and {len(macros) - 3} more" if len(macros) > 3 else ""
        noun = "Office file" if len(macros) == 1 else "Office files"
        verb = "contains" if len(macros) == 1 else "contain"
        warns.append(f"{len(macros)} {noun} {verb} macros: {names}{more}. Open with care.")
    if future:
        noun = "file" if len(future) == 1 else "files"
        verb = "has" if len(future) == 1 else "have"
        warns.append(f"{len(future)} {noun} {verb} a modified time in the future. This can show time change.")
    if stomp:
        noun = "file" if len(stomp) == 1 else "files"
        verb = "has" if len(stomp) == 1 else "have"
        warns.append(f"{len(stomp)} {noun} {verb} a modified time before the creation time. This can show time change.")
    if recent:
        warns.append(f"{len(recent)} files changed in the last {args.mark_recent} days.")
    if big:
        names = ", ".join(v["path_relative"] for v in big[:2])
        warns.append(f"Large files ({len(big)}): {names}. Check size before copy.")
    lines.extend(warns if warns else ["No warnings."])
    lines.append("")

    # 5. Skip these directories
    lines.append("## SKIP THESE DIRECTORIES")
    skips = _collect_skip_dirs(tree)
    if skips:
        for rel, n in skips:
            lines.append(f"- {rel or '.'} - {n} machine file{'s' if n != 1 else ''} only. Skip it.")
    else:
        lines.append("No machine-only directories.")
    if tree.get("sys_skipped_total"):
        lines.append(f"- System directories skipped: {tree['sys_skipped_total']}. Do not change this without a reason.")
    lines.append("")

    # 6. Next actions
    lines.append("## NEXT ACTIONS")
    if interesting:
        lines.append("1. Open the first directory in the LOOK AT list.")
        lines.append("2. Pull every file with a score of 20 or more.")
        lines.append("3. Work down the REVIEW list. Higher score means higher value.")
        lines.append("4. Read each warning. Check each warning item.")
        if args.csv:
            lines.append(f"5. Open {args.csv} for the full file list.")
        elif args.jsonl:
            lines.append(f"5. Open {args.jsonl} for the full file list.")
    else:
        lines.append("1. Skip this profile.")
        lines.append("2. Scan the next profile.")
    lines.append("")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main(argv=None) -> int:
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("root", type=Path, help="directory to scan")
    ap.add_argument("--max-depth", type=int, default=None,
                    help="limit recursion depth")
    ap.add_argument("--show-all", action="store_true",
                    help="also print LOW-interest (machine) files")
    ap.add_argument("--include-system", action="store_true",
                    help="descend into AppData, .git, node_modules, etc.")
    ap.add_argument("--only-interesting", action="store_true",
                    help="collapse subtrees that contain no HIGH/MEDIUM files")
    ap.add_argument("--color", dest="color", action="store_true", default=None,
                    help="ANSI-color output (default: auto)")
    ap.add_argument("--no-color", dest="color", action="store_false",
                    help="disable color")
    ap.add_argument("--quiet", action="store_true",
                    help="suppress tree output (use with --csv/--jsonl)")
    ap.add_argument("--csv", type=Path, default=None,
                    help="write flat CSV export (one row per file)")
    ap.add_argument("--jsonl", type=Path, default=None,
                    help="write nested JSON Lines export")
    ap.add_argument("--bluf", default=None,
                    help="write a short BLUF brief to this path; use '-' for stdout")
    ap.add_argument("--signature", action="store_true",
                    help="PE Authenticode presence check (not validity)")
    ap.add_argument("--only-cats", default=None, metavar="LIST",
                    help="show only these category groups or categories, "
                         "comma separated. Groups: creds, media, docs, code, "
                         "db, acquired, forensic, noise. A fine category "
                         "name like 'capture files' also works.")
    ap.add_argument("--mark-recent", type=int, default=None, metavar="DAYS",
                    help="flag files modified within the last N days")
    args = ap.parse_args(argv)

    if not args.root.is_dir():
        sys.exit(f"error: not a directory: {args.root}")
    if args.color is None:
        args.color = sys.stdout.isatty()

    # forensic images are full of undecodable names; never crash a consumer
    try:
        sys.stdout.reconfigure(errors="backslashreplace")
    except (AttributeError, ValueError):
        pass

    tree = build_tree(args.root, args)
    cats = None
    if args.only_cats:
        try:
            cats = resolve_categories([args.only_cats])
        except ValueError as exc:
            sys.exit(f"error: {exc}")
    annotate(tree, cats=cats)
    args._cats = cats

    if args.bluf:
        brief = render_bluf(tree, args)
        if args.bluf == "-":
            print(brief)
        else:
            Path(args.bluf).write_text(brief, encoding="utf-8")

    stats: Counter = Counter()
    try:
        if not args.quiet:
            print(f"{tree['path']}/")
            render_tree(tree, args, stats)
    except BrokenPipeError:
        # downstream pager closed; exit cleanly instead of a traceback
        devnull = os.open(os.devnull, os.O_WRONLY)
        os.dup2(devnull, sys.stdout.fileno())
        return 0

    if args.csv or args.jsonl:
        recs = list(iter_records(tree))
        cats = getattr(args, "_cats", None)
        if cats is not None:
            recs = [r for r in recs if r["selected"]]
        rows = [flatten(r, args) for r in recs]
        if args.csv:
            write_csv(args.csv, rows)
        if args.jsonl:
            write_jsonl(args.jsonl, rows)

    if not args.quiet:
        lc = tree["level_counts"]
        cats = getattr(args, "_cats", None)
        if cats is not None:
            print(f"\n--- summary (filtered: {args.only_cats}) ---")
        else:
            print("\n--- summary ---")
        print(f"HIGH   * (user-generated): {lc['HIGH']}")
        print(f"MEDIUM . (user-acquired):  {lc['MEDIUM']}")
        print(f"LOW      (machine/noise):  {lc['LOW']}")
        if stats["dirs collapsed"]:
            print(f"dirs collapsed (machine-only): {stats['dirs collapsed']}")
        if stats["dirs filtered"]:
            print(f"dirs filtered (not in selected categories): {stats['dirs filtered']}")
        if tree["error"]:
            print(f"root error: {tree['error']}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
