@echo off
chcp 65001 >nul
title CloudROM - Menu de Contexto
cls
echo Registrando opcoes do CloudROM no botao direito do Windows...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup_context_menu.ps1"
pause
