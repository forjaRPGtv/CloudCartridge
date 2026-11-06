# ==============================================================================
# CloudROM Telemetry Dashboard - Open-Source Edition
# Com Cloud Save Sync, Multi-Disc Pre-fetch & Campanha Fixada ( Pin)
# Arthur Reis Projetos
# ==============================================================================

[CmdletBinding()]
param (
    [string]$FilePath = '',
    [switch]$LaunchAfter = $false,
    [switch]$DashboardOnly = $false,
    [switch]$PrefetchOnly = $false
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Ajustar tamanho e titulo da janela
try {
    $host.UI.RawUI.WindowTitle = "Telemetria CloudCartridge - Downloads & Retencao de Jogos"
    if ($host.UI.RawUI.WindowSize.Width -lt 92) {
        $host.UI.RawUI.WindowSize = New-Object System.Management.Automation.Host.Size(92, 34)
    }
} catch {}

$scriptDir = $PSScriptRoot
$configFile = Join-Path $scriptDir "config.json"
$modulePath = Join-Path $scriptDir 'CloudCartridge.Core.psm1'
Import-Module $modulePath -Force
$config = Get-CloudCartridgeConfig -ConfigPath $configFile

$baseDir = $config.local_roms_path
$gDrivePath = $config.google_drive_roms_path
$cloudSavesDir = if ($gDrivePath) { Join-Path $gDrivePath '_RA_SAVES' } else { '' }
$retentionDays = if ($config.cleanup_enabled -and $null -ne $config.retention_days) { [int]$config.retention_days } else { 0 }
$registryFile = Join-Path $baseDir '.cache_registry.json'

function Get-RegistryData {
    if (Test-Path -LiteralPath $registryFile) {
        try {
            return Get-Content -LiteralPath $registryFile -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {}
    }
    return [PSCustomObject]@{ retention_days = $retentionDays; games = [PSCustomObject]@{} }
}

function Save-RegistryData ($reg) {
    Write-CloudCartridgeJsonAtomic -InputObject $reg -Path $registryFile -Depth 5
}

function Get-ProgressBar ([double]$percent, [int]$barWidth = 36) {
    $completedWidth = [math]::Floor(($percent / 100) * $barWidth)
    $remainingWidth = $barWidth - $completedWidth
    if ($completedWidth -lt 0) { $completedWidth = 0 }
    if ($remainingWidth -lt 0) { $remainingWidth = 0 }
    return ('#' * $completedWidth) + ('.' * $remainingWidth)
}

function Set-TelemetryCursor ([int]$left, [int]$top) {
    try {
        if (-not [Console]::IsOutputRedirected) {
            [Console]::CursorLeft = $left
            [Console]::CursorTop = $top
        }
    } catch {}
}

function Get-RemainingTimeStr ([DateTime]$lastPlayed, [bool]$isPinned) {
    if ($isPinned) {
        return " EM CAMPANHA (FIXADO - NUNCA EXPIRA)"
    }
    if (-not $config.cleanup_enabled) {
        return "RETENCAO DESATIVADA"
    }
    $expireTime = $lastPlayed.AddDays($retentionDays)
    $now = Get-Date
    $diff = $expireTime - $now

    if ($diff.TotalSeconds -le 0) {
        return "Expirando na proxima limpeza"
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
    if (-not $config.enable_cloud_save_sync -or -not $cloudSavesDir -or -not (Test-Path -LiteralPath $cloudSavesDir)) { return }
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
                    $result = Copy-CloudCartridgeSaveSafely -SourcePath $s.FullName -DestinationPath $destFile -DestinationRoot $cloudSavesDir
                    if ($result.status -ne 'unchanged') {
                        $syncedCount++
                        Write-Host "  -> Save sincronizado com versao protegida: $($s.Name)" -ForegroundColor Green
                    }
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
                Write-Host "  - $($d.Name) ($sMB MB)" -ForegroundColor Gray
            }
            Write-Host " Pre-baixando discos adicionais para evitar travamentos durante a campanha..." -ForegroundColor Cyan
            Write-Host "==========================================================================================" -ForegroundColor Magenta

            foreach ($d in $otherDiscs) {
                Write-Host "`n -> Pre-baixando: $($d.Name)..." -ForegroundColor Yellow
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -FilePath $d.FullName -LaunchAfter:$false -PrefetchOnly
            }
        }
    }
}

function Draw-InstalledGamesPanel {
    Write-Host "==========================================================================================" -ForegroundColor DarkCyan
    Write-Host " [PAINEL 2] JOGOS INSTALADOS NO PC & CONTAGEM REGRESSIVA (RETENCAO: $retentionDays DIAS)             " -ForegroundColor Yellow
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

                Write-Host " - " -NoNewline -ForegroundColor Green
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
        Write-Host " Nenhum jogo ocupando espaco local no momento. Sua biblioteca esta 100% na nuvem!" -ForegroundColor Gray
    } else {
        Write-Host "------------------------------------------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host " Total em disco: $([math]::Round($totalMB, 1)) MB em $installedCount jogo(s) instalados." -ForegroundColor Green
        Write-Host " *Jogos com estrela () estao em campanha e nunca sao apagados automaticamente." -ForegroundColor Cyan
        Write-Host " *Ao zerar o tempo, o espaco e liberado sem apagar nada da nuvem nem perder saves." -ForegroundColor DarkGray
    }
    Write-Host "==========================================================================================" -ForegroundColor DarkCyan
}

