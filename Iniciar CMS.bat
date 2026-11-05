@echo off
cd /d "%~dp0"
title Wild Papagayo - CMS
powershell -NoProfile -ExecutionPolicy Bypass -File "Start-Wild-CMS.ps1"
pause
