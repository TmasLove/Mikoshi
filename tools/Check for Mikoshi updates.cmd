@echo off
REM Double-click this to check GitHub for a newer Mikoshi and install it.
REM
REM It runs the PowerShell script next to it with -ExecutionPolicy Bypass,
REM scoped to this one process, so nothing about your machine's PowerShell
REM settings is changed.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Update-Mikoshi.ps1" %*
echo.
pause
