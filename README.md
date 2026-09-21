# PRE2GUS

Native Gravis UltraSound GF1 music and sound effects for the DOS version of
**Prehistorik 2**, implemented as a non-destructive launcher.

PRE2GUS leaves `PRE2.EXE` unchanged on disk. It waits for the protected loader
to finish, verifies the materialized game-code signatures, and redirects the
game's music and sound-effect entry points to a direct GF1 driver. The GUS MAX
codec is not required.

## What is included

- 16-bit real-mode launcher and GF1 driver source (`src/pre2gus.asm`)
- a reproducible prebuilt launcher (`dist/PRE2GUS.COM`)
- a reproducible native DOS installer (`dist/INSTALL.COM`)
- an optional modern-host installer (`install.py`)
- an asset converter that decodes the user's original `.TRK` and `SAMPLE.SQZ`
  files locally (native DOS and Python implementations)
- DOS launch and self-test batch files

This repository contains **no original game executable, compressed tracks,
music modules, graphics, or sound-effect data**. Converted assets are not
redistributable output of this repository; users create them locally from their
own copy of the game.

## Requirements

- an installed copy of the DOS game containing `PRE2.EXE`, the twelve required
  `.TRK` files, and `SAMPLE.SQZ`
- a GF1-compatible Gravis UltraSound with sufficient RAM; the tested target is
  a 1 MB GUS MAX
- `ULTRASND` configured in DOS, for example `240,7,7,7,7`
- approximately 525 KB free for the converted audio
- optional: Python 3 for host-side installation, or NASM 2.x when rebuilding

## Install

### Directly in DOS

Extract the release ZIP into the original game directory, change to that
directory, and run:

```dos
INSTALL
```

`INSTALL.COM` reads the original audio and writes the twelve MODs plus
`PRE2SFX.RAW` locally. It does not modify `PRE2.EXE`. If generated files already
exist, answer `Y` at the prompt or use `INSTALL /Y`.

The installer is a real-mode DOS program with no Python, Windows, protected-mode
extender, or compiler dependency. Its complete conversion was tested using a
DOSBox-X 386 CPU profile, and release 1.3 was reported working on the physical
AMD 386DX-40 target.

### From a modern computer

The optional Python installer can target a directory that will later be copied
to or mounted by the DOS machine:

```sh
python3 install.py /path/to/PRE2
```

On Windows, drag the game folder onto `INSTALL-WINDOWS.cmd`, or run
`INSTALL-WINDOWS.cmd C:\PATH\TO\PRE2`. Python 3 is required only for this
host-side route; compiling PRE2GUS is not.

The installer:

1. reads the original audio assets from that directory;
2. validates and converts the twelve tracker files to four-channel `M.K.` MODs;
3. decodes `SAMPLE.SQZ` into the SFX bank expected by the launcher;
4. copies both DOS programs plus `RUN_GUS.BAT` and `TEST_GUS.BAT` beside the
   game.

It refuses to replace different PRE2GUS-generated files unless `--force` is
given. Add `--build` to assemble both DOS programs locally with NASM instead of
using the reproducible binaries in `dist/`.

In DOS, first run:

```dos
TEST_GUS.BAT
```

Listen for both tracker music and a digital effect, then start the game with:

```dos
RUN_GUS.BAT
```

## Audio controls

`RUN_GUS.BAT` selects 60% stereo width. The launcher accepts signed panning
values from -100 to 100:

```dos
PRE2GUS /P0       REM centered music
PRE2GUS /P40      REM narrower stereo
PRE2GUS /P60      REM default, GF1 positions 3/12
PRE2GUS /P100     REM full GF1 separation
PRE2GUS /P-60     REM reverse left and right
PRE2GUS -vp60     REM OCP-style spelling
```

The GF1 provides 16 discrete pan positions, so adjacent percentages may map to
the same hardware values. The option affects the four music voices, not SFX or
the third-party intro.

Music and SFX volume can be selected independently from 0 through 100:

```dos
PRE2GUS /M60 /S80     REM 60% music, 80% effects
PRE2GUS -vm60 -vs80   REM OCP-style spelling
```

When omitted, `/M` and `/S` retain the earlier releases' exact GF1 master
levels: 52/64 for music (displayed as 81%) and 55/64 for SFX (displayed as
86%).

The GF1 line input remains enabled during the game by default. `/LON` selects
that behavior explicitly; `/LOFF` keeps it enabled for the intro, mutes it at
the verified game handoff, and enables it again when PRE2GUS exits. This mixer
control is write-only, so PRE2GUS cannot read and restore an unknown pre-launch
mute state.

## Executable compatibility

The fully inspected reference executable is 52,190 bytes with SHA-256:

```text
e1a7f875b2806551e3f1a8e393b5dfedd5825c402528a24ed90f21e08a2a1142
```

The Python installer warns, but does not block, when `PRE2.EXE` differs. The
launcher patches only when the required in-memory code signatures match. A
level-select variant with a shortened or absent HybriD intro has been reported
working on real hardware, but that executable has not been independently
audited here.

## Build and verify

```sh
make
make test
make audit
cmp dist/PRE2GUS.COM path/to/rebuilt/PRE2GUS.COM
cmp dist/INSTALL.COM path/to/rebuilt/INSTALL.COM
```

The repository audit rejects original game formats, converted MOD/SFX assets,
archives, and the verified original executable hash. Continuous integration
runs the build, unit tests, reproducibility comparison, and content audit.

## Releases

GitHub Releases provide precompiled `PRE2GUS.COM` and `INSTALL.COM` files in a
ready-to-extract DOS bundle. Release packages deliberately omit the original
compressed audio and all locally generated MOD/SFX files. End users do not need
Python, NASM, or another compiler.

## Hardware and emulator status

- Version 1.1 was reported working well on a physical AMD 386DX-40 with a
  1 MB GUS MAX.
- Version 1.2 panning modes, invalid-argument handling, protected-loader
  handoff, and the first game-requested GF1 track were checked in DOSBox-X.
- Version 1.3 was reported working on the physical AMD 386DX-40/GUS MAX system;
  its handoff-time line-input mute was also observed there.
- Version 1.4's volume parsing, line-input modes, and GF1 self-test were checked
  under a DOSBox-X 386 profile. Physical 1.4 confirmation is still welcome.

See [docs/VALIDATION.md](docs/VALIDATION.md) for the precise verification scope.

## Legal

Prehistorik 2 and its data remain the property of their respective rights
holders. This independent project is not affiliated with or endorsed by them.
You must supply your own legally obtained game copy. Do not publish the source
game files or the converted audio produced by the installer.
