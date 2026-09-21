# Release bundle installation

The release bundle includes precompiled DOS launcher and installer programs. You
do not need Python, NASM, Windows, or another compiler when installing in DOS.

The repository and release intentionally contain no Prehistorik 2 audio data.
`INSTALL.COM` derives everything it needs from the original files already in
the user's game directory.

## DOS on the target machine

1. Back up the working game directory.
2. Extract the release ZIP into that directory.
3. At the DOS prompt, change to the game directory and run `INSTALL`.
4. Run `TEST_GUS.BAT` and listen for tracker music plus a digital effect.
5. Start the game with `RUN_GUS.BAT`.

Use `INSTALL /Y` to replace existing PRE2GUS-generated audio without prompting.
The native installer needs the twelve original `.TRK` files, `SAMPLE.SQZ`, and
about 525 KB of free disk space. It leaves `PRE2.EXE` untouched.

## Optional modern-host installation

### Windows

Drag the game folder onto `INSTALL-WINDOWS.cmd`, or run:

```text
INSTALL-WINDOWS.cmd C:\PATH\TO\PRE2
```

### macOS or Linux

Run:

```sh
python3 install.py /path/to/PRE2
```

The Python installer performs the same local conversion and places both DOS
programs, the two batch files, twelve MODs, and the decoded SFX bank in the game
directory.

On the DOS system, run `TEST_GUS.BAT` first and listen for both music and a
digital effect. Then use `RUN_GUS.BAT`, which selects 60% music stereo width.
