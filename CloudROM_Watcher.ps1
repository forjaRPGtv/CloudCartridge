# ==============================================================================
# CloudROM Watcher - Open-Source Edition
# Guardião de Telemetria em Background para Emuladores
# Arthur Reis Projetos
# ==============================================================================

[CmdletBinding()]
param (
    [switch]$StayActive = $true
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = $PSScriptRoot
$configFile = Join-Path $scriptDir "config.json"
$config = $null
if (Test-Path -LiteralPath $configFile) {
    try { $config = Get-Content -LiteralPath $configFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
}

$baseDir = if ($config -and $config.local_roms_path) { $config.local_roms_path } else { 'Z:\_ISOS_ROMS_' }
$registryFile = Join-Path $baseDir '.cache_registry.json'
$telemetryScript = Join-Path $scriptDir "CloudROM_Telemetry.ps1"

$validExtensions = @(
    '.7z', '.zip', '.chd', '.iso', '.cso', '.bin', '.cue', 
    '.pbp', '.wbfs', '.rvz', '.nes', '.sfc', '.smc', '.gba', 
    '.gb', '.gbc', '.n64', '.z64', '.v64', '.nds'
)

$activeDownloads = [System.Collections.Concurrent.ConcurrentDictionary[string, DateTime]]::new()

function Is-GameInCache ([string]$fullPath) {
    if (Test-Path -LiteralPath $registryFile) {
        try {
            $reg = Get-Content -LiteralPath $registryFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($reg.games) {
                $cleanPath = $fullPath.Replace('/', '\')
                if ($reg.games.PSObject.Properties[$cleanPath]) {
                    return ($reg.games.$cleanPath.status -eq 'local_cached')
                }
            }
        } catch {}
    }
    return $false
}

function Trigger-TelemetryWindow ([string]$targetFile) {
    $cleanPath = $targetFile.Replace('/', '\')
    $ext = [System.IO.Path]::GetExtension($cleanPath).ToLower()

    if ($cleanPath -like '*_RA_*' -or $cleanPath -like '*_INSTALLERS*' -or $cleanPath -like '*cheats*') {
        return
    }

    if ($validExtensions -notcontains $ext) {
        return
    }

    $now = [DateTime]::Now
    $lastTime = [DateTime]::MinValue
    if ($activeDownloads.TryGetValue($cleanPath, [ref]$lastTime)) {
        if (($now - $lastTime).TotalSeconds -lt 10) {
            return
        }
    }

    if (Is-GameInCache $cleanPath) {
        return
    }

    $activeDownloads[$cleanPath] = $now

    Write-Host "`n[Watcher] Detectado carregamento de jogo na nuvem: " -NoNewline -ForegroundColor Cyan
    Write-Host (Split-Path $cleanPath -Leaf) -ForegroundColor Yellow
    Write-Host "[Watcher] Abrindo janela de telemetria em tempo real..." -ForegroundColor Green

    $psArgs = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$telemetryScript`"",
        "-FilePath", "`"$cleanPath`"",
        "-LaunchAfter:`$false"
    )

    Start-Process -FilePath "powershell.exe" -ArgumentList $psArgs -WindowStyle Normal
}

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "      CloudROM Watcher - Guardião de Telemetria Ativo            " -ForegroundColor Yellow
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "Monitorando requisições de jogos em $baseDir..." -ForegroundColor White
Write-Host "Sempre que um jogo na nuvem for aberto no emulador," -ForegroundColor Gray
Write-Host "uma janela de telemetria com progresso em tempo real aparecerá!" -ForegroundColor Gray
Write-Host "Pressione Ctrl+C para encerrar o monitor.`n" -ForegroundColor DarkGray

if (-not (Test-Path -LiteralPath $baseDir)) {
    Write-Host "Aviso: Diretório base $baseDir ainda não existe. Execute Setup_CloudROM.ps1 primeiro." -ForegroundColor Yellow
    exit 0
}

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $baseDir
$watcher.IncludeSubdirectories = $true
$watcher.EnableRaisingEvents = $true
$watcher.NotifyFilter = [System.IO.NotifyFilters]::FileName -bor [System.IO.NotifyFilters]::LastAccess -bor [System.IO.NotifyFilters]::Size

$action = {
    $path = $Event.SourceEventArgs.FullPath
    Trigger-TelemetryWindow $path
}

$createdEvent = Register-ObjectEvent $watcher 'Created' -Action $action
$changedEvent = Register-ObjectEvent $watcher 'Changed' -Action $action

try {
    while ($StayActive) {
        Start-Sleep -Seconds 2
    }
} finally {
    Unregister-Event -SourceIdentifier $createdEvent.Name -ErrorAction SilentlyContinue
    Unregister-Event -SourceIdentifier $changedEvent.Name -ErrorAction SilentlyContinue
    $watcher.Dispose()
    Write-Host "`n[Watcher] Monitor de telemetria encerrado." -ForegroundColor Yellow
}
