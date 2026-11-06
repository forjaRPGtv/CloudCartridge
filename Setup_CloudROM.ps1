[CmdletBinding()]
param(
    [string]$GoogleDrivePath,
    [string]$LocalRomsPath,
    [string]$RetroArchPath,
    [switch]$CreateJunctions,
    [switch]$RegisterContextMenu,
    [switch]$NonInteractive,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$scriptDir = $PSScriptRoot
Import-Module (Join-Path $scriptDir 'CloudCartridge.Core.psm1') -Force
$configPath = Join-Path $scriptDir 'config.json'

if (-not $NonInteractive) {
    Write-Host 'CloudCartridge - configuracao segura' -ForegroundColor Cyan
    if (-not $GoogleDrivePath) { $GoogleDrivePath = Read-Host 'Pasta de ROMs no Google Drive (pode ficar vazia)' }
    if (-not $LocalRomsPath) { $LocalRomsPath = Read-Host 'Pasta local gerenciada (ex.: Z:\_ISOS_ROMS_)' }
    if (-not $RetroArchPath) { $RetroArchPath = Read-Host 'Caminho do retroarch.exe (pode ficar ausente)' }
    if (-not $CreateJunctions -and $GoogleDrivePath) {
        $CreateJunctions = (Read-Host 'Planejar juncoes para as pastas da biblioteca? [s/N]') -match '^(s|sim|y|yes)$'
    }
    if (-not $RegisterContextMenu) {
        $RegisterContextMenu = (Read-Host 'Registrar menu de contexto do Explorer? [s/N]') -match '^(s|sim|y|yes)$'
    }
}

if ([string]::IsNullOrWhiteSpace($LocalRomsPath)) { throw 'LocalRomsPath e obrigatorio.' }
$LocalRomsPath = [System.IO.Path]::GetFullPath($LocalRomsPath)
if ($GoogleDrivePath) { $GoogleDrivePath = [System.IO.Path]::GetFullPath($GoogleDrivePath) }
if ($RetroArchPath) { $RetroArchPath = [System.IO.Path]::GetFullPath($RetroArchPath) }

$junctionPlan = @()
if ($CreateJunctions -and $GoogleDrivePath -and (Test-Path -LiteralPath $GoogleDrivePath -PathType Container)) {
    foreach ($source in Get-ChildItem -LiteralPath $GoogleDrivePath -Directory) {
        if ($source.Name -like '_RA_*' -or $source.Name -like '_INSTALLERS*' -or $source.Name -eq 'cheats') { continue }
        $destination = Join-Path $LocalRomsPath $source.Name
        $junctionPlan += [PSCustomObject]@{ source = $source.FullName; destination = $destination; action = if (Test-Path -LiteralPath $destination) { 'preserve_existing' } else { 'create_junction' } }
    }
}

$plan = [PSCustomObject][ordered]@{
    applied = $false
    dry_run = -not $Apply
    config_path = $configPath
    config_exists = Test-Path -LiteralPath $configPath -PathType Leaf
    google_drive_path = $GoogleDrivePath
    local_roms_path = $LocalRomsPath
    retroarch_path = $RetroArchPath
    create_junctions = [bool]$CreateJunctions
    register_context_menu = [bool]$RegisterContextMenu
    junctions = $junctionPlan
    backup_path = $null
}

if (-not $Apply -and -not $NonInteractive) {
    $plan | Format-List
    $confirmation = Read-Host 'Aplicar este plano? Digite APLICAR'
    if ($confirmation -eq 'APLICAR') { $Apply = $true; $plan.dry_run = $false }
}
if (-not $Apply) { $plan | ConvertTo-Json -Depth 8; exit 0 }

if ($plan.config_exists) {
    $backupRoot = Join-Path $scriptDir 'backups\config'
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $backupPath = Join-Path $backupRoot ("config-{0}.json" -f [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'))
    Copy-Item -LiteralPath $configPath -Destination $backupPath
    $plan.backup_path = $backupPath
}
if (-not (Test-Path -LiteralPath $LocalRomsPath -PathType Container)) { New-Item -ItemType Directory -Path $LocalRomsPath -Force | Out-Null }
$values = @{ local_roms_path = $LocalRomsPath; google_drive_roms_path = $GoogleDrivePath; retroarch_path = $RetroArchPath }
$null = Update-CloudCartridgeConfig -ConfigPath $configPath -Values $values

foreach ($row in @($junctionPlan | Where-Object { $_.action -eq 'create_junction' })) {
    if (-not (Test-CloudCartridgePathWithinRoot -Path $row.destination -Root $LocalRomsPath)) { throw 'Destino de juncao fora da raiz local.' }
    New-Item -ItemType Junction -Path $row.destination -Target $row.source | Out-Null
}
if ($RegisterContextMenu) {
    $contextScript = Join-Path $scriptDir 'setup_context_menu.ps1'
    if (-not (Test-Path -LiteralPath $contextScript -PathType Leaf)) { throw 'Script de menu de contexto ausente.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $contextScript
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao registrar menu de contexto.' }
}
$plan.applied = $true
$plan | ConvertTo-Json -Depth 8
