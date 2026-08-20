#!/usr/bin/env python3
"""Run local structural checks on a ghostWriter BRF export.

This verifies the byte repertoire, CRLF records, page geometry, and the list
failure that can put several bullet items on one physical line. It can also
back-translate the BRF for inspection when liblouis is installed. It is not an
official BANA certification or a substitute for reading the file on target
hardware.

Usage: validate-brf.py FILE.brf [--cells 40] [--lines 25] [--show]
"""

import argparse
import re
import subprocess
import sys


def back_translate(data, table):
    try:
        result = subprocess.run(
            ["lou_translate", "-b", f"en-us-brf.dis,{table}"],
            input=data.decode("ascii"),
            capture_output=True,
            text=True,
            check=True,
        )
    except (OSError, UnicodeDecodeError, subprocess.CalledProcessError):
        return None
    return result.stdout.rstrip()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("file")
    parser.add_argument("--cells", type=int, default=40)
    parser.add_argument("--lines", type=int, default=25)
    parser.add_argument("--table", default="en-ueb-g2.ctb")
    parser.add_argument("--show", action="store_true")
    args = parser.parse_args()

    problems = []
    notes = []
    if args.cells < 1 or args.lines < 1:
        parser.error("--cells and --lines must be positive")

    with open(args.file, "rb") as handle:
        data = handle.read()

    invalid = sorted({byte for byte in data if byte not in {10, 12, 13} and not 32 <= byte <= 126})
    if invalid:
        problems.append(f"bytes outside printable BRF ASCII: {invalid}")
    else:
        notes.append("all content uses printable BRF ASCII plus CRLF and form feed")

    if re.search(b"(?<!\r)\n|\r(?!\n)", data):
        problems.append("line endings contain lone CR or LF; BRF records must use CRLF")
    else:
        notes.append("line records use CRLF")

    if not data.endswith(b"\r\n"):
        problems.append("the final BRF record is not terminated by CRLF")

    pages = data.split(b"\x0c")
    if any(index > 0 and not page for index, page in enumerate(pages)):
        problems.append("empty page found after a form feed")

    physical_lines = 0
    bullet_lines = 0
    for page_number, page in enumerate(pages, start=1):
        if page_number < len(pages) and not page.endswith(b"\r\n"):
            problems.append(f"page {page_number} does not end with CRLF before its form feed")
        records = page.split(b"\r\n")
        if records and records[-1] == b"":
            records.pop()
        physical_lines += len(records)
        if len(records) > args.lines:
            problems.append(
                f"page {page_number} has {len(records)} lines; selected depth is {args.lines}"
            )
        for line_number, record in enumerate(records, start=1):
            if len(record) > args.cells:
                problems.append(
                    f"page {page_number}, line {line_number} has {len(record)} cells; "
                    f"selected width is {args.cells}"
                )
            if record.endswith(b" "):
                problems.append(f"page {page_number}, line {line_number} has trailing spaces")
            markers = record.count(b"_4 ")
            if markers:
                bullet_lines += 1
            if markers > 1:
                problems.append(
                    f"page {page_number}, line {line_number} contains {markers} bullet markers; "
                    "each list item must begin on its own physical line"
                )
            if record.lstrip().startswith(b"- "):
                problems.append(
                    f"page {page_number}, line {line_number} uses a print hyphen as a list marker"
                )

    notes.append(f"checked {len(pages)} page(s) and {physical_lines} physical line(s)")
    if bullet_lines:
        notes.append(f"found {bullet_lines} line(s) beginning or continuing with a UEB bullet marker")

    if args.show:
        translated = back_translate(data, args.table)
        if translated is None:
            problems.append("could not back-translate with lou_translate")
        else:
            print("\n--- back-translation ---")
            print(translated)

    print("\n=== checks passed ===")
    for note in notes:
        print(f"  ok    {note}")
    if problems:
        print("\n=== problems ===")
        for problem in problems:
            print(f"  FAIL  {problem}")
        print(f"\n{len(problems)} problem(s) found.")
        return 1

    print("\nNo problems found.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
