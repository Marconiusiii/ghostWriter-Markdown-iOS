#!/bin/bash
#
# Rebuilds liblouis.xcframework and refreshes the bundled English and Spanish
# braille tables.
#
# Only the LGPL library (liblouis/) and its gnulib support are built. The
# tools/ directory is GPL 3 and is deliberately never built, so that no GPL
# code reaches the shipped binary.
#
# Run from anywhere; artifacts land next to this script.

set -euo pipefail

VERSION="3.38.0"
MIN_IOS="17.0"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Fetching liblouis ${VERSION}..."
curl -sL -o "$WORK/liblouis.tar.gz" \
  "https://github.com/liblouis/liblouis/releases/download/v${VERSION}/liblouis-${VERSION}.tar.gz"
tar xzf "$WORK/liblouis.tar.gz" -C "$WORK"
SRC="$WORK/liblouis-${VERSION}"

# The release tarball ships a pre-generated configure, so automake is not
# required. --disable-ucs4 pins widechar to 16 bits, which is what lets the
# Swift bridge hand over String.utf16 without converting.
build_slice() {
  local sdk="$1" min_flag="$2" out="$3"
  local sysroot; sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"
  mkdir -p "$WORK/$out"
  (
    cd "$WORK/$out"
    "$SRC/configure" \
      --host=arm-apple-darwin \
      --prefix="$WORK/$out-install" \
      --enable-static --disable-shared --without-yaml --disable-ucs4 \
      CC="$(xcrun --sdk "$sdk" -f clang)" \
      CFLAGS="-arch arm64 -isysroot $sysroot $min_flag" > configure.log 2>&1
    # gnulib first: liblouis.la links against it.
    ( cd gnulib && make -j8 > build.log 2>&1 )
    ( cd liblouis && make -j8 > build.log 2>&1 )
  )
}

echo "Building device slice (arm64, iOS ${MIN_IOS})..."
build_slice iphoneos "-mios-version-min=${MIN_IOS}" build-device

echo "Building simulator slice (arm64)..."
build_slice iphonesimulator "-mios-simulator-version-min=${MIN_IOS}" build-sim

echo "Assembling xcframework..."
for slice in device sim; do
  mkdir -p "$WORK/xc-$slice/Headers"
  cp "$WORK/build-$slice/liblouis/.libs/liblouis.a" "$WORK/xc-$slice/"
  cp "$WORK/build-$slice/liblouis/liblouis.h" "$WORK/xc-$slice/Headers/"
done

rm -rf "$HERE/liblouis.xcframework"
xcodebuild -create-xcframework \
  -library "$WORK/xc-device/liblouis.a" -headers "$WORK/xc-device/Headers" \
  -library "$WORK/xc-sim/liblouis.a" -headers "$WORK/xc-sim/Headers" \
  -output "$HERE/liblouis.xcframework" > /dev/null

# Tables must come from the same release as the library: the table language
# changes between versions, and older tables fail to compile.
echo "Copying English and Spanish braille tables..."
mkdir -p "$HERE/tables"
for t in en-ueb-g1.ctb en-ueb-g2.ctb en-ueb-chardefs.uti en-ueb-math.ctb \
         braille-patterns.cti latinLetterDef6Dots.uti latinUppercaseComp6.uti \
         spaces.uti text_nabcc.dis es-g1.ctb es-g2.ctb es-chardefs.cti \
         litdigits6Dots.uti digits6Dots.uti; do
  cp "$SRC/tables/$t" "$HERE/tables/"
done

cp "$SRC/COPYING.LESSER" "$HERE/LICENSE-LGPL-2.1.txt"

echo "Done. liblouis ${VERSION} built for arm64 device and simulator."