Clear-Host

if ($DashboardOnly -or [string]::IsNullOrWhiteSpace($FilePath)) {
    Write-Host "==========================================================================================" -ForegroundColor Cyan
    Write-Host "          DASHBOARD DE TELEMETRIA CLOUDCARTRIDGE - OpenSource Edition                     " -ForegroundColor Yellow
    Write-Host "==========================================================================================" -ForegroundColor Cyan
    Write-Host " Status Atual: Standby / Monitorando requisicoes de jogos..." -ForegroundColor Gray
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
$downloadJournal = Join-Path $baseDir '.download_jobs.json'
$catalogId = Get-CloudCartridgeCatalogIdForPath -Path $FilePath
$jobPriority = if ($PrefetchOnly) { 'prefetch' } else { 'current' }
$registration = Register-CloudCartridgeDownloadJob -JournalPath $downloadJournal -ManagedRoot $baseDir -FilePath $FilePath -CatalogId $catalogId -Priority $jobPriority
if ($registration.deduplicated) {
    Write-Host "[Fila] Download ja solicitado; aguardando job $($registration.job.job_id)." -ForegroundColor Gray
}
$downloadJobId = $registration.job.job_id
$ownsDownloadJob = $false
while (-not $ownsDownloadJob) {
    $currentJob = @(Get-CloudCartridgeDownloadJobs -JournalPath $downloadJournal | Where-Object { $_.job_id -eq $downloadJobId } | Select-Object -First 1)
    if ($currentJob.Count -eq 0) { throw "Job de download desapareceu: $downloadJobId" }
    if ($currentJob[0].state -eq 'completed') {
        Write-Host "[Fila] Download compartilhado concluido e validado." -ForegroundColor Green
        exit 0
    }
    if ($currentJob[0].state -eq 'failed') {
        throw "Download compartilhado falhou: $($currentJob[0].error)"
    }
    $ownsDownloadJob = Enter-CloudCartridgeDownloadJob -JournalPath $downloadJournal -JobId $downloadJobId -MaxConcurrent ([int]$config.max_concurrent_downloads)
    if ($ownsDownloadJob) { break }
    Start-Sleep -Milliseconds 250
}
$resumeBytes = if ($currentJob[0].bytes_downloaded) { [long]$currentJob[0].bytes_downloaded } else { 0 }
if ($resumeBytes -lt 0 -or $resumeBytes -ge $totalBytes) { $resumeBytes = 0 }
$null = Set-CloudCartridgeDownloadJobState -JournalPath $downloadJournal -JobId $downloadJobId -State active -BytesDownloaded $resumeBytes -TotalBytes $totalBytes

Write-Host "==========================================================================================" -ForegroundColor Cyan
Write-Host "                  TELEMETRIA CLOUDCARTRIDGE - DOWNLOAD EM TEMPO REAL                     " -ForegroundColor Yellow
Write-Host "==========================================================================================" -ForegroundColor Cyan
Write-Host " [PAINEL 1] ARQUIVO EM TRANSFERENCIA" -ForegroundColor Yellow
Write-Host " -----------------------------------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host " Plataforma : " -NoNewline -ForegroundColor Gray; Write-Host $platform -ForegroundColor White
Write-Host " Arquivo    : " -NoNewline -ForegroundColor Gray; Write-Host $fileName -ForegroundColor White
Write-Host " Tamanho    : " -NoNewline -ForegroundColor Gray; Write-Host "$totalMB MB" -ForegroundColor White
Write-Host " Origem     : " -NoNewline -ForegroundColor Gray; Write-Host "Google Drive (Nuvem)" -ForegroundColor Cyan
Write-Host " -----------------------------------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host " Progresso  : [Iniciando conexao de streaming...]" -ForegroundColor Yellow
Write-Host " Baixado    : 0 MB de $totalMB MB" -ForegroundColor Gray
Write-Host " Velocidade : 0 MB/s" -ForegroundColor Gray
Write-Host " Tempo      : 0s decorridos" -ForegroundColor Gray
Write-Host ""

Draw-InstalledGamesPanel

$buffer = New-Object byte[] (4 * 1024 * 1024)
$stream = $null
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$readTotal = $resumeBytes
$lastUpdate = [DateTime]::MinValue

try {
    $stream = [System.IO.File]::OpenRead($FilePath)
    if ($resumeBytes -gt 0) {
        $null = $stream.Seek($resumeBytes, [System.IO.SeekOrigin]::Begin)
    }

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

            Set-TelemetryCursor -left 0 -top 9
            Write-Host " Progresso  : " -NoNewline -ForegroundColor Gray
            Write-Host "[$bar] " -NoNewline -ForegroundColor Green
            Write-Host "$percent%     " -ForegroundColor Yellow

            Set-TelemetryCursor -left 0 -top 10
            Write-Host " Baixado    : " -NoNewline -ForegroundColor Gray
            Write-Host "$mbRead MB de $totalMB MB        " -ForegroundColor White

            Set-TelemetryCursor -left 0 -top 11
            Write-Host " Velocidade : " -NoNewline -ForegroundColor Gray
            Write-Host "$speed MB/s        " -ForegroundColor Cyan

            Set-TelemetryCursor -left 0 -top 12
            Write-Host " Tempo      : " -NoNewline -ForegroundColor Gray
            Write-Host "$([math]::Round($elapsedSec, 1))s decorridos | ETA restante: $($etaSec)s     " -ForegroundColor White
            $null = Set-CloudCartridgeDownloadJobState -JournalPath $downloadJournal -JobId $downloadJobId -State active -BytesDownloaded $readTotal -TotalBytes $totalBytes
        }
    }
} catch {
    $null = Set-CloudCartridgeDownloadJobState -JournalPath $downloadJournal -JobId $downloadJobId -State failed -BytesDownloaded $readTotal -TotalBytes $totalBytes -ErrorMessage $_.Exception.Message
    throw
} finally {
    if ($stream) { $stream.Close(); $stream.Dispose() }
    $stopwatch.Stop()
}
$contentSha256 = (Get-FileHash -LiteralPath $FilePath -Algorithm SHA256).Hash.ToLowerInvariant()

