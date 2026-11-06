@echo off
setlocal
cd /d "%~dp0"
if not exist "host-data\admin\users.json" (
  echo [ERRO] Banco do Host ausente em host-data\admin\users.json
  echo Configure perfis antes de iniciar o gateway.
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0CloudCartridge.HostServer.ps1" -DatabasePath "%~dp0host-data\admin\users.json" -DataRoot "%~dp0host-data"
exit /b %errorlevel%
