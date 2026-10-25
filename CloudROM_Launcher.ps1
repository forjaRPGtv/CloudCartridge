# ==============================================================================
# CloudROM Launcher & Cache Manager - Open-Source Edition
# Arthur Reis Projetos
# ==============================================================================

[CmdletBinding()]
param (
    [string]$GamePath = '',
    [switch]$PurgeOnly = $false
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
$gDrivePath = if ($config -and $config.google_drive_roms_path) { $config.google_drive_roms_path } else { '' }
$cloudSavesDir = if ($gDrivePath) { Join-Path $gDrivePath '_RA_SAVES' } else { '' }
$retentionDays = if ($config -and $config.retention_days) { [int]$config.retention_days } else { 3 }
$registryFile = Join-Path $baseDir '.cache_registry.json'
$coreMappingFile = Join-Path $scriptDir "core_mapping.json"
$standaloneFile = Join-Path $scriptDir "standalone_emulators.json"
$telemetryScript = Join-Path $scriptDir "CloudROM_Telemetry.ps1"
$retroArchExe = if ($config -and $config.retroarch_path) { $config.retroarch_path } else { 'C:\RetroArch-Win64\retroarch.exe' }

$coreMapping = @{}
if (Test-Path -LiteralPath $coreMappingFile) {
    try { $coreMapping = Get-Content -LiteralPath $coreMappingFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
}

$standaloneMapping = @{}
if (Test-Path -LiteralPath $standaloneFile) {
    try { $standaloneMapping = Get-Content -LiteralPath $standaloneFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
}

function Get-CacheRegistry {
    if (Test-Path -LiteralPath $registryFile) {
        try { return Get-Content -LiteralPath $registryFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
    }
    return [PSCustomObject]@{ retention_days = $retentionDays; games = @{} }
}

function Save-CacheRegistry ($reg) {
    try { $reg | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $registryFile -Encoding UTF8 } catch {}
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

function Invoke-CachePurge {
    Write-Host "`n[Auto-Purge] Verificando jogos com mais de $retentionDays dias sem uso..." -ForegroundColor Cyan
    $reg = Get-CacheRegistry
    $now = Get-Date
    $purgedCount = 0
    $freedMB = 0

    if ($reg.games) {
        $keys = @($reg.games.PSObject.Properties.Name)
        foreach ($key in $keys) {
            $item = $reg.games.$key
            if (-not $item.last_played) { continue }

            if ($item.is_pinned -eq $true) {
                Write-Host "  ⭐ Jogo em campanha (protegido): $($item.title)" -ForegroundColor Green
                continue
            }

            $lastPlayed = [DateTime]$item.last_played
            $diff = $now - $lastPlayed

            if ($diff.TotalDays -ge $retentionDays) {
                $targetFile = $key
                if (Test-Path -LiteralPath $targetFile) {
                    try {
                        $p = Start-Process -FilePath "attrib.exe" -ArgumentList "+u", "-p", "`"$targetFile`"" -NoNewWindow -Wait -PassThru
                        if ($p.ExitCode -eq 0) {
                            $size = if ($item.size_mb) { [double]$item.size_mb } else { 0 }
                            $freedMB += $size
                            $purgedCount++
                            Write-Host "  -> Espaço liberado no PC: $($item.title) ($($diff.Days) dias sem jogar)" -ForegroundColor Yellow
                        }
                    } catch {}
                }
                $item.status = "cloud_only"
            }
        }
    }

    Save-CacheRegistry $reg
    if ($purgedCount -gt 0) {
        Write-Host "[Auto-Purge] Limpeza concluída: $purgedCount jogo(s) liberados (~$([math]::Round($freedMB, 1)) MB economizados).`n" -ForegroundColor Green
    } else {
        Write-Host "[Auto-Purge] Nenhum jogo expirado no momento. Cache 100% otimizado.`n" -ForegroundColor Gray
    }
}

function Hydrate-GameFile ([string]$filePath) {
    if (-not (Test-Path -LiteralPath $filePath)) {
        throw "Arquivo não encontrado: $filePath"
    }

    if (Test-Path -LiteralPath $telemetryScript) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $telemetryScript -FilePath $filePath -LaunchAfter:$false
    }
}

function Start-GameWithEmulator ([string]$filePath) {
    $platform = Split-Path (Split-Path $filePath -Parent) -Leaf
    Write-Host "`n[Launcher] Inicializando $platform..." -ForegroundColor Cyan

    if ($standaloneMapping.PSObject.Properties[$platform]) {
        $emu = $standaloneMapping.$platform
        if (Test-Path -LiteralPath $emu.Executable) {
            Write-Host "Emulador Standalone Detectado: $($emu.EmulatorName)" -ForegroundColor Green
            Write-Host "Executando partida... (o terminal retornará ao fechar o jogo)" -ForegroundColor Yellow

            $argsFormatted = $emu.Arguments.Replace('{ROM}', $filePath)
            $proc = Start-Process -FilePath $emu.Executable -ArgumentList $argsFormatted -Wait -PassThru

            Sync-CloudSaves $filePath
            Write-Host "`n[CloudROM] Partida encerrada! Retenção ativa por $retentionDays dias." -ForegroundColor Green
            return
        }
    }

    $coreInfo = if ($coreMapping.PSObject.Properties[$platform]) { $coreMapping.$platform } else { $null }

    if ($coreInfo -and (Test-Path -LiteralPath $coreInfo.CorePath) -and (Test-Path -LiteralPath $retroArchExe)) {
        Write-Host "Emulador: RetroArch" -ForegroundColor Green
        Write-Host "Core: $($coreInfo.CoreName)" -ForegroundColor Gray
        Write-Host "Executando partida... (o terminal retornará ao fechar o jogo)" -ForegroundColor Yellow

        $proc = Start-Process -FilePath $retroArchExe -ArgumentList "-L", "`"$($coreInfo.CorePath)`"", "`"$filePath`"" -Wait -PassThru
    } else {
        Write-Host "Iniciando com o aplicativo padrão do sistema..." -ForegroundColor Yellow
        $proc = Start-Process -FilePath $filePath -Wait -PassThru
    }

    Sync-CloudSaves $filePath
    Write-Host "`n[CloudROM] Partida encerrada! Retenção ativa por $retentionDays dias." -ForegroundColor Green
}

if ($PurgeOnly) {
    Invoke-CachePurge
    exit 0
}

if ($GamePath) {
    Invoke-CachePurge
    Hydrate-GameFile $GamePath
    Start-GameWithEmulator $GamePath
    exit 0
}

function Show-MainMenu {
    Clear-Host
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host "       CloudROM Manager PRO - Jogos na Nuvem & Telemetria        " -ForegroundColor Yellow
    Write-Host "                  Open-Source Edition                            " -ForegroundColor Gray
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host " [1] Buscar Jogo por Nome (Pesquisa Rápida em todos os consoles)" -ForegroundColor White
    Write-Host " [2] Navegar por Console / Plataforma" -ForegroundColor White
    Write-Host " [3] Ver Jogos em Cache & Prazos (Abrir Dashboard de Telemetria)" -ForegroundColor White
    Write-Host " [4] ⭐ Fixar / Desafixar Jogo em Campanha (Nunca expirar)" -ForegroundColor Yellow
    Write-Host " [5] Limpar Cache Agora (Liberar espaço de jogos > $retentionDays dias)" -ForegroundColor White
    Write-Host " [0] Sair" -ForegroundColor Gray
    Write-Host "=================================================================" -ForegroundColor Cyan
    
    $choice = Read-Host "Escolha uma opção"
    return $choice
}

Invoke-CachePurge

while ($true) {
    $option = Show-MainMenu
    switch ($option) {
        '1' {
            $query = Read-Host "`nDigite parte do nome do jogo (ex: mario, crash, sonic, zelda)"
            if (-not [string]::IsNullOrWhiteSpace($query)) {
                Write-Host "`nBuscando jogos..." -ForegroundColor Gray
                $found = Get-ChildItem -LiteralPath $baseDir -Recurse -File -Filter "*$query*" -ErrorAction SilentlyContinue |
                    Where-Object { $_.DirectoryName -notlike '*_RA_*' -and $_.DirectoryName -notlike '*_INSTALLERS*' -and $_.DirectoryName -notlike '*cheats*' } |
                    Select-Object -First 30

                if (-not $found -or $found.Count -eq 0) {
                    Write-Host "Nenhum jogo encontrado com o termo '$query'." -ForegroundColor Red
                    Start-Sleep -Seconds 2
                } else {
                    Write-Host "`nJogos encontrados:" -ForegroundColor Green
                    for ($i = 0; $i -lt $found.Count; $i++) {
                        $item = $found[$i]
                        $plat = Split-Path $item.DirectoryName -Leaf
                        $sizeMB = [math]::Round($item.Length / 1MB, 1)
                        Write-Host " [$($i + 1)] [$plat] $($item.BaseName) ($sizeMB MB)" -ForegroundColor White
                    }
                    Write-Host " [0] Cancelar" -ForegroundColor Gray

                    $pick = Read-Host "`nEscolha o número do jogo para jogar"
                    $pickIdx = [int]$pick - 1
                    if ($pickIdx -ge 0 -and $pickIdx -lt $found.Count) {
                        $selectedGame = $found[$pickIdx].FullName
                        Hydrate-GameFile $selectedGame
                        Start-GameWithEmulator $selectedGame
                        Write-Host "`nPressione qualquer tecla para continuar..." -ForegroundColor Gray
                        [void][System.Console]::ReadKey($true)
                    }
                }
            }
        }
        '2' {
            Write-Host "`nConsoles Disponíveis:" -ForegroundColor Cyan
            $platforms = Get-ChildItem -LiteralPath $baseDir -Directory |
                Where-Object { $_.Name -notlike '_RA_*' -and $_.Name -notlike '_*' -and $_.Name -ne 'cheats' -and $_.Name -ne 'Arcade' -and $_.Name -ne 'Vectrex' -and $_.Name -ne 'Jaguar' } |
                Sort-Object Name

            for ($i = 0; $i -lt $platforms.Count; $i++) {
                Write-Host " [$($i + 1)] $($platforms[$i].Name)" -ForegroundColor White
            }
            Write-Host " [0] Voltar" -ForegroundColor Gray

            $pickPlat = Read-Host "`nEscolha o console"
            $platIdx = [int]$pickPlat - 1
            if ($platIdx -ge 0 -and $platIdx -lt $platforms.Count) {
                $targetPlatDir = $platforms[$platIdx].FullName
                $platName = $platforms[$platIdx].Name
                Write-Host "`nCarregando jogos de $platName..." -ForegroundColor Gray

                $games = Get-ChildItem -LiteralPath $targetPlatDir -File | Sort-Object Name | Select-Object -First 50
                if (-not $games -or $games.Count -eq 0) {
                    Write-Host "Nenhum jogo encontrado nesta pasta." -ForegroundColor Yellow
                    Start-Sleep -Seconds 2
                } else {
                    for ($j = 0; $j -lt $games.Count; $j++) {
                        $g = $games[$j]
                        $sMB = [math]::Round($g.Length / 1MB, 1)
                        Write-Host " [$($j + 1)] $($g.BaseName) ($sMB MB)" -ForegroundColor White
                    }
                    Write-Host " [0] Cancelar" -ForegroundColor Gray

                    $pickGame = Read-Host "`nEscolha o jogo para jogar"
                    $gIdx = [int]$pickGame - 1
                    if ($gIdx -ge 0 -and $gIdx -lt $games.Count) {
                        $selectedGame = $games[$gIdx].FullName
                        Hydrate-GameFile $selectedGame
                        Start-GameWithEmulator $selectedGame
                        Write-Host "`nPressione qualquer tecla para continuar..." -ForegroundColor Gray
                        [void][System.Console]::ReadKey($true)
                    }
                }
            }
        }
        '3' {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $telemetryScript -DashboardOnly
        }
        '4' {
            Write-Host "`n=== FIXAR / DESAFIXAR JOGO EM CAMPANHA (⭐ NUNCA EXPIRA) ===" -ForegroundColor Yellow
            $reg = Get-CacheRegistry
            if (-not $reg.games -or $reg.games.PSObject.Properties.Count -eq 0) {
                Write-Host "Nenhum jogo em cache local no momento." -ForegroundColor Gray
                Start-Sleep -Seconds 2
            } else {
                $keys = @($reg.games.PSObject.Properties.Name)
                $activeList = @()
                for ($k = 0; $k -lt $keys.Count; $k++) {
                    $item = $reg.games.($keys[$k])
                    if ($item.status -eq 'local_cached') {
                        $activeList += [PSCustomObject]@{ Key = $keys[$k]; Title = $item.title; Pinned = [bool]$item.is_pinned; System = $item.system }
                    }
                }

                if ($activeList.Count -eq 0) {
                    Write-Host "Nenhum jogo baixado no momento." -ForegroundColor Gray
                    Start-Sleep -Seconds 2
                } else {
                    for ($m = 0; $m -lt $activeList.Count; $m++) {
                        $act = $activeList[$m]
                        $star = if ($act.Pinned) { "⭐ [FIXADO]" } else { "   [NORMAL]" }
                        Write-Host " [$($m + 1)] $star [$($act.System)] $($act.Title)" -ForegroundColor White
                    }
                    Write-Host " [0] Cancelar" -ForegroundColor Gray

                    $togglePick = Read-Host "`nEscolha o número do jogo para alternar o status de campanha"
                    $tIdx = [int]$togglePick - 1
                    if ($tIdx -ge 0 -and $tIdx -lt $activeList.Count) {
                        $targetKey = $activeList[$tIdx].Key
                        $currentPin = [bool]$reg.games.$targetKey.is_pinned
                        $reg.games.$targetKey.is_pinned = (-not $currentPin)
                        Save-CacheRegistry $reg
                        $newStatus = if (-not $currentPin) { "⭐ FIXADO EM CAMPANHA (NUNCA EXPIRA)" } else { "NORMAL (Expira em $retentionDays dias)" }
                        Write-Host "`nStatus atualizado: $newStatus!" -ForegroundColor Green
                        Start-Sleep -Seconds 2
                    }
                }
            }
        }
        '5' {
            Invoke-CachePurge
            Write-Host "Pressione qualquer tecla para voltar..." -ForegroundColor Gray
            [void][System.Console]::ReadKey($true)
        }
        '0' {
            Write-Host "`nAté logo!" -ForegroundColor Green
            exit 0
        }
    }
}
