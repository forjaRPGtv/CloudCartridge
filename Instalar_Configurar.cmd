@echo off
chcp 65001 >nul
title CloudROM - Assistente de Configuração
cls
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup_CloudROM.ps1"
pause
