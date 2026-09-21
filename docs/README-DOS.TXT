PRE2GUS 1.3 - NATIVE GRAVIS ULTRASOUND AUDIO FOR PREHISTORIK 2
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

MUSIC PANNING
-------------

RUN_GUS.BAT uses /P60. You can run PRE2GUS directly with /P-100 through /P100,
or with the OCP-style spelling -vp-100 through -vp100. /P0 centers the music,
/P100 gives full separation, and a negative value reverses left and right.

COMPATIBILITY
-------------

The launcher was reported working on a physical AMD 386DX-40 with a 1 MB GUS
MAX. The native installer and all of its generated files were verified under a
DOSBox-X 386 CPU profile. Native installation on physical hardware is still to
be confirmed.

LEGAL
-----

Prehistorik 2 and its data remain the property of their respective rights
holders. This independent project is not affiliated with or endorsed by them.
Do not redistribute the original game files or the converted audio.
