@echo off
:: Spirited Gifts shipping station setup - right-click this file > Run as administrator
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0SG-Setup.ps1"
if errorlevel 1 (
  echo.
  echo Something failed. Check results\%COMPUTERNAME%.txt and C:\SGSetup\
  pause
)
