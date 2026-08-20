# liblouis

Braille translation for ghostWriter's eBraille export. Grade 1 and grade 2
Unified English Braille.

## Version

liblouis 3.38.0, released 1 June 2026, from the upstream release tarball at
https://github.com/liblouis/liblouis

## What is here

- `liblouis.xcframework` — static library, arm64 device and arm64 simulator
- `tables/` — the nine UEB tables grade 1 and grade 2 resolve to
- `LICENSE-LGPL-2.1.txt` — the licence the library and tables are under
- `build-liblouis.sh` — regenerates everything above

## Licensing

The liblouis library is LGPL 2.1 or later. The bundled table files retain their
upstream copyright and licence notices; check those notices when changing the
table set.

liblouis also ships command line tools under GPL 3. Those are **not** built and
**not** shipped. `build-liblouis.sh` builds only `liblouis/` and `gnulib/`,
never `tools/`. Distributors must still meet the LGPL obligations that apply to
the statically linked library, including any required source and relinking
materials. This file is technical provenance, not legal advice.

Attribution and the full licence text are surfaced in the app's licence screen
alongside ZIPFoundation.

## Build configuration

Configured `--enable-static --disable-shared --without-yaml --disable-ucs4`,
minimum iOS 17.

`--disable-ucs4` pins `widechar` to 16 bits. That matters: it makes liblouis
speak UTF-16, which is Swift's native string representation, so the bridge
hands over `String.utf16` directly with no conversion layer.

The release tarball ships a pre-generated `configure`, so `automake` is not
needed to build this.

Do not add `-fembed-bitcode-marker`. Bitcode is no longer supported and current
linkers misparse the flag.

## Notes for the Swift side

Two things are easy to get wrong.

**Table location.** `lou_setDataPath` is deprecated as of 3.38 and does not
reliably work. Set the `LOUIS_TABLEPATH` environment variable instead, pointing
at the bundled `tables/` directory.

**Output encoding.** By default liblouis emits ASCII braille, the old BRF
convention where a cell is a printable ASCII character. eBraille requires real
Unicode braille patterns in U+2800–U+28FF. Pass `dotsIO | ucBrl` as the
translation mode to get them. Without it the export looks like it works and is
silently wrong.

## Tables

Tables must always come from the same release as the library. The table
language evolves, and tables from an older liblouis fail to compile — the
0.10.20-era tables previously used elsewhere use a `uplow` opcode that 3.38
has removed.
