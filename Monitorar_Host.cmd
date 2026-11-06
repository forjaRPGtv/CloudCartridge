@echo off
chcp 65001 >nul
title CloudCartridge - Monitor privado
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0CloudCartridge.HostMonitor.ps1"
if errorlevel 1 exit /b %errorlevel%
