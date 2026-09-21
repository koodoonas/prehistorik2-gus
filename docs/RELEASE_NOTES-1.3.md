PRE2GUS 1.3 adds a native DOS installer and audio converter. Extract
`PRE2GUS-1.3-DOS.zip` directly into a legally obtained Prehistorik 2 game
directory and run `INSTALL` at the DOS prompt. Python and a compiler are not
required.

The release contains no original or converted game audio. `INSTALL.COM` reads
the user's twelve original `.TRK` files and `SAMPLE.SQZ`, then creates the files
needed by the GF1 launcher locally. It never modifies `PRE2.EXE`.

The native installer completed under a DOSBox-X 386 profile. All twelve MODs
and the SFX bank were byte-identical to the verified Python converter outputs.
The final launcher also passed its GF1 music/SFX self-test. Physical 386
installation is still awaiting confirmation.
