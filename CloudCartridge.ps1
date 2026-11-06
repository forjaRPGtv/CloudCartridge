[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Command = 'status',
    [Parameter(Position = 1, ValueFromRemainingArguments = $true)][string[]]$Arguments
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
Import-Module (Join-Path $scriptDir 'CloudCartridge.Core.psm1') -Force

$jsonOutput = $Arguments -contains '--json'
$filteredArguments = @($Arguments | Where-Object { $_ -ne '--json' -and $_ -ne '--refresh' -and $_ -ne '--available' })
$configPath = Join-Path $scriptDir 'config.json'
$config = Get-CloudCartridgeConfig -ConfigPath $configPath

function Get-CacheSummary {
    $registryPath = Join-Path $config.local_roms_path '.cache_registry.json'
    $summary = [ordered]@{
        registry_path = $registryPath
        registry_exists = Test-Path -LiteralPath $registryPath -PathType Leaf
        total = 0
        local_cached = 0
        cloud_only = 0
        pinned = 0
        error = $null
    }
    if ($summary.registry_exists) {
        try {
            $registry = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $entries = if ($registry.games) { @($registry.games.PSObject.Properties) } else { @() }
            $summary.total = $entries.Count
            $summary.local_cached = @($entries | Where-Object { $_.Value.status -eq 'local_cached' }).Count
            $summary.cloud_only = @($entries | Where-Object { $_.Value.status -eq 'cloud_only' }).Count
            $summary.pinned = @($entries | Where-Object { $_.Value.is_pinned -eq $true }).Count
        } catch {
            $summary.error = $_.Exception.Message
        }
    }
    return [PSCustomObject]$summary
}

function Get-CoreInventory {
    $mappingPath = Join-Path $scriptDir 'core_mapping.json'
    $items = @()
    if (Test-Path -LiteralPath $mappingPath -PathType Leaf) {
        $mapping = Get-Content -LiteralPath $mappingPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($property in @($mapping.PSObject.Properties)) {
            $path = [string]$property.Value.CorePath
            $state = if ($path -eq 'DETECT') { 'not_configured' } elseif (Test-Path -LiteralPath $path -PathType Leaf) { 'detected' } else { 'not_installed' }
            $items += [PSCustomObject]@{
                system = $property.Name
                core_name = $property.Value.CoreName
                core_path = $path
                state = $state
            }
        }
    }
    return $items
}

function Get-EmulatorInventory {
    $actualPath = Join-Path $scriptDir 'standalone_emulators.json'
    $templatePath = Join-Path $scriptDir 'standalone_emulators.template.json'
    $sourcePath = if (Test-Path -LiteralPath $actualPath -PathType Leaf) { $actualPath } else { $templatePath }
    $items = @()
    if (Test-Path -LiteralPath $sourcePath -PathType Leaf) {
        $mapping = Get-Content -LiteralPath $sourcePath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($property in @($mapping.PSObject.Properties)) {
            $exe = [string]$property.Value.Executable
            $items += [PSCustomObject]@{
                system = $property.Name
                emulator = $property.Value.EmulatorName
                executable = $exe
                version = if (Test-Path -LiteralPath $exe -PathType Leaf) { (Get-Item -LiteralPath $exe).VersionInfo.FileVersion } else { $null }
                state = if (Test-Path -LiteralPath $exe -PathType Leaf) { 'detected' } else { 'not_installed' }
                source = if ($sourcePath -eq $actualPath) { 'configured' } else { 'template' }
            }
        }
    }
    return $items
}

function Get-DoctorReport {
    $cores = @(Get-CoreInventory)
    $emulators = @(Get-EmulatorInventory)
    $cache = Get-CacheSummary
    $issues = @()
    if (-not (Test-Path -LiteralPath $config.local_roms_path -PathType Container)) { $issues += 'library_root_missing' }
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { $issues += 'config_missing_using_defaults' }
    if (-not (Test-Path -LiteralPath $config.retroarch_path -PathType Leaf)) { $issues += 'retroarch_missing' }
    if ($config.enable_cloud_save_sync -and [string]::IsNullOrWhiteSpace([string]$config.google_drive_roms_path)) { $issues += 'cloud_save_destination_unconfigured' }
    if ($cache.error) { $issues += 'cache_registry_invalid' }
    if (@($cores | Where-Object { $_.state -eq 'not_installed' }).Count -gt 0) { $issues += 'mapped_cores_missing' }
    if (@($cores | Where-Object { $_.state -eq 'not_configured' }).Count -gt 0) { $issues += 'core_mapping_not_configured' }

    return [PSCustomObject][ordered]@{
        schema_version = 1
        status = if ($issues.Count -eq 0) { 'ok' } else { 'warning' }
        config = [PSCustomObject]@{
            path = $configPath
            exists = Test-Path -LiteralPath $configPath -PathType Leaf
            retention_days = $config.retention_days
            cleanup_enabled = [bool]$config.cleanup_enabled
            cloud_save_sync = [bool]$config.enable_cloud_save_sync
            multi_disc_prefetch = [bool]$config.enable_multi_disc_prefetch
        }
        library = [PSCustomObject]@{
            path = $config.local_roms_path
            exists = Test-Path -LiteralPath $config.local_roms_path -PathType Container
        }
        retroarch = [PSCustomObject]@{
            path = $config.retroarch_path
            version = if (Test-Path -LiteralPath $config.retroarch_path -PathType Leaf) { (Get-Item -LiteralPath $config.retroarch_path).VersionInfo.FileVersion } else { $null }
            state = if (Test-Path -LiteralPath $config.retroarch_path -PathType Leaf) { 'detected' } else { 'not_installed' }
        }
        cores = [PSCustomObject]@{
            total = $cores.Count
            detected = @($cores | Where-Object { $_.state -eq 'detected' }).Count
            missing = @($cores | Where-Object { $_.state -eq 'not_installed' }).Count
            not_configured = @($cores | Where-Object { $_.state -eq 'not_configured' }).Count
        }
        emulators = [PSCustomObject]@{
            mappings = $emulators.Count
            detected_mappings = @($emulators | Where-Object { $_.state -eq 'detected' }).Count
            unique_detected = @($emulators | Where-Object { $_.state -eq 'detected' } | Select-Object -ExpandProperty executable -Unique).Count
            missing = @($emulators | Where-Object { $_.state -eq 'not_installed' }).Count
        }
        cache = $cache
        issues = $issues
    }
}

function Write-Result {
    param($Value)
    if ($jsonOutput) {
        $Value | ConvertTo-Json -Depth 8 -Compress
    } elseif ($Value -is [System.Array]) {
        $Value | Format-Table -AutoSize
    } else {
        $Value | Format-List
    }
}

switch ($Command.ToLowerInvariant()) {
    'status' {
        $report = Get-DoctorReport
        Write-Result ([PSCustomObject][ordered]@{
            status = $report.status
            retroarch = $report.retroarch.state
            cores = "$($report.cores.detected)/$($report.cores.total)"
            emulators = "$($report.emulators.detected_mappings)/$($report.emulators.mappings)"
            cache_local = $report.cache.local_cached
            issues = $report.issues
        })
    }
    'doctor' { Write-Result (Get-DoctorReport) }
    'detect' {
        Write-Result ([PSCustomObject][ordered]@{
            emulators = @(Get-EmulatorInventory)
            cores = @(Get-CoreInventory)
        })
    }
    'emulators' {
        if ($filteredArguments.Count -gt 0 -and $filteredArguments[0] -ne 'list') { throw 'Use: cloudcartridge emulators list [--json]' }
        Write-Result @(Get-EmulatorInventory)
    }
    'cores' {
        if ($filteredArguments.Count -gt 0 -and $filteredArguments[0] -ne 'list') { throw 'Use: cloudcartridge cores list [--available] [--json]' }
        $cores = @(Get-CoreInventory)
        if ($Arguments -contains '--available') { $cores = @($cores | Where-Object { $_.state -eq 'detected' }) }
        Write-Result $cores
    }
    'cache' {
        if ($filteredArguments.Count -gt 0 -and $filteredArguments[0] -ne 'status') { throw 'Use: cloudcartridge cache status [--json]' }
        Write-Result (Get-CacheSummary)
    }
    default {
        throw "Comando desconhecido: $Command. Use status, doctor, detect, emulators, cores ou cache."
    }
}
