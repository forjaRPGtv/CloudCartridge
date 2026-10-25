@echo off
chcp 65001 >nul
title CloudROM Launcher - OpenSource
cls
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0CloudROM_Launcher.ps1"
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo Ocorreu um erro ao executar o launcher.
    pause
)
