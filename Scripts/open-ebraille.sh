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

echo "unpacked to: $dest"
open "$dest/index.html"
