# ==============================================================================
# CloudROM Telemetry Dashboard - Open-Source Edition
# Com Cloud Save Sync, Multi-Disc Pre-fetch & Campanha Fixada (⭐ Pin)
# Arthur Reis Projetos
# ==============================================================================

[CmdletBinding()]
param (
    [string]$FilePath = '',
    [switch]$LaunchAfter = $false,
    [switch]$DashboardOnly = $false
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Ajustar tamanho e título da janela
try {
    $host.UI.RawUI.WindowTitle = "Telemetria CloudCartridge - Downloads & Retenção de Jogos"
    if ($host.UI.RawUI.WindowSize.Width -lt 92) {
        $host.UI.RawUI.WindowSize = New-Object System.Management.Automation.Host.Size(92, 34)
    }
} catch {}

$scriptDir = $PSScriptRoot
$configFile = Join-Path $scriptDir "config.json"
$config = $null
if (Test-Path -LiteralPath $configFile) {
    try { $config = Get-Content -LiteralPath $configFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
}

$baseDir = if ($config -and $config.local_roms_path) { $config.local_roms_path } else { 'Z:\_ISOS_ROMS_' }
$gDrivePath = if ($config -and $config.google_drive_roms_path) { $config.google_drive_roms_path } else { '' }
$cloudSavesDir = if ($gDrivePath) { Join-Path $gDrivePath '_RA_SAVES' } else { '' }
$retentionDays = if ($config -and $config.retention_days) { [int]$config.retention_days } else { 3 }
$registryFile = Join-Path $baseDir '.cache_registry.json'

function Get-RegistryData {
    if (Test-Path -LiteralPath $registryFile) {
        try {
            return Get-Content -LiteralPath $registryFile -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {}
    }
    return [PSCustomObject]@{ retention_days = $retentionDays; games = @{} }
}

function Save-RegistryData ($reg) {
    try {
        $reg | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $registryFile -Encoding UTF8
    } catch {}
}

function Get-ProgressBar ([double]$percent, [int]$barWidth = 36) {
    $completedWidth = [math]::Floor(($percent / 100) * $barWidth)
    $remainingWidth = $barWidth - $completedWidth
    if ($completedWidth -lt 0) { $completedWidth = 0 }
    if ($remainingWidth -lt 0) { $remainingWidth = 0 }
    return ('█' * $completedWidth) + ('░' * $remainingWidth)
}

function Get-RemainingTimeStr ([DateTime]$lastPlayed, [bool]$isPinned) {
    if ($isPinned) {
        return "⭐ EM CAMPANHA (FIXADO - NUNCA EXPIRA)"
    }
    $expireTime = $lastPlayed.AddDays($retentionDays)
    $now = Get-Date
    $diff = $expireTime - $now

    if ($diff.TotalSeconds -le 0) {
        return "Expirando na próxima limpeza"
    }

    $days = $diff.Days
    $hours = $diff.Hours
    $mins = $diff.Minutes

    if ($days -gt 0) {
        return "$days dia(s), $hours h e $mins min"
    } elseif ($hours -gt 0) {
        return "$hours h e $mins min"
    } else {
        return "$mins minuto(s)"
    }
}

function Sync-CloudSaves ([string]$gamePath) {
    if (-not $cloudSavesDir -or -not (Test-Path -LiteralPath $cloudSavesDir)) { return }
    Write-Host "`n[Cloud Save Sync] Verificando saves gerados durante a partida..." -ForegroundColor Cyan
    $gameBase = [System.IO.Path]::GetFileNameWithoutExtension($gamePath)
    $cleanGameBase = $gameBase -replace '\s*\([^\)]*\)', ''
    
    $localSaveSources = @(
        'C:\RetroArch-Win64\saves',
        'C:\RetroArch-Win64\states',
        (Join-Path $baseDir '_RA_SAVES')
    )

    $syncedCount = 0
    foreach ($source in $localSaveSources) {
        if (Test-Path -LiteralPath $source) {
            $recentSaves = Get-ChildItem -LiteralPath $source -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { 
                    ($_.Name -like "*$cleanGameBase*" -or $_.Name -like "*$gameBase*") -and
                    ($_.Extension -match '^\.(srm|state|mcd|sav|state[0-9]+)$') -and
                    ((Get-Date) - $_.LastWriteTime).TotalMinutes -le 60
                }

            foreach ($s in $recentSaves) {
                try {
                    $rel = $s.FullName.Substring($source.Length).TrimStart('\', '/')
                    $destFile = Join-Path $cloudSavesDir $rel
                    $destFolder = Split-Path $destFile -Parent
                    if (-not (Test-Path -LiteralPath $destFolder)) {
                        New-Item -ItemType Directory -Path $destFolder -Force | Out-Null
                    }
                    Copy-Item -LiteralPath $s.FullName -Destination $destFile -Force
                    $syncedCount++
                    Write-Host "  -> Save sincronizado na nuvem: $($s.Name)" -ForegroundColor Green
                } catch {}
            }
        }
    }

    if ($syncedCount -gt 0) {
        Write-Host "[Cloud Save Sync] Sucesso: $syncedCount save(s) enviados e protegidos na nuvem!" -ForegroundColor Green
    }
}

function Check-And-PrefetchMultiDisc ([string]$gamePath) {
    $parentDir = Split-Path $gamePath -Parent
    $fileName = [System.IO.Path]::GetFileName($gamePath)

    if ($fileName -match '(.*)[\(\[]?(Disc|Disk|CD)\s*1[\)\]]?(.*)') {
        $prefix = $matches[1].Trim()
        $otherDiscs = Get-ChildItem -LiteralPath $parentDir -File -ErrorAction SilentlyContinue |
            Where-Object { 
                $_.Name -ne $fileName -and 
                $_.Name -match [regex]::Escape($prefix) -and 
                $_.Name -match '(Disc|Disk|CD)\s*[2-9]'
            }

        if ($otherDiscs -and $otherDiscs.Count -gt 0) {
            Write-Host "`n==========================================================================================" -ForegroundColor Magenta
            Write-Host " [MULTI-DISCO DETECTADO] Este jogo possui $($otherDiscs.Count + 1) discos!" -ForegroundColor Yellow
            Write-Host " Discos seguintes encontrados:" -ForegroundColor White
            foreach ($d in $otherDiscs) {
                $sMB = [math]::Round($d.Length / 1MB, 1)
                Write-Host "  • $($d.Name) ($sMB MB)" -ForegroundColor Gray
            }
            Write-Host " Pré-baixando discos adicionais para evitar travamentos durante a campanha..." -ForegroundColor Cyan
            Write-Host "==========================================================================================" -ForegroundColor Magenta

            foreach ($d in $otherDiscs) {
                Write-Host "`n -> Pré-baixando: $($d.Name)..." -ForegroundColor Yellow
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -FilePath $d.FullName -LaunchAfter:$false
            }
        }
    }
}

function Draw-InstalledGamesPanel {
    Write-Host "==========================================================================================" -ForegroundColor DarkCyan
    Write-Host " [PAINEL 2] JOGOS INSTALADOS NO PC & CONTAGEM REGRESSIVA (RETENÇÃO: $retentionDays DIAS)             " -ForegroundColor Yellow
    Write-Host "==========================================================================================" -ForegroundColor DarkCyan

    $reg = Get-RegistryData
    $installedCount = 0
    $totalMB = 0

    if ($reg.games) {
        $keys = @($reg.games.PSObject.Properties.Name)
        foreach ($k in $keys) {
            $item = $reg.games.$k
            if ($item.status -eq 'local_cached' -and (Test-Path -LiteralPath $k)) {
                $installedCount++
                $size = if ($item.size_mb) { [double]$item.size_mb } else { 0 }
                $totalMB += $size
                $dt = if ($item.last_played) { [DateTime]$item.last_played } else { Get-Date }
                $isPinned = [bool]$item.is_pinned
                $remStr = Get-RemainingTimeStr $dt $isPinned

                Write-Host " • " -NoNewline -ForegroundColor Green
                Write-Host "[$($item.system)] " -NoNewline -ForegroundColor Cyan
                Write-Host "$($item.title) " -NoNewline -ForegroundColor White
                Write-Host "($($size) MB)" -ForegroundColor Gray
                Write-Host "   -> Jogado em: $($dt.ToString('dd/MM HH:mm')) | " -NoNewline -ForegroundColor DarkGray
                
                if ($isPinned) {
                    Write-Host $remStr -ForegroundColor Green
                } else {
                    Write-Host "Falta para sair: $remStr" -ForegroundColor Yellow
                }
            }
        }
    }

    if ($installedCount -eq 0) {
        Write-Host " Nenhum jogo ocupando espaço local no momento. Sua biblioteca está 100% na nuvem!" -ForegroundColor Gray
    } else {
        Write-Host "------------------------------------------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host " Total em disco: $([math]::Round($totalMB, 1)) MB em $installedCount jogo(s) instalados." -ForegroundColor Green
        Write-Host " *Jogos com estrela (⭐) estão em campanha e nunca são apagados automaticamente." -ForegroundColor Cyan
        Write-Host " *Ao zerar o tempo, o espaço é liberado sem apagar nada da nuvem nem perder saves." -ForegroundColor DarkGray
    }
    Write-Host "==========================================================================================" -ForegroundColor DarkCyan
}

Clear-Host

if ($DashboardOnly -or [string]::IsNullOrWhiteSpace($FilePath)) {
    Write-Host "==========================================================================================" -ForegroundColor Cyan
    Write-Host "          DASHBOARD DE TELEMETRIA CLOUDCARTRIDGE - OpenSource Edition                     " -ForegroundColor Yellow
    Write-Host "==========================================================================================" -ForegroundColor Cyan
    Write-Host " Status Atual: Standby / Monitorando requisições de jogos..." -ForegroundColor Gray
    Write-Host ""
    Draw-InstalledGamesPanel
    Write-Host "`nPressione qualquer tecla para fechar..." -ForegroundColor Gray
    [void][System.Console]::ReadKey($true)
    exit 0
}

$fileItem = Get-Item -LiteralPath $FilePath
$fileName = $fileItem.Name
$totalBytes = $fileItem.Length
$totalMB = [math]::Round($totalBytes / 1MB, 2)
$platform = Split-Path (Split-Path $FilePath -Parent) -Leaf

Write-Host "==========================================================================================" -ForegroundColor Cyan
Write-Host "                  TELEMETRIA CLOUDCARTRIDGE - DOWNLOAD EM TEMPO REAL                     " -ForegroundColor Yellow
Write-Host "==========================================================================================" -ForegroundColor Cyan
Write-Host " [PAINEL 1] ARQUIVO EM TRANSFERÊNCIA" -ForegroundColor Yellow
Write-Host " -----------------------------------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host " Plataforma : " -NoNewline -ForegroundColor Gray; Write-Host $platform -ForegroundColor White
Write-Host " Arquivo    : " -NoNewline -ForegroundColor Gray; Write-Host $fileName -ForegroundColor White
Write-Host " Tamanho    : " -NoNewline -ForegroundColor Gray; Write-Host "$totalMB MB" -ForegroundColor White
Write-Host " Origem     : " -NoNewline -ForegroundColor Gray; Write-Host "Google Drive (Nuvem)" -ForegroundColor Cyan
Write-Host " -----------------------------------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host " Progresso  : [Iniciando conexão de streaming...]" -ForegroundColor Yellow
Write-Host " Baixado    : 0 MB de $totalMB MB" -ForegroundColor Gray
Write-Host " Velocidade : 0 MB/s" -ForegroundColor Gray
Write-Host " Tempo      : 0s decorridos" -ForegroundColor Gray
Write-Host ""

Draw-InstalledGamesPanel

$buffer = New-Object byte[] (4 * 1024 * 1024)
$stream = $null
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$readTotal = 0
$lastUpdate = [DateTime]::MinValue

try {
    $stream = [System.IO.File]::OpenRead($FilePath)

    while ($readTotal -lt $totalBytes) {
        $bytesRead = $stream.Read($buffer, 0, $buffer.Length)
        if ($bytesRead -eq 0) { break }
        $readTotal += $bytesRead

        $now = [DateTime]::Now
        if (($now - $lastUpdate).TotalMilliseconds -ge 100 -or $readTotal -ge $totalBytes) {
            $lastUpdate = $now
            $percent = if ($totalBytes -gt 0) { [math]::Min(100.0, [math]::Round(($readTotal / $totalBytes) * 100, 1)) } else { 100.0 }
            $mbRead = [math]::Round($readTotal / 1MB, 2)
            $elapsedSec = $stopwatch.Elapsed.TotalSeconds
            $speed = if ($elapsedSec -gt 0) { [math]::Round(($readTotal / 1MB) / $elapsedSec, 2) } else { 0 }
            $etaSec = if ($speed -gt 0 -and $totalMB -gt $mbRead) { [math]::Round(($totalMB - $mbRead) / $speed, 0) } else { 0 }
            $bar = Get-ProgressBar -percent $percent -barWidth 36

            [Console]::CursorLeft = 0; [Console]::CursorTop = 9
            Write-Host " Progresso  : " -NoNewline -ForegroundColor Gray
            Write-Host "[$bar] " -NoNewline -ForegroundColor Green
            Write-Host "$percent%     " -ForegroundColor Yellow

            [Console]::CursorLeft = 0; [Console]::CursorTop = 10
            Write-Host " Baixado    : " -NoNewline -ForegroundColor Gray
            Write-Host "$mbRead MB de $totalMB MB        " -ForegroundColor White

            [Console]::CursorLeft = 0; [Console]::CursorTop = 11
            Write-Host " Velocidade : " -NoNewline -ForegroundColor Gray
            Write-Host "$speed MB/s        " -ForegroundColor Cyan

            [Console]::CursorLeft = 0; [Console]::CursorTop = 12
            Write-Host " Tempo      : " -NoNewline -ForegroundColor Gray
            Write-Host "$([math]::Round($elapsedSec, 1))s decorridos | ETA restante: $($etaSec)s     " -ForegroundColor White
        }
    }
} finally {
    if ($stream) { $stream.Close(); $stream.Dispose() }
    $stopwatch.Stop()
}

$reg = Get-RegistryData
if (-not $reg.games) { $reg | Add-Member -MemberType NoteProperty -Name "games" -Value ([PSCustomObject]@{}) }
$cleanPath = $FilePath.Replace('/', '\')
$existingPinned = $false
if ($reg.games.PSObject.Properties[$cleanPath] -and $reg.games.$cleanPath.is_pinned) {
    $existingPinned = [bool]$reg.games.$cleanPath.is_pinned
}

$entry = [PSCustomObject]@{
    title       = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
    system      = $platform
    last_played = (Get-Date).ToString("o")
    size_mb     = $totalMB
    status      = "local_cached"
    is_pinned   = $existingPinned
}
if ($reg.games.PSObject.Properties[$cleanPath]) {
    $reg.games.$cleanPath = $entry
} else {
    $reg.games | Add-Member -MemberType NoteProperty -Name $cleanPath -Value $entry
}
Save-RegistryData $reg

[Console]::CursorLeft = 0; [Console]::CursorTop = 13
Write-Host "`n [STATUS] DOWNLOAD 100% CONCLUÍDO EM $([math]::Round($stopwatch.Elapsed.TotalSeconds, 1))s! O jogo está pronto." -ForegroundColor Green
Start-Sleep -Seconds 1

if ($LaunchAfter) {
    Check-And-PrefetchMultiDisc $FilePath
}

if ($LaunchAfter) {
    Write-Host "`n Inicializando emulador agora..." -ForegroundColor Yellow
    Start-Sleep -Milliseconds 600

    $standaloneFile = Join-Path $scriptDir "standalone_emulators.json"
    if (Test-Path -LiteralPath $standaloneFile) {
        try {
            $standaloneMapping = Get-Content -LiteralPath $standaloneFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($standaloneMapping.PSObject.Properties[$platform]) {
                $emu = $standaloneMapping.$platform
                if (Test-Path -LiteralPath $emu.Executable) {
                    $argsFormatted = $emu.Arguments.Replace('{ROM}', $FilePath)
                    Start-Process -FilePath $emu.Executable -ArgumentList $argsFormatted -Wait
                    Sync-CloudSaves $FilePath
                    Write-Host "`n[Telemetria] Partida finalizada! Retenção ativa por $retentionDays dias." -ForegroundColor Green
                    Start-Sleep -Seconds 2
                    exit 0
                }
            }
        } catch {}
    }

    $coreMappingFile = Join-Path $scriptDir "core_mapping.json"
    $retroArchExe = if ($config -and $config.retroarch_path) { $config.retroarch_path } else { 'C:\RetroArch-Win64\retroarch.exe' }
    $coreMapping = @{}
    if (Test-Path -LiteralPath $coreMappingFile) {
        $coreMapping = Get-Content -LiteralPath $coreMappingFile -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    $coreInfo = if ($coreMapping.PSObject.Properties[$platform]) { $coreMapping.$platform } else { $null }

    if ($coreInfo -and (Test-Path -LiteralPath $coreInfo.CorePath) -and (Test-Path -LiteralPath $retroArchExe)) {
        Start-Process -FilePath $retroArchExe -ArgumentList "-L", "`"$($coreInfo.CorePath)`"", "`"$FilePath`"" -Wait
    } else {
        Start-Process -FilePath $FilePath -Wait
    }

    Sync-CloudSaves $FilePath
    Write-Host "`n[Telemetria] Partida finalizada! Retenção ativa por $retentionDays dias." -ForegroundColor Green
    Start-Sleep -Seconds 2
}
