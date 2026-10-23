@echo off
rem Checks GitHub for new versions of the suite's apps and installs them (your data is never touched).
title AI Research Suite - Check for updates
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0update.ps1" %*
echo.
pause
