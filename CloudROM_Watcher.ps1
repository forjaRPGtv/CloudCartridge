# ==============================================================================
# CloudROM Watcher - Guardião de Telemetria Universal para RetroArch & Standalone
# Monitora content_history.lpl e processos de emuladores para disparar a Telemetria
# Arthur Reis Projetos
# ==============================================================================

[CmdletBinding()]
param (
    [switch]$StayActive = $true
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$baseDir = 'Z:\_ISOS_ROMS_'
$telemetryScript = 'z:\_Arthur_Projetos\RetroArch-Tools\CloudROM_Telemetry.ps1'
$historyFile = 'C:\RetroArch-Win64\playlists\builtin\content_history.lpl'
$historyDir = Split-Path $historyFile -Parent

# Extensões suportadas de jogos
$validExtensions = @(
    '.7z', '.zip', '.chd', '.iso', '.cso', '.bin', '.cue', 
    '.pbp', '.wbfs', '.rvz', '.nes', '.sfc', '.smc', '.gba', 
    '.gb', '.gbc', '.n64', '.z64', '.v64', '.nds'
)

# Emuladores Standalone suportados
$standaloneProcs = @(
    'pcsx2-qt', 'Dolphin', 'Cemu', 'rpcs3', 'citra-qt', 'duckstation-qt-x64-ReleaseLTCG'
)

# Cache em memória para evitar abrir múltiplas janelas para o mesmo jogo
$activeGames = [System.Collections.Concurrent.ConcurrentDictionary[string, DateTime]]::new()

function Trigger-TelemetryWindow ([string]$targetFile) {
    if ([string]::IsNullOrWhiteSpace($targetFile)) { return }
    $cleanPath = $targetFile.Replace('/', '\')
    $ext = [System.IO.Path]::GetExtension($cleanPath).ToLower()

    # Ignorar pastas internas de assets, saves e BIOS
    if ($cleanPath -like '*_RA_*' -or $cleanPath -like '*_INSTALLERS*' -or $cleanPath -like '*cheats*') {
        return
    }

    if ($validExtensions -notcontains $ext) {
        return
    }

    if (-not (Test-Path -LiteralPath $cleanPath)) {
        return
    }

    # Evitar disparos repetidos para o mesmo arquivo dentro de 15 segundos
    $now = [DateTime]::Now
    $lastTime = [DateTime]::MinValue
    if ($activeGames.TryGetValue($cleanPath, [ref]$lastTime)) {
        if (($now - $lastTime).TotalSeconds -lt 15) {
            return
        }
    }
    $activeGames[$cleanPath] = $now

    $fileName = Split-Path $cleanPath -Leaf
    Write-Host "`n[Watcher] JOGO DETECTADO: $fileName" -ForegroundColor Cyan
    Write-Host "[Watcher] Abrindo janela de telemetria em tempo real..." -ForegroundColor Green

    # Abrir a janela de telemetria destacada em primeiro plano
    $psArgs = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$telemetryScript`"",
        "-FilePath", "`"$cleanPath`"",
        "-LaunchAfter:`$false"
    )

    Start-Process -FilePath "powershell.exe" -ArgumentList $psArgs -WindowStyle Normal
}

function Check-RetroArchHistory {
    if (Test-Path -LiteralPath $historyFile) {
        try {
            $data = Get-Content -LiteralPath $historyFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($data.items -and $data.items.Count -gt 0) {
                $latest = $data.items[0]
                if ($latest.path -and $latest.path -like 'Z:\_ISOS_ROMS_\*') {
                    Trigger-TelemetryWindow $latest.path
                }
            }
        } catch {}
    }
}

function Check-StandaloneEmulators {
    foreach ($procName in $standaloneProcs) {
        $procs = Get-Process -Name $procName -ErrorAction SilentlyContinue
        foreach ($p in $procs) {
            try {
                $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId = $($p.Id)").CommandLine
                if ($cmd -match '([A-Za-z]:\\[^"]+\.(chd|iso|cso|bin|cue|rvz|wbfs|7z|zip))') {
                    $romPath = $matches[1]
                    if (Test-Path -LiteralPath $romPath) {
                        Trigger-TelemetryWindow $romPath
                    }
                }
            } catch {}
        }
    }
}

Clear-Host
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "      CloudROM Watcher - Guardião de Telemetria Universal        " -ForegroundColor Yellow
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "Status: Ativo e monitorando RetroArch e Emuladores Standalone..." -ForegroundColor White
Write-Host "Sempre que qualquer jogo for aberto (pelo menu ou atalho)," -ForegroundColor Gray
Write-Host "a janela de telemetria abrirá automaticamente!" -ForegroundColor Gray
Write-Host "=================================================================`n" -ForegroundColor DarkCyan

# 1. Configurar FileSystemWatcher no content_history.lpl do RetroArch
$watcher = $null
if (Test-Path -LiteralPath $historyDir) {
    $watcher = New-Object System.IO.FileSystemWatcher $historyDir, (Split-Path $historyFile -Leaf)
    $watcher.NotifyFilter = [System.IO.NotifyFilters]::LastWrite -bor [System.IO.NotifyFilters]::Size
    $watcher.EnableRaisingEvents = $true

    $action = {
        Start-Sleep -Milliseconds 200
        Check-RetroArchHistory
    }

    $changedEvent = Register-ObjectEvent $watcher 'Changed' -Action $action
    Write-Host "[OK] Monitor de histórico do RetroArch engatilhado com sucesso." -ForegroundColor Green
}

# 2. Loop de monitoramento para Standalone e liveness
try {
    while ($StayActive) {
        Check-StandaloneEmulators
        Start-Sleep -Seconds 2
    }
} finally {
    if ($watcher) {
        Unregister-Event -SourceIdentifier $changedEvent.Name -ErrorAction SilentlyContinue
        $watcher.Dispose()
    }
    Write-Host "`n[Watcher] Monitor de telemetria encerrado." -ForegroundColor Yellow
}
