# Changelog

## 1.3

- Added `INSTALL.COM`, a native real-mode DOS installer and audio converter.
- Made it possible to install directly on the target 386 without Python,
  Windows, or a compiler.
- Added reproducible builds and repository-content checks for both shipped
  `.COM` binaries.
- Verified under a DOSBox-X 386 profile that all thirteen files produced by
  `INSTALL.COM` are byte-identical to the reference Python converter output.

## 1.2

- Added signed `-100..100` music-width control through `/P` and OCP-style
  `-vp` command-line syntax.
- Made `RUN_GUS.BAT` explicitly select `/P60`.
- Added strict command-line validation and stopped forwarding launcher options
  to the child game.
- Added a source-only distribution workflow: local asset conversion, installer,
  repository content audit, tests, and reproducible build checks.
- Added a precompiled release bundle and Windows drag-and-drop installer entry
  point; end users do not need NASM.

## 1.1

- Enabled the GUS analog line input while the untouched HybriD intro runs.
- Disabled the input at the verified game handoff so Prehistorik 2 proper uses
  GF1 music and sound effects only.
- Restored the line input when the launcher exits.

## 1.0

- First native GF1 launcher for the verified DOS executable.
