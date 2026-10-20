#!/usr/bin/env python3
"""
Export ALL videos from a YouTube channel tab to CSV:
    video name | views | when posted | full youtube link

Uses YouTube's internal "Innertube" browse API (the same one the website
uses for infinite scroll) - no API key, no login, no quota.

Requirements:
    pip install requests

Usage:
    python yt_channel_videos.py @BlackHatOfficialYT
    python yt_channel_videos.py UCJ6q9Ie29ajGqKApbLqfBOg -o blackhat.csv
    python yt_channel_videos.py UCJ6q9Ie29ajGqKApbLqfBOg --tab shorts
    python yt_channel_videos.py UCJ6q9Ie29ajGqKApbLqfBOg --proxy "http://user:pass@host:port"

About --proxy:
    Run WITHOUT a proxy if your machine can open youtube.com directly -
    that is the simplest and most reliable mode.

    Some proxies (e.g. certain residential plans) block youtube.com and
    youtubei.googleapis.com by SNI. In --proxy mode this script therefore
    tunnels the Innertube API through https://www.googleapis.com (which such
    filters usually allow) while sending the header
        Host: youtubei.googleapis.com
    Google's front end routes by the Host header, so the request still
    reaches the Innertube backend. If your proxy does NOT block YouTube,
    pass --proxy-direct to call youtubei.googleapis.com through it normally.

Notes:
    - "views" are the abbreviated counts YouTube shows on the channel page
      ("1.2M", "10K", ...). Exact counts require the official Data API key.
    - "when posted" is the relative age YouTube displays ("2mo ago").
    - Shorts are on a separate tab: use --tab shorts (or run twice).
"""

import argparse
import csv
import json
import random
import sys
import time

import requests

# Public key embedded in every youtube.com page (not a secret).
API_KEY = "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8"
CLIENT_VERSION = "2.20251016.01.00"

TAB_PARAMS = {
    "videos": "EgZ2aWRlb3PyBgQKAjoA",
    "shorts": "EgZzaG9ydHPyBgQKAjoA",
}

FRONTED_HOST = "https://www.googleapis.com"      # SNI / TCP target in proxy mode
REAL_HOST = "youtubei.googleapis.com"            # routed via Host header
DIRECT_HOST = "https://youtubei.googleapis.com"


# ---------------------------------------------------------------- transport

def make_session(proxy=None):
    s = requests.Session()
    if proxy:
        s.proxies = {"http": proxy, "https": proxy}
    s.headers.update({
        "Content-Type": "application/json",
        "X-YouTube-Client-Name": "1",
        "X-YouTube-Client-Version": CLIENT_VERSION,
        "User-Agent": "Mozilla/5.0",
        "Origin": "https://www.youtube.com",
    })
    return s


def innertube(session, endpoint, payload, proxy=None, proxy_direct=False):
    """POST to youtubei/v1/<endpoint>, with SNI-evasion fallback in proxy mode."""
    url = f"{DIRECT_HOST}/youtubei/v1/{endpoint}"
    headers = {}
    if proxy and not proxy_direct:
        url = f"{FRONTED_HOST}/youtubei/v1/{endpoint}"
        headers["Host"] = REAL_HOST
    params = {"key": API_KEY, "prettyPrint": "false"}

    last_err = None
    for attempt in range(6):
        try:
            r = session.post(url, params=params, headers=headers,
                             data=json.dumps(payload), timeout=60)
            if r.status_code == 200:
                return r.json()
            last_err = f"HTTP {r.status_code}: {r.text[:200]}"
            if r.status_code in (400, 401, 403, 404):
                break  # not retryable
        except requests.RequestException as e:
            last_err = str(e)[:200]
        time.sleep(min(2 ** attempt + random.random(), 20))
    raise RuntimeError(f"innertube {endpoint} failed: {last_err}")


def context():
    return {"client": {"clientName": "WEB", "clientVersion": CLIENT_VERSION,
                       "hl": "en", "gl": "US"}}


def resolve_handle(session, handle_or_url, proxy, proxy_direct):
    """@handle or channel URL -> UC... channel id."""
    target = handle_or_url
    if target.startswith("@"):
        target = "https://www.youtube.com/" + target
    d = innertube(session, "navigation/resolve_url",
                  {"context": context(), "url": target}, proxy, proxy_direct)
    return d["endpoint"]["browseEndpoint"]["browseId"]


# ------------------------------------------------------------------ parsing

def walk(o):
    if isinstance(o, dict):
        yield o
        for v in o.values():
            yield from walk(v)
    elif isinstance(o, list):
        for v in o:
            yield from walk(v)


def _meta_parts(lockup):
    rows = (lockup.get("metadata", {}).get("lockupMetadataViewModel", {})
            .get("metadata", {}).get("contentMetadataViewModel", {})
            .get("metadataRows", []))
    for row in rows:
        for part in row.get("metadataParts", []):
            yield part.get("text", {}).get("content", ""), part.get("accessibilityLabel", "")


