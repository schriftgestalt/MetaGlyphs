Place a dereferenced copy of mpost, mpost.mp, and plain.mp in this folder.
The Xcode project copies the engine and its license/notice files into the
plugin's Resources directory. This setup README is excluded from the bundle.

Sources in a BasicTeX installation:
  bin/universal-darwin/mpost
  texmf-dist/metapost/base/mpost.mp
  texmf-dist/metapost/base/plain.mp

Keep upstream license notices with redistributed engine files. Inspect mpost
with otool -L before distribution and include any non-system dependencies.
The vendored engine is MetaPost 3.00 (TeX Live 2026), copied from BasicTeX.
It contains Intel x86_64 and Apple Silicon arm64 slices. Both slices link only
to /usr/lib/libSystem.B.dylib; no additional third-party dylibs are required.
The macro files identify themselves as public domain. The executable includes
LGPL v3-or-later code; retain the corresponding notices and source obligations
when redistributing. This folder contains a prebuilt engine, not engine sources.

Keep COPYING, COPYING.LESSER, METAPOST-NOTICE.txt, REDISTRIBUTION.md, and
SOURCE.txt alongside the engine. Read SOURCE.txt before a binary release:
matching source access and component notices still need to be verified.
