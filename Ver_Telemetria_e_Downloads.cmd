@echo off
chcp 65001 >nul
title Telemetria CloudROM - Downloads & Retenção
cls
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0CloudROM_Telemetry.ps1" -DashboardOnly