$reg = Get-RegistryData
if (-not $reg.PSObject.Properties['games']) {
    $reg | Add-Member -MemberType NoteProperty -Name 'games' -Value ([PSCustomObject]@{})
} elseif ($null -eq $reg.games) {
    $reg.games = [PSCustomObject]@{}
}
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
    sha256      = $contentSha256
}
if ($reg.games.PSObject.Properties[$cleanPath]) {
    $reg.games.$cleanPath = $entry
} else {
    $reg.games | Add-Member -MemberType NoteProperty -Name $cleanPath -Value $entry
}
Save-RegistryData $reg
$null = Set-CloudCartridgeDownloadJobState -JournalPath $downloadJournal -JobId $downloadJobId -State completed -BytesDownloaded $readTotal -TotalBytes $totalBytes -ContentSha256 $contentSha256

Set-TelemetryCursor -left 0 -top 13
Write-Host "`n [STATUS] DOWNLOAD 100% CONCLUIDO EM $([math]::Round($stopwatch.Elapsed.TotalSeconds, 1))s! O jogo esta pronto." -ForegroundColor Green
Start-Sleep -Seconds 1

if ($config.enable_multi_disc_prefetch -and -not $PrefetchOnly) {
    Check-And-PrefetchMultiDisc $FilePath
}

if ($PrefetchOnly) {
    exit 0
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
                    Write-Host "`n[Telemetria] Partida finalizada! Retencao ativa por $retentionDays dias." -ForegroundColor Green
                    Start-Sleep -Seconds 2
                    exit 0
                }
            }
        } catch {}
    }

    $coreMappingFile = Join-Path $scriptDir "core_mapping.json"
    $retroArchExe = $config.retroarch_path
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
    Write-Host "`n[Telemetria] Partida finalizada! Retencao ativa por $retentionDays dias." -ForegroundColor Green
    Start-Sleep -Seconds 2
}
if (-not $LaunchAfter) {
    # Modo Companheiro Ativo: Janela permanece aberta durante a partida
    Write-Host "`n==========================================================================================" -ForegroundColor DarkCyan
    Write-Host "  [HUD COMPANHEIRO ATIVO] Jogo em execucao no emulador." -ForegroundColor Cyan
    Write-Host "  Esta janela de telemetria permanecera aberta durante toda a sua partida." -ForegroundColor Gray
    Write-Host "  Ao encerrar o jogo, seus saves serao enviados para a nuvem automaticamente!" -ForegroundColor Yellow
    Write-Host "==========================================================================================" -ForegroundColor DarkCyan

    $allEmuProcs = @('retroarch', 'pcsx2-qt', 'Dolphin', 'Cemu', 'rpcs3', 'citra-qt', 'duckstation-qt-x64-ReleaseLTCG')
    while ($true) {
        $activeEmu = Get-Process -Name $allEmuProcs -ErrorAction SilentlyContinue
        if (-not $activeEmu) {
            break
        }
        Start-Sleep -Seconds 2
    }

    Sync-CloudSaves $FilePath
    Write-Host "`n[Telemetria] Partida finalizada! Saves sincronizados e retencao renovada por $retentionDays dias." -ForegroundColor Green
    Write-Host "Esta janela fechara em 5 segundos..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 5
}
