#!/usr/bin/env python3
"""Split pages off a PDF into a separate file (last 2 pages by default).

Usage:
    python split_last_2_pages.py input.pdf
    python split_last_2_pages.py input.pdf -o last2.pdf
    python split_last_2_pages.py input.pdf --first          # split the FIRST N pages instead
    python split_last_2_pages.py input.pdf -n 3             # split N pages
    python split_last_2_pages.py input.pdf --keep-rest      # also save the remaining pages

By default, creates "<name>_last2.pdf" next to the input file
(or "<name>_first2.pdf" when --first is used).
"""

import argparse
import sys
from pathlib import Path

from pypdf import PdfReader, PdfWriter


def split_pages(input_path: str, output_path: str | None = None, n: int = 2,
                first: bool = False, keep_rest: bool = False) -> tuple[Path, Path | None]:
    """Split off N pages from the end (default) or the start (--first) of a PDF."""
    input_path = Path(input_path)
    if not input_path.is_file():
        raise FileNotFoundError(f"Input file not found: {input_path}")

    reader = PdfReader(str(input_path))
    total = len(reader.pages)
    if total <= n:
        side = "first" if first else "last"
        raise ValueError(
            f"'{input_path.name}' has only {total} page(s); "
            f"need more than {n} to split off the {side} {n}."
        )

    if first:
        selected, rest = reader.pages[:n], reader.pages[n:]
        default_out = f"{input_path.stem}_first{n}.pdf"
        rest_name = f"{input_path.stem}_last{total - n}.pdf"
    else:
        selected, rest = reader.pages[total - n:], reader.pages[:total - n]
        default_out = f"{input_path.stem}_last{n}.pdf"
        rest_name = f"{input_path.stem}_first{total - n}.pdf"

    output_path = Path(output_path) if output_path else input_path.with_name(default_out)

    # Selected pages -> separate PDF
    writer = PdfWriter()
    for page in selected:
        writer.add_page(page)
    with open(output_path, "wb") as f:
        writer.write(f)

    # Optionally save the remaining pages too
    rest_path = None
    if keep_rest:
        rest_writer = PdfWriter()
        for page in rest:
            rest_writer.add_page(page)
        rest_path = input_path.with_name(rest_name)
        with open(rest_path, "wb") as f:
            rest_writer.write(f)

    return output_path, rest_path


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Split N pages off a PDF into a separate file "
                    "(last 2 pages by default; use --first for the first pages)."
    )
    parser.add_argument("input", help="Path to the source PDF")
    parser.add_argument("-o", "--output", help="Output path for the split-off pages PDF")
    parser.add_argument("-n", "--num-pages", type=int, default=2,
                        help="Number of pages to split off (default: 2)")
    parser.add_argument("--first", action="store_true",
                        help="Split the FIRST N pages instead of the last N")
    parser.add_argument("--keep-rest", action="store_true",
                        help="Also save the remaining pages as a separate PDF")
    args = parser.parse_args()

    if args.num_pages < 1:
        parser.error("--num-pages must be at least 1")

    try:
        out, rest = split_pages(args.input, args.output, n=args.num_pages,
                                first=args.first, keep_rest=args.keep_rest)
    except (FileNotFoundError, ValueError) as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    side = "first" if args.first else "last"
    print(f"Saved {side} {args.num_pages} page(s) -> {out}")
    if rest:
        print(f"Saved remaining pages        -> {rest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
