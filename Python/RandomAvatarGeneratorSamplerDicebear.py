#!/usr/bin/env python3
"""
dicebear_sampler.py — fetch N random-seed avatars for every DiceBear style
and assemble them into a labeled contact-sheet PNG.

Usage:
    python3 dicebear_sampler.py                 # 4 samples per style -> dicebear-sampler.png
    python3 dicebear_sampler.py -n 8 -o out.png # 8 samples per style
    python3 dicebear_sampler.py --seed 42       # reproducible "random" seeds
    python3 dicebear_sampler.py --styles-json other.json  # use a custom style list

Requires: requests, pillow   (pip install requests pillow)

The full DiceBear 10.x style list is embedded below (61 styles, from
@dicebear/styles v10.6.0). Pass --styles-json to override it with your own
JSON of the same shape: {"categories": {"<group>": ["style", ...]}}.


requirements.txt:

requests>=2.31
Pillow>=10.0

"""

import argparse
import io
import json
import random
import sys
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path

import requests
from PIL import Image, ImageDraw, ImageFont

API = "https://api.dicebear.com/10.x/{style}/png?seed={seed}&size={size}"
RETRIES = 3
TIMEOUT = 30

# Embedded DiceBear 10.x styles (@dicebear/styles v10.6.0, 61 styles).
# Override with --styles-json if you want a different list.
DEFAULT_STYLES = {
    "human": [
        "micah", "lorelei", "lorelei-neutral", "avataaars", "avataaars-neutral",
        "open-peeps", "personas", "notionists", "notionists-neutral",
        "adventurer", "adventurer-neutral", "croodles", "croodles-neutral",
        "big-smile", "big-ears", "big-ears-neutral", "miniavs", "thumbs",
        "toon-head", "dylan", "pixel-art", "pixel-art-neutral", "cameo",
        "clay", "gaze", "line-face", "moods", "initial-face",
    ],
    "bots": [
        "bottts", "bottts-neutral", "pixelbot", "voxel-bot",
    ],
    "creatures": [
        "critters", "sprouts",
    ],
    "emoji": [
        "fun-emoji",
    ],
    "abstract": [
        "identicon", "initials", "icons", "glyphs", "shapes", "shape-grid",
        "rings", "marbles", "planets", "squircles", "blobs", "loops", "waves",
        "stripes", "weave", "patchwork", "triangles", "stack", "slice",
        "glass", "shadows", "disco", "cutouts", "constellation", "landscape",
        "voxel-art",
    ],
}


def load_styles(styles_json: Path | None):
    """Return (rows, url_pattern). rows = [(category, style), ...].

    Uses the embedded DEFAULT_STYLES unless a JSON path is given.
    """
    if styles_json is None:
        data = {"categories": DEFAULT_STYLES, "urlPattern": API}
    else:
        data = json.loads(Path(styles_json).read_text())
    rows = []
    for cat, styles in data["categories"].items():
        for s in styles:
            rows.append((cat, s))
    return rows, data.get("urlPattern", API)


def fetch_one(style: str, seed: str, size: int):
    """Download one avatar PNG; returns (style, seed, bytes|None)."""
    url = API.format(style=style, seed=seed, size=size)
    for attempt in range(RETRIES):
        try:
            r = requests.get(url, timeout=TIMEOUT)
            r.raise_for_status()
            return style, seed, r.content
        except requests.RequestException:
            if attempt == RETRIES - 1:
                return style, seed, None
    return style, seed, None


