@ECHO OFF
IF "%~1"=="" GOTO USAGE

WHERE py >NUL 2>NUL
IF ERRORLEVEL 1 GOTO PYTHON
py -3 "%~dp0install.py" "%~1"
GOTO END

:PYTHON
WHERE python >NUL 2>NUL
IF ERRORLEVEL 1 GOTO NOPYTHON
python "%~dp0install.py" "%~1"
GOTO END

:NOPYTHON
ECHO Python 3 was not found. Install it, then run this file again.
GOTO END

:USAGE
ECHO Drag the Prehistorik 2 game folder onto INSTALL-WINDOWS.cmd
ECHO or run: INSTALL-WINDOWS.cmd C:\PATH\TO\PRE2

:END
