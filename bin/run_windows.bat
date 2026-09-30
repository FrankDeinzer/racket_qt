@echo off
rem Starts the Qt-backed DrRacket on Windows (PLT_QT=1) for manual/free testing
rem (docs/HACKING.md, CLAUDE.md "Run / Smoke-Test" Windows section).
rem Any args are passed to DrRacket (e.g. files to open).
setlocal

set "PLT_QT=1"
set "PATH=C:\Qt\6.11.0\msvc2022_64\bin;%PATH%"

"C:\Program Files\Racket\DrRacket.exe" %*
exit /b %ERRORLEVEL%
