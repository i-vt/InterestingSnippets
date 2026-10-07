#!/usr/bin/env python3
"""
Download every episode of the podcast.

How it works
------------
1. Fetches the official RSS feed (https://feeds.megaphone.fm/bingobongolongodongo)
   which lists every episode with a direct .mp3 enclosure URL.
2. Saves a manifest (episodes.json) of all episodes found.
3. Downloads each .mp3 with curl through your proxy, with:
     - resume support        (interrupted downloads pick up where they left off)
     - automatic retries     (with backoff)
     - skip-if-complete      (compares local size to the size in the feed)
     - safe file names       ("180 - Conti.mp3")
     - polite delay between episodes

Usage
-----
    python3 download_episodes.py                     # download everything
    python3 download_episodes.py --limit 3           # first 3 episodes only (test run)
    python3 download_episodes.py --episodes 180 179  # specific episode numbers
    python3 download_episodes.py --workers 3         # 3 parallel downloads
    python3 download_episodes.py --out /path/to/dir  # custom output folder
    python3 download_episodes.py --no-proxy          # bypass the proxy
    python3 download_episodes.py --manifest-only     # just write episodes.json

Re-running the script is safe: finished episodes are skipped,
partial ones are resumed.
"""

import argparse
import json
import re
import subprocess
import sys
import time
import unicodedata
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

FEED_URL = "https://feeds.megaphone.fm/bingobongolongodongo"

# Proxy (from your message). Override with --proxy or the HTTPS_PROXY env var.
DEFAULT_PROXY = "http://masfasdfasfd:24asdfafdf@proxy.com:12341"

USER_AGENT = ("Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:147.0) "
              "Gecko/20100101 Firefox/147.0")

ITUNES_NS = "{http://www.itunes.com/dtds/podcast-1.0.dtd}"


def slugify(text: str, max_len: int = 80) -> str:
    """Make a filesystem-safe version of an episode title."""
    text = unicodedata.normalize("NFKD", text)
    text = re.sub(r"[\\/:*?\"<>|]", "", text)      # illegal filename chars
    text = re.sub(r"\s+", " ", text).strip()
    return text[:max_len].rstrip(" .")


def fetch_feed(proxy: str | None) -> bytes:
    print(f"Fetching RSS feed: {FEED_URL}")
    req = urllib.request.Request(FEED_URL, headers={"User-Agent": USER_AGENT})
    handlers = []
    if proxy:
        handlers.append(urllib.request.ProxyHandler({"http": proxy, "https": proxy}))
    opener = urllib.request.build_opener(*handlers)
    with opener.open(req, timeout=60) as resp:
        data = resp.read()
    print(f"  feed size: {len(data)/1024:.0f} KiB")
    return data


def parse_feed(xml_bytes: bytes) -> list[dict]:
    """Extract one dict per episode from the RSS XML."""
    root = ET.fromstring(xml_bytes)
    episodes = []
    for item in root.iter("item"):
        title = (item.findtext("title") or "").strip()
        enc = item.find("enclosure")
        if enc is None or not enc.get("url"):
            continue
        url = enc.get("url")
        length = int(enc.get("length") or 0)

        # Episode number: prefer <itunes:episode>, fall back to "NNN:" in the title.
        ep_num = item.findtext(f"{ITUNES_NS}episode")
        if not ep_num:
            m = re.match(r"\s*(\d+)\s*[:：]", title)
            ep_num = m.group(1) if m else None

        # Clean display title: strip a leading "180: " prefix since we add our own.
        clean_title = re.sub(r"^\s*\d+\s*[:：]\s*", "", title)

        if ep_num:
            filename = f"{int(ep_num):03d} - {slugify(clean_title)}.mp3"
        else:
            filename = f"{slugify(title)}.mp3"

        episodes.append({
            "episode": int(ep_num) if ep_num else None,
            "title": title,
            "url": url,
            "bytes": length,
            "published": (item.findtext("pubDate") or "").strip(),
            "filename": filename,
        })

    # Newest first in the feed -> sort by episode number (None/trailers last, keep order).
    episodes.sort(key=lambda e: (e["episode"] is None, e["episode"] or 0))
    return episodes


def human(n: float) -> str:
    for unit in ("B", "KiB", "MiB", "GiB"):
        if n < 1024 or unit == "GiB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.0f} B"


def is_complete(path: Path, expected: int) -> bool:
    """True if the local file looks complete.

    NOTE: the RSS feed's declared length often differs from the bytes the CDN
    actually serves (PRX Dovetail stitches ads dynamically), so an exact byte
    match would wrongly reject good downloads. Allow +/-1% tolerance.
    """
    if not path.exists():
        return False
    size = path.stat().st_size
    if size == 0:
        return False
    if expected <= 0:
        return True
    return abs(size - expected) / expected < 0.01


