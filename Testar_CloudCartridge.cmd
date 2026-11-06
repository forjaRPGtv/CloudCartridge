@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tests\Run-Tests.ps1"
set "EXIT_CODE=%ERRORLEVEL%"
echo.
if not "%EXIT_CODE%"=="0" echo [FALHA] Testes do CloudCartridge falharam.
if "%EXIT_CODE%"=="0" echo [OK] Testes do CloudCartridge passaram.
exit /b %EXIT_CODE%
