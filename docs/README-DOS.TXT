PRE2GUS 1.4 - NATIVE GRAVIS ULTRASOUND AUDIO FOR PREHISTORIK 2
================================================================

This package contains no files from the original game. You must have a
legally obtained DOS copy with PRE2.EXE, twelve .TRK files, and SAMPLE.SQZ.

INSTALL DIRECTLY IN DOS
-----------------------

1. Back up your working game directory.
2. Extract every file in this ZIP into that directory.
3. Change to the game directory and run:

      INSTALL

   Use INSTALL /Y to replace existing generated audio without prompting.
4. Make sure ULTRASND is set, for example:

      SET ULTRASND=240,7,7,7,7

5. Run TEST_GUS.BAT. Listen for music and a digital sound effect.
6. Run RUN_GUS.BAT to start the game with 60 percent music panning.

INSTALL.COM converts the original compressed audio locally. It creates twelve
.MOD files and PRE2SFX.RAW, using about 525 KB. It does not modify PRE2.EXE.
Python, Windows, NASM, and a DOS extender are not required.

AUDIO CONTROLS
--------------

RUN_GUS.BAT uses /P60. You can run PRE2GUS directly with /P-100 through /P100,
or with the OCP-style spelling -vp-100 through -vp100. /P0 centers the music,
/P100 gives full separation, and a negative value reverses left and right.

Use /M0 through /M100 for music volume and /S0 through /S100 for sound-effect
volume. OCP-style -vm and -vs spellings are also accepted. If these options are
omitted, PRE2GUS uses the earlier releases' exact volume levels (shown as 81%
music and 86% SFX).

Line input stays enabled during the game by default. /LON selects this
explicitly. /LOFF keeps line input enabled for the intro, mutes it when the
game takes over, and enables it again on exit.

COMPATIBILITY
-------------

Release 1.3 was reported working on a physical AMD 386DX-40 with a 1 MB GUS
MAX. Version 1.4's new controls and GF1 self-test were verified under a
DOSBox-X 386 CPU profile; physical 1.4 confirmation is still pending.

LEGAL
-----

Prehistorik 2 and its data remain the property of their respective rights
holders. This independent project is not affiliated with or endorsed by them.
Do not redistribute the original game files or the converted audio.