def download_one(ep: dict, outdir: Path, proxy: str | None,
                 retries: int = 5, delay: float = 2.0) -> bool:
    dest = outdir / ep["filename"]
    expected = ep["bytes"]

    if is_complete(dest, expected):
        print(f"  SKIP  {ep['filename']} (already complete, {human(expected)})")
        return True

    cmd = [
        "curl", "-sS", "-f", "-L",
        "-C", "-",                       # resume partial file
        "--connect-timeout", "30",
        "--max-time", "7200",            # up to 2h per episode (slow proxies)
        "-A", USER_AGENT,
        "-w", "\nHTTP_CODE:%{http_code}",
        "-o", str(dest),
    ]
    if proxy:
        cmd += ["-x", proxy]
    cmd.append(ep["url"])

    have = dest.stat().st_size if dest.exists() else 0
    tag = "resuming" if have else "fetching"
    print(f"  GET   {ep['filename']}  ({tag}, {human(have)} -> ~{human(expected)})")

    for attempt in range(1, retries + 1):
        result = subprocess.run(cmd, capture_output=True, text=True)
        http_code = ""
        m = re.search(r"HTTP_CODE:(\d+)", result.stdout or "")
        if m:
            http_code = m.group(1)

        # exit 0 = transfer completed successfully (sizes vary, see is_complete).
        # HTTP 416 = server rejected our resume range -> file is already whole.
        if result.returncode == 0 or http_code == "416":
            if dest.exists() and dest.stat().st_size > 0:
                print(f"  OK    {ep['filename']}  ({human(dest.stat().st_size)})")
                time.sleep(delay)        # be polite to the CDN
                return True

        err = (result.stderr or "").strip().splitlines()
        why = err[-1] if err else f"exit {result.returncode} (HTTP {http_code or '?'})"
        print(f"  RETRY {attempt}/{retries}  {ep['filename']}: {why}")
        time.sleep(5 * attempt)

    print(f"  FAIL  {ep['filename']} (left partial file for next run)")
    return False


def main() -> int:
    ap = argparse.ArgumentParser(description="Download all Darknet Diaries episodes.")
    ap.add_argument("--out", default=str(Path(__file__).resolve().parent / "episodes"),
                    help="output folder for mp3 files (default: ./episodes next to script)")
    ap.add_argument("--proxy", default=None,
                    help="proxy URL (default: built-in iproyal proxy; env HTTPS_PROXY also honored)")
    ap.add_argument("--no-proxy", action="store_true", help="connect directly, no proxy")
    ap.add_argument("--limit", type=int, default=0, help="only download N episodes (test runs)")
    ap.add_argument("--episodes", type=int, nargs="*", default=None,
                    help="only these episode numbers, e.g. --episodes 180 179 1")
    ap.add_argument("--workers", type=int, default=1, help="parallel downloads (default 1)")
    ap.add_argument("--delay", type=float, default=2.0, help="pause between episodes, seconds")
    ap.add_argument("--manifest-only", action="store_true",
                    help="only fetch the feed and write episodes.json")
    args = ap.parse_args()

    if args.no_proxy:
        proxy = None
    else:
        import os
        proxy = args.proxy or os.environ.get("HTTPS_PROXY") or DEFAULT_PROXY
    print(f"Proxy: {'none (direct)' if not proxy else re.sub(r'://[^@]*@', '://***@', proxy)}")

    outdir = Path(args.out)
    outdir.mkdir(parents=True, exist_ok=True)

    feed = fetch_feed(proxy)
    episodes = parse_feed(feed)
    total_bytes = sum(e["bytes"] for e in episodes)
    print(f"Found {len(episodes)} episodes in feed, total {human(total_bytes)}")

    manifest_path = Path(args.out).parent / "episodes.json"
    manifest_path.write_text(json.dumps(episodes, indent=2, ensure_ascii=False))
    print(f"Manifest written: {manifest_path}")

    if args.manifest_only:
        return 0

    if args.episodes:
        wanted = set(args.episodes)
        episodes = [e for e in episodes if e["episode"] in wanted]
        missing = wanted - {e["episode"] for e in episodes}
        if missing:
            print(f"Warning: episode numbers not found in feed: {sorted(missing)}")
    if args.limit:
        episodes = episodes[: args.limit]

    if not episodes:
        print("Nothing to download.")
        return 0

    print(f"\nDownloading {len(episodes)} episode(s) -> {outdir}\n")

    failures = []
    if args.workers > 1:
        from concurrent.futures import ThreadPoolExecutor, as_completed
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            futs = {pool.submit(download_one, ep, outdir, proxy): ep for ep in episodes}
            for fut in as_completed(futs):
                if not fut.result():
                    failures.append(futs[fut]["filename"])
    else:
        for i, ep in enumerate(episodes, 1):
            print(f"[{i}/{len(episodes)}] {ep['title']}")
            if not download_one(ep, outdir, proxy, delay=args.delay):
                failures.append(ep["filename"])

    done = len(episodes) - len(failures)
    print(f"\nFinished: {done}/{len(episodes)} downloaded.")
    if failures:
        print("Failed (re-run the script to resume/retry):")
        for f in failures:
            print(f"  - {f}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
