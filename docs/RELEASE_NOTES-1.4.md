PRE2GUS 1.4 keeps the GUS analog line input enabled when the game takes over,
fixing the unwanted line-input mute observed with release 1.3 on real hardware.

New launcher controls:

- `/M0..100` selects music volume; `-vm` is the OCP-style alias.
- `/S0..100` selects sound-effect volume; `-vs` is the OCP-style alias.
- `/LON` keeps line input enabled (the default).
- `/LOFF` mutes line input after the intro and enables it again on exit.

If `/M` or `/S` is omitted, the exact volume scalar from earlier releases is
retained. `RUN_GUS.BAT` continues to select 60% music stereo width.

The release contains native 16-bit DOS binaries and a DOS-side asset converter.
Extract `PRE2GUS-1.4-DOS.zip` into a legally obtained game directory and run
`INSTALL`. No compiler, Python, Windows, or original game data is included in
the release.

Release 1.3 was reported working on an AMD 386DX-40 with a 1 MB GUS MAX. The
new 1.4 controls and GF1 self-test passed under a DOSBox-X 386 profile; physical
1.4 confirmation remains pending.