def parse_lockup(lv):
    title = lv.get("metadata", {}).get("lockupMetadataViewModel", {}) \
             .get("title", {}).get("content", "")
    views = age = None
    for content, label in _meta_parts(lv):
        blob = f"{content} {label}"
        if "view" in blob and views is None:
            views = content.replace(" views", "").replace("No views", "0")
        elif ("ago" in blob or "Streamed" in blob or "Premiered" in blob) and age is None:
            age = content
    return lv.get("contentId"), title, views, age


def parse_video_renderer(vr):
    vid = vr.get("videoId")
    t = vr.get("title", {})
    title = "".join(r.get("text", "") for r in t.get("runs", [])) or t.get("simpleText", "")
    vct = vr.get("viewCountText", {})
    views = vct.get("simpleText") or "".join(r.get("text", "") for r in vct.get("runs", []))
    views = views.replace(" views", "") or None
    age = vr.get("publishedTimeText", {}).get("simpleText")
    return vid, title, views, age


def collect_videos(node, out):
    """Collect (videoId, title, views, age) from any renderer node."""
    if "richItemRenderer" in node:
        collect_videos(node["richItemRenderer"].get("content", {}), out)
    lv = node.get("lockupViewModel")
    if lv and lv.get("contentType") == "LOCKUP_CONTENT_TYPE_VIDEO":
        out.append(parse_lockup(lv))
    for key in ("videoRenderer", "gridVideoRenderer", "reelItemRenderer"):
        if key in node:
            out.append(parse_video_renderer(node[key]))


def continuation_token(renderer_contents):
    for c in renderer_contents:
        cir = c.get("continuationItemRenderer")
        if cir:
            return (cir.get("continuationEndpoint", {})
                    .get("continuationCommand", {}).get("token"))
    return None


def extract_page(d):
    """Return (videos, next_token) from either response shape."""
    # Shape A: continuation response (appendContinuationItemsAction)
    for node in walk(d):
        acia = node.get("appendContinuationItemsAction")
        if acia:
            items = acia.get("continuationItems", [])
            vids = []
            for c in items:
                collect_videos(c, vids)
            return vids, continuation_token(items)

    # Shape B: initial tab page -> pick the grid that actually holds videos
    best_vids, best_tok = [], None
    for node in walk(d):
        rg = node.get("richGridRenderer") or node.get("gridRenderer")
        if rg and "contents" in rg:
            vids = []
            for c in rg["contents"]:
                collect_videos(c, vids)
            if len(vids) > len(best_vids):
                best_vids = vids
                best_tok = continuation_token(rg["contents"])
    return best_vids, best_tok


# ---------------------------------------------------------------------- main

def scrape(channel, tab, proxy=None, proxy_direct=False, delay=(0.2, 0.8)):
    session = make_session(proxy)

    cid = channel
    if not (channel.startswith("UC") and len(channel) == 24):
        cid = resolve_handle(session, channel, proxy, proxy_direct)
        print(f"resolved {channel} -> {cid}")

    seen = {}
    payload = {"context": context(), "browseId": cid, "params": TAB_PARAMS[tab]}
    page = 0
    while payload and page < 1000:
        page += 1
        d = innertube(session, "browse", payload, proxy, proxy_direct)
        vids, token = extract_page(d)
        new = 0
        for vid, title, views, age in vids:
            if vid and vid not in seen:
                seen[vid] = (title, views, age)
                new += 1
        print(f"page {page:>3}: +{new:>2} new (total {len(seen)})", flush=True)
        if not token:
            break
        payload = {"context": context(), "browseId": cid, "continuation": token}
        time.sleep(random.uniform(*delay))
    return seen


def main():
    ap = argparse.ArgumentParser(description="Export all videos of a YouTube channel to CSV.")
    ap.add_argument("channel", help="channel id (UC...), @handle, or channel URL")
    ap.add_argument("-o", "--output", default="youtube_channel_videos.csv")
    ap.add_argument("--tab", choices=TAB_PARAMS, default="videos")
    ap.add_argument("--proxy", help='e.g. "http://user:pass@host:port"')
    ap.add_argument("--proxy-direct", action="store_true",
                    help="call youtubei.googleapis.com directly through the proxy "
                         "(use only if the proxy does not block YouTube)")
    args = ap.parse_args()

    try:
        seen = scrape(args.channel, args.tab, args.proxy, args.proxy_direct)
    except RuntimeError as e:
        sys.exit(f"error: {e}")

    with open(args.output, "w", newline="", encoding="utf-8-sig") as f:
        w = csv.writer(f)
        w.writerow(["video name", "views", "when posted", "full youtube link"])
        for vid, (title, views, age) in seen.items():
            w.writerow([title, views, age, f"https://www.youtube.com/watch?v={vid}"])
    print(f"done: {len(seen)} videos -> {args.output}")


if __name__ == "__main__":
    main()
