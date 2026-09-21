# Validation record

This document separates observations made on real hardware from checks made in
DOSBox-X. Emulator success does not establish electrical or timing behavior on
an individual ISA system.

## Physical hardware

The owner reports that PRE2GUS 1.1 works well on an AMD 386DX-40 system with a
1 MB GUS MAX using `ULTRASND=240,7,7,7,7`. A level-select executable with a
shorter or absent HybriD intro was also reported compatible. That alternate
executable was not supplied for independent code comparison.

PRE2GUS 1.2 retains the same GF1 positions as 1.1 when `/P60` is selected.
Other 1.2 widths have not yet been confirmed by listening on the physical card.
Version 1.3 changes the installer and displayed version, not the GF1 playback
logic. Native installation has not yet been run on the physical machine.

## DOSBox-X

The release build was exercised with a 386 CPU profile, 1 MB GUS MAX profile,
base `240h`, IRQ 7, DMA 7, and an initially uninitialized GUS.

Verified behavior:

- `/T /P0`, `/T /P60`, `/T /P100`, and `/T -vp-100` completed the five-second
  GF1 music-plus-SFX test and received GF1 timer interrupts.
- Captures showed a substantially narrower stereo image at `/P0` than `/P100`.
- `-vp-100` reversed the captured left/right distribution.
- out-of-range, duplicate, missing, malformed, and unknown switches stopped
  before GUS initialization.
- with `/P40`, the protected reference executable reached the exact handoff,
  loaded the first game-requested GF1 track, and restored interrupt vectors.
- with an emulated SB16/OPL3, intro audio preceded the GF1 game track.
- the native `INSTALL.COM` completed with a 386 CPU profile and only DOS file
  services, producing all twelve MODs and `PRE2SFX.RAW` at the expected sizes.

DOSBox-X mixes emulated cards internally, so it cannot prove a physical analog
SB16-to-GUS pass-through path.

## Reproducibility and content checks

- NASM 2.16.01 rebuilt `PRE2GUS.COM` byte-for-byte.
- NASM 2.16.01 rebuilt `INSTALL.COM` byte-for-byte.
- `tools/prepare_assets.py` regenerated all twelve MOD files and the SFX bank
  byte-for-byte from the locally held reference game files.
- all thirteen native-installer outputs compared byte-for-byte equal to those
  Python-converter outputs.
- the repository audit permits the project-built launcher binary and rejects
  the project-built installer binary, and rejects other DOS programs, original
  executable/audio formats, generated assets, and archives.
- no original game asset is required to build or test the repository source.

## Suggested physical checks

1. Keep the previous working PRE2GUS directory as a fallback.
2. Run `TEST_GUS.BAT` and listen for music plus a digital effect.
3. Compare `PRE2GUS /P0`, `/P40`, `/P60`, and `/P100` by ear.
4. Run through several stages and trigger overlapping effects.
5. Exit normally and retain the patch/counter report if anything fails.
