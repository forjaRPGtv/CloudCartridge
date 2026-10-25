@echo off
chcp 65001 >nul
title RetroArch com Telemetria CloudROM
cls

echo =================================================================
echo        Iniciando RetroArch com Telemetria CloudROM Ativa
echo =================================================================
echo.
echo [1/2] Iniciando Guardião de Telemetria em segundo plano...
start /min powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0CloudROM_Watcher.ps1"

echo [2/2] Abrindo RetroArch...
for /f "tokens=*" %%a in ('powershell.exe -NoProfile -Command "(Get-Content '%~dp0config.json' -Raw | ConvertFrom-Json).retroarch_path"') do set RAPATH=%%a
if "%RAPATH%"=="" set RAPATH=C:\RetroArch-Win64\retroarch.exe

"%RAPATH%"

echo.
echo =================================================================
echo RetroArch finalizado. Encerrando Guardião e otimizando cache...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-Process -Name powershell | Where-Object { $_.CommandLine -like '*CloudROM_Watcher*' } | Stop-Process -Force -ErrorAction SilentlyContinue; & '%~dp0CloudROM_Launcher.ps1' -PurgeOnly"

echo Concluído. Até a próxima partida!
timeout /t 2 >nul