def get_font(size: int):
    for name in ("DejaVuSans.ttf", "DejaVu Sans"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def build_sheet(results, rows, n, avatar_size, label_w, out_path):
    cell_pad = 10
    caption_h = 22
    cell = avatar_size + cell_pad * 2
    row_h = max(cell + caption_h, 56)
    head_h = 64
    W = label_w + 24 + n * (cell + 10) + 14
    H = head_h + len(rows) * (row_h + 8) + 16

    sheet = Image.new("RGB", (W, H), "#eceef2")
    draw = ImageDraw.Draw(sheet)
    f_title, f_label, f_cap = get_font(20), get_font(14), get_font(11)

    title = f"DiceBear sampler — {len(rows)} styles × {n} random UUID seeds"
    draw.text((24, 14), title, font=f_title, fill="#1d2129")
    draw.text((24, 42), f"generated {datetime.now(timezone.utc):%Y-%m-%d %H:%M UTC} · api.dicebear.com/10.x",
              font=get_font(12), fill="#6b7280")

    y = head_h
    for cat, style in rows:
        key = (cat, style)
        draw.rounded_rectangle([10, y, W - 10, y + row_h], radius=10, fill="#ffffff", outline="#e2e5ea")
        draw.text((24, y + row_h // 2 - 9), style, font=f_label, fill="#1d2129")
        draw.text((24, y + row_h // 2 + 9), cat, font=f_cap, fill="#8a919c")

        for i in range(n):
            seed, blob = results.get((key, i), (None, None))
            x = label_w + 24 + i * (cell + 10)
            cy = y + (row_h - caption_h - cell) // 2
            draw.rounded_rectangle([x, cy, x + cell, cy + cell], radius=8,
                                   fill="#fafbfc", outline="#edf0f3")
            if blob:
                av = Image.open(io.BytesIO(blob)).convert("RGBA")
                av.thumbnail((avatar_size, avatar_size))
                sheet.paste(av, (x + (cell - av.width) // 2, cy + (cell - av.height) // 2), av)
            else:
                draw.text((x + 12, cy + cell // 2 - 6), "fetch error", font=f_cap, fill="#c0392b")
            cap = seed[:8] if seed else "--------"
            tw = draw.textlength(cap, font=f_cap)
            draw.text((x + (cell - tw) // 2, y + row_h - caption_h), cap, font=f_cap, fill="#8a919c")
        y += row_h + 8

    sheet.save(out_path)
    return sheet.size


def main():
    ap = argparse.ArgumentParser(description="DiceBear random-seed sampler sheet")
    ap.add_argument("-n", "--per-style", type=int, default=4, help="avatars per style (default 4)")
    ap.add_argument("-o", "--out", default="dicebear-sampler.png", help="output PNG path")
    ap.add_argument("--size", type=int, default=160, help="avatar pixel size (default 160)")
    ap.add_argument("--styles-json", default=None,
                    help="optional JSON style list; defaults to the built-in 61-style list")
    ap.add_argument("--seed", type=int, default=None, help="master seed for reproducible UUIDs")
    ap.add_argument("--workers", type=int, default=8, help="parallel downloads (default 8)")
    args = ap.parse_args()

    rows, _ = load_styles(args.styles_json)
    rng = random.Random(args.seed) if args.seed is not None else random.Random()

    jobs = []
    for key in rows:
        for i in range(args.per_style):
            # deterministic UUIDs when --seed is given
            seed = str(uuid.UUID(int=rng.getrandbits(128))) if args.seed is not None else str(uuid.uuid4())
            jobs.append((key, i, seed))
    # re-shuffle job order so a slow style doesn't stall the tail
    rng.shuffle(jobs)

    results, done = {}, 0
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futs = {ex.submit(fetch_one, key[1], seed, args.size): (key, i, seed)
                for key, i, seed in jobs}
        for fut in as_completed(futs):
            key, i, seed = futs[fut]
            _, _, blob = fut.result()
            results[(key, i)] = (seed, blob)
            done += 1
            if done % 50 == 0 or done == len(jobs):
                print(f"{done}/{len(jobs)} fetched", flush=True)

    size = build_sheet(results, rows, args.per_style, args.size, 210, args.out)
    errors = sum(1 for v in results.values() if v[1] is None)
    print(f"saved {args.out} ({size[0]}x{size[1]}), {errors} failed avatar(s)")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
