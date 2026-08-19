#!/usr/bin/env python3
"""Show the cell layout of an eBraille file as plain text.

A braille display puts each block at a specific cell. That structure is the
whole point of a layout standard, and it is invisible both in a browser (which
renders ch as a character width) and in a back-translation (which throws the
positions away).

This resolves the stylesheet against the content and prints, for each block,
which cell it starts in and which cell its runover lines return to — plus the
English text, so you can check that the right content landed in the right
place.

Usage:  preview-ebraille-layout.py FILE.ebrl [--width 40] [--braille]
"""

import argparse
import re
import subprocess
import sys
import zipfile
from xml.etree import ElementTree as ET

OPF = "{http://www.idpf.org/2007/opf}"

# Blocks whose layout we report, in the order they can nest.
BLOCK_TAGS = ("h1", "h2", "h3", "h4", "h5", "h6", "p", "li", "blockquote", "pre")


def parse_css(css):
    """Cell offsets per selector: {tag: (start_cell, runover_cell)}."""
    rules = {}
    for match in re.finditer(r"([^{}]+)\{([^{}]*)\}", css):
        selectors = [s.strip() for s in match.group(1).split(",")]
        body = match.group(2)

        def cells(prop):
            found = re.search(rf"\b{prop}\s*:\s*(-?\d+(?:\.\d+)?)ch", body)
            return float(found.group(1)) if found else 0.0

        padding = cells("padding-left")
        indent = cells("text-indent")
        centered = re.search(r"text-align\s*:\s*center", body) is not None

        for selector in selectors:
            if not selector:
                continue
            rules[selector] = {
                "padding": padding,
                "indent": indent,
                "centered": centered,
            }
    return rules


def style_for(tag, rules, depth=0):
    """Resolve a tag's layout, accounting for nesting depth of lists."""
    style = None
    for selector, value in rules.items():
        parts = selector.split()
        if parts[-1] == tag:
            # Prefer a bare tag rule; nested rules are handled via depth.
            if style is None or len(parts) == 1:
                style = value
    if style is None:
        return None

    padding = style["padding"] + (2.0 * depth if tag == "li" else 0.0)
    start = padding + style["indent"]
    return {
        "start": start,
        "runover": padding,
        "centered": style["centered"],
    }


def back_translate(text, table):
    try:
        result = subprocess.run(
            ["lou_translate", "-b", f"unicode.dis,{table}"],
            input=text, capture_output=True, text=True, check=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return text
    return result.stdout.strip()


def blocks(xhtml):
    """Yield (tag, depth, text) for each layout block, in document order."""
    body = xhtml.split("<body>", 1)[-1]
    depth = 0
    for match in re.finditer(r"<(/?)(\w+)[^>]*>|([^<]+)", body):
        closing, tag, text = match.groups()
        if tag in ("ol", "ul"):
            depth += -1 if closing else 1
            depth = max(depth, 0)
        elif tag in BLOCK_TAGS and not closing:
            # Text of this block: everything up to its closing tag.
            rest = body[match.end():]
            end = rest.find(f"</{tag}>")
            inner = rest[:end] if end >= 0 else rest
            inner = re.sub(r"<[^>]+>", "", inner).strip()
            if inner:
                yield tag, max(depth - 1, 0), inner


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("file")
    parser.add_argument("--width", type=int, default=40,
                        help="cells per line to simulate (default 40)")
    parser.add_argument("--table", default="en-ueb-g2.ctb")
    parser.add_argument("--braille", action="store_true",
                        help="show braille rather than back-translated English")
    args = parser.parse_args()

    with zipfile.ZipFile(args.file) as archive:
        names = archive.namelist()
        opf = "package.opf" if "package.opf" in names else None
        if not opf:
            print("no package.opf found", file=sys.stderr)
            return 1

        root = ET.parse(archive.open(opf)).getroot()
        hrefs = {i.get("id"): i.get("href") for i in root.findall(f".//{OPF}item")}
        spine = [hrefs.get(r.get("idref")) for r in root.findall(f".//{OPF}itemref")]

        css = ""
        for item in root.findall(f".//{OPF}item"):
            if item.get("media-type") == "text/css":
                css += archive.open(item.get("href")).read().decode("utf-8")
        rules = parse_css(css)

        print(f"simulating a {args.width}-cell display\n")
        print("cells  block  text")
        print("-----  -----  " + "-" * (args.width))

        for href in spine:
            if not href or href not in names:
                continue
            xhtml = archive.open(href).read().decode("utf-8")

            for tag, depth, braille in blocks(xhtml):
                style = style_for(tag, rules, depth)
                if style is None:
                    continue
                text = braille if args.braille else back_translate(braille, args.table)

                start = int(style["start"])
                runover = int(style["runover"])

                if style["centered"]:
                    label = "centr"
                    pad = max((args.width - len(text)) // 2, 0)
                    lines = [" " * pad + text]
                else:
                    label = f"{start + 1}-{runover + 1}"
                    lines = []
                    remaining = text
                    first = True
                    while remaining:
                        margin = start if first else runover
                        room = max(args.width - margin, 10)
                        if len(remaining) <= room:
                            chunk, remaining = remaining, ""
                        else:
                            cut = remaining.rfind(" ", 0, room)
                            cut = cut if cut > 0 else room
                            chunk, remaining = remaining[:cut], remaining[cut:].lstrip()
                        lines.append(" " * margin + chunk)
                        first = False

                print(f"{label:>5}  {tag:>5}  {lines[0]}")
                for line in lines[1:]:
                    print(f"{'':>5}  {'':>5}  {line}")
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
