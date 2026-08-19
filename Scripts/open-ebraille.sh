#!/bin/bash
# Unpack an eBraille file and open it in the default browser.
#
# An eBraille publication is a website in a ZIP: index.html is its entry point,
# and the spec requires it to be readable this way. Safari and VoiceOver render
# the braille characters directly, and they route to a connected braille
# display like any other text on the page.
#
# Usage:  Scripts/open-ebraille.sh FILE.ebrl

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: $(basename "$0") FILE.ebrl" >&2
  exit 64
fi

file="$1"
if [ ! -f "$file" ]; then
  echo "no such file: $file" >&2
  exit 66
fi

name="$(basename "${file%.*}")"
dest="${TMPDIR:-/tmp}/ebraille/$name"

rm -rf "$dest"
mkdir -p "$dest"
unzip -q "$file" -d "$dest"

if [ ! -f "$dest/index.html" ]; then
  echo "warning: no index.html in the publication root" >&2
  echo "the spec requires one; opening the folder instead" >&2
  open "$dest"
  exit 0
fi

# index.html is the navigation document: a bare list of links, with no
# stylesheet, because its job is to get you into the publication. The formatted
# braille is in the spine documents. Open the first of those, and print the
# entry page as the alternative rather than making it the default.
first_content=""
if [ -f "$dest/package.opf" ]; then
  # The first itemref in the spine, resolved to its manifest href.
  first_content=$(python3 - "$dest/package.opf" <<'PYTHON'
import sys
from xml.etree import ElementTree as ET

OPF = "{http://www.idpf.org/2007/opf}"
try:
    root = ET.parse(sys.argv[1]).getroot()
except ET.ParseError:
    sys.exit(0)

hrefs = {
    item.get("id"): item.get("href")
    for item in root.findall(f".//{OPF}item")
}
for ref in root.findall(f".//{OPF}itemref"):
    href = hrefs.get(ref.get("idref"))
    if href:
        print(href)
        break
PYTHON
  )
fi

echo "unpacked to: $dest"

if [ -n "$first_content" ] && [ -f "$dest/$first_content" ]; then
  echo "opening content:    $first_content"
  echo "table of contents:  index.html"
  open "$dest/$first_content"
else
  echo "no spine content found; opening the table of contents"
  open "$dest/index.html"
fi
