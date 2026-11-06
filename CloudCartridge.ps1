[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Command = 'status',
    [Parameter(Position = 1, ValueFromRemainingArguments = $true)][string[]]$Arguments
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
Import-Module (Join-Path $scriptDir 'CloudCartridge.Core.psm1') -Force
Import-Module (Join-Path $scriptDir 'CloudCartridge.SaveGuardian.psm1') -Force
Import-Module (Join-Path $scriptDir 'CloudCartridge.Playlists.psm1') -Force

$jsonOutput = $Arguments -contains '--json'
$confirmed = $Arguments -contains '--yes'
$filteredArguments = @($Arguments | Where-Object { $_ -notin @('--json', '--refresh', '--available', '--dry-run', '--yes') })
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

function Get-DownloadSummary {
    $journalPath = Join-Path $config.local_roms_path '.download_jobs.json'
    $jobs = @(Get-CloudCartridgeDownloadJobs -JournalPath $journalPath)
    return [PSCustomObject][ordered]@{
        journal_path = $journalPath
        queued = @($jobs | Where-Object { $_.state -eq 'queued' }).Count
        active = @($jobs | Where-Object { $_.state -eq 'active' }).Count
        completed = @($jobs | Where-Object { $_.state -eq 'completed' }).Count
        failed = @($jobs | Where-Object { $_.state -eq 'failed' }).Count
        jobs = $jobs
    }
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
    $downloads = Get-DownloadSummary
    $issues = @()
    if (-not (Test-Path -LiteralPath $config.local_roms_path -PathType Container)) { $issues += 'library_root_missing' }
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { $issues += 'config_missing_using_defaults' }
    $retroArchDetection = Find-CloudCartridgeExecutable -CandidatePaths @(
        $config.retroarch_path,
        (Join-Path $scriptDir 'RetroArch\retroarch.exe'),
        (Join-Path (Split-Path $scriptDir -Parent) 'RetroArch\retroarch.exe'),
        'C:\RetroArch-Win64\retroarch.exe'
    ) -CommandNames @('retroarch.exe')
    if ($retroArchDetection.state -ne 'detected') { $issues += 'retroarch_missing' }
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
            configured_path = $config.retroarch_path
            path = $retroArchDetection.path
            source = $retroArchDetection.source
            version = if ($retroArchDetection.path) { (Get-Item -LiteralPath $retroArchDetection.path).VersionInfo.FileVersion } else { $null }
            state = $retroArchDetection.state
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
        downloads = [PSCustomObject]@{
            queued = $downloads.queued
            active = $downloads.active
            completed = $downloads.completed
            failed = $downloads.failed
        }
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

function Get-ArgumentValue {
    param([string]$Name)
    for ($index = 0; $index -lt $Arguments.Count; $index++) {
        if ($Arguments[$index] -eq $Name -and $index + 1 -lt $Arguments.Count) {
            return $Arguments[$index + 1]
        }
    }
    return $null
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
            downloads_active = $report.downloads.active
            downloads_queued = $report.downloads.queued
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
        $subcommand = if ($filteredArguments.Count -gt 0) { $filteredArguments[0] } else { 'status' }
        switch ($subcommand) {
            'status' { Write-Result (Get-CacheSummary) }
            'policy' {
                $retentionValue = Get-ArgumentValue '--retention-days'
                if ([string]::IsNullOrWhiteSpace($retentionValue)) {
                    throw 'Use: cloudcartridge cache policy --retention-days 3|7|14|30|off [--dry-run|--yes]'
                }
                if ($retentionValue -eq 'off') {
                    $values = @{ retention_days = $null; cleanup_enabled = $false }
                } else {
                    $retentionNumber = 0
                    if (-not [int]::TryParse($retentionValue, [ref]$retentionNumber) -or $retentionNumber -notin @(3, 7, 14, 30)) {
                        throw 'retention-days deve ser 3, 7, 14, 30 ou off.'
                    }
                    $values = @{ retention_days = $retentionNumber; cleanup_enabled = $true }
                }
                $previewOnly = -not $confirmed
                $updated = Update-CloudCartridgeConfig -ConfigPath $configPath -Values $values -DryRun:$previewOnly
                Write-Result ([PSCustomObject][ordered]@{
                    applied = -not $previewOnly
                    dry_run = $previewOnly
                    retention_days = $updated.retention_days
                    cleanup_enabled = [bool]$updated.cleanup_enabled
                    config_path = $configPath
                })
            }
            'pin' {
                if ($filteredArguments.Count -lt 2) { throw 'Use: cloudcartridge cache pin <caminho-ou-catalog_id> [--dry-run|--yes]' }
                $registryPath = Join-Path $config.local_roms_path '.cache_registry.json'
                $result = Set-CloudCartridgeCachePin -RegistryPath $registryPath -ManagedRoot $config.local_roms_path -Identifier $filteredArguments[1] -Pinned $true -DryRun:(-not $confirmed)
                Write-Result $result
            }
            'unpin' {
                if ($filteredArguments.Count -lt 2) { throw 'Use: cloudcartridge cache unpin <caminho-ou-catalog_id> [--dry-run|--yes]' }
                $registryPath = Join-Path $config.local_roms_path '.cache_registry.json'
                $result = Set-CloudCartridgeCachePin -RegistryPath $registryPath -ManagedRoot $config.local_roms_path -Identifier $filteredArguments[1] -Pinned $false -DryRun:(-not $confirmed)
                Write-Result $result
            }
            'cleanup' {
                $registryPath = Join-Path $config.local_roms_path '.cache_registry.json'
                $previewOnly = -not $confirmed
                $results = @(Invoke-CloudCartridgeCacheCleanup `
                    -RegistryPath $registryPath `
                    -ManagedRoot $config.local_roms_path `
                    -RetentionDays $config.retention_days `
                    -CleanupEnabled ([bool]$config.cleanup_enabled) `
                    -DryRun:$previewOnly)
                Write-Result ([PSCustomObject][ordered]@{
                    applied = -not $previewOnly
                    dry_run = $previewOnly
                    retention_days = $config.retention_days
                    cleanup_enabled = [bool]$config.cleanup_enabled
                    candidates = @($results | Where-Object { $_.decision -eq 'dehydrate' }).Count
                    dehydrated = @($results | Where-Object { $_.decision -eq 'dehydrated' }).Count
                    failed = @($results | Where-Object { $_.decision -eq 'failed' }).Count
                    results = $results
                })
            }
            default { throw 'Use: cloudcartridge cache status|policy|pin|unpin|cleanup [opcoes]' }
        }
    }
    'downloads' {
        $subcommand = if ($filteredArguments.Count -gt 0) { $filteredArguments[0] } else { 'list' }
        if ($subcommand -ne 'list') { throw 'Use: cloudcartridge downloads list [--json]' }
        Write-Result (Get-DownloadSummary)
    }
    'save' {
        $subcommand = if ($filteredArguments.Count -gt 0) { $filteredArguments[0] } else { 'doctor' }
        switch ($subcommand) {
            'doctor' {
                $gameName = Get-ArgumentValue '--game-name'
                if ([string]::IsNullOrWhiteSpace($gameName)) { throw 'Use: cloudcartridge save doctor --game-name <nome> [--current-dir <pasta>] [--legacy-dir <pasta>] [--retroarch-config <arquivo>] [--json]' }
                $currentDirectory = Get-ArgumentValue '--current-dir'
                $legacyDirectory = Get-ArgumentValue '--legacy-dir'
                $retroArchConfig = Get-ArgumentValue '--retroarch-config'
                if ([string]::IsNullOrWhiteSpace($retroArchConfig)) {
                    $retroArchConfig = if (Test-Path -LiteralPath 'C:\RetroArch-Win64\retroarch.cfg' -PathType Leaf) { 'C:\RetroArch-Win64\retroarch.cfg' } else { $null }
                }
                $settings = if ($retroArchConfig) { Read-CloudCartridgeRetroArchSaveSettings -ConfigPaths @($retroArchConfig) } else { $null }
                if ([string]::IsNullOrWhiteSpace($currentDirectory) -and $settings) { $currentDirectory = $settings.savefile_directory }
                if ([string]::IsNullOrWhiteSpace($currentDirectory)) { throw 'Diretorio atual de saves nao resolvido; informe --current-dir.' }
                $report = Find-CloudCartridgeSaveCandidates -GameName $gameName -CurrentDirectories @($currentDirectory) -LegacyDirectories @($legacyDirectory | Where-Object { $_ })
                Write-Result ([PSCustomObject][ordered]@{
                    status = $report.status
                    path_changed = $report.path_changed
                    game_name = $report.game_name
                    effective_settings = $settings
                    candidates = $report.candidates
                })
            }
            'reconcile' {
                $saveKey = Get-ArgumentValue '--key'
                $localPath = Get-ArgumentValue '--local'
                $remotePath = Get-ArgumentValue '--remote'
                $localRoot = Get-ArgumentValue '--local-root'
                $remoteRoot = Get-ArgumentValue '--remote-root'
                $manifestPath = Get-ArgumentValue '--manifest'
                $historyRoot = Get-ArgumentValue '--history'
                $retroArchConfig = Get-ArgumentValue '--retroarch-config'
                $requiredArguments = @($saveKey, $localPath, $remotePath, $localRoot, $remoteRoot, $manifestPath, $historyRoot)
                if (@($requiredArguments | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
                    throw 'Use: cloudcartridge save reconcile --key <id> --local <arquivo> --remote <arquivo> --local-root <pasta> --remote-root <pasta> --manifest <arquivo> --history <pasta> [--yes] [--json]'
                }
                $configPaths = @($retroArchConfig | Where-Object { $_ })
                $result = Invoke-CloudCartridgeSaveReconcileGuarded -SaveKey $saveKey -LocalPath $localPath -RemotePath $remotePath -LocalRoot $localRoot -RemoteRoot $remoteRoot -ManifestPath $manifestPath -HistoryRoot $historyRoot -RetroArchConfigPaths $configPaths -CloudCartridgeSyncEnabled ([bool]$config.enable_cloud_save_sync) -Apply:$confirmed
                Write-Result $result
            }
            'queue' {
                $saveKey = Get-ArgumentValue '--key'
                $localPath = Get-ArgumentValue '--local'
                $remotePath = Get-ArgumentValue '--remote'
                $localRoot = Get-ArgumentValue '--local-root'
                $remoteRoot = Get-ArgumentValue '--remote-root'
                $manifestPath = Get-ArgumentValue '--manifest'
                $historyRoot = Get-ArgumentValue '--history'
                $queuePath = Get-ArgumentValue '--queue'
                $retroArchConfig = Get-ArgumentValue '--retroarch-config'
                $requiredArguments = @($saveKey, $localPath, $remotePath, $localRoot, $remoteRoot, $manifestPath, $historyRoot, $queuePath)
                if (@($requiredArguments | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
                    throw 'Use: cloudcartridge save queue --queue <arquivo> --key <id> --local <arquivo> --remote <arquivo> --local-root <pasta> --remote-root <pasta> --manifest <arquivo> --history <pasta> [--json]'
                }
                Write-Result (Add-CloudCartridgeSaveSyncJob -QueuePath $queuePath -SaveKey $saveKey -LocalPath $localPath -RemotePath $remotePath -LocalRoot $localRoot -RemoteRoot $remoteRoot -ManifestPath $manifestPath -HistoryRoot $historyRoot -RetroArchConfigPaths @($retroArchConfig | Where-Object { $_ }))
            }
            'jobs' {
                $queuePath = Get-ArgumentValue '--queue'
                if ([string]::IsNullOrWhiteSpace($queuePath)) { throw 'Use: cloudcartridge save jobs --queue <arquivo> [--json]' }
                Write-Result @(Get-CloudCartridgeSaveSyncJobs -QueuePath $queuePath)
            }
            'sync' {
                $queuePath = Get-ArgumentValue '--queue'
                if ([string]::IsNullOrWhiteSpace($queuePath)) { throw 'Use: cloudcartridge save sync --queue <arquivo> [--yes] [--json]' }
                if (-not $confirmed) {
                    $pendingJobs = @(Get-CloudCartridgeSaveSyncJobs -QueuePath $queuePath | Where-Object { $_.state -eq 'queued' })
                    Write-Result ([PSCustomObject]@{ applied = $false; dry_run = $true; pending = $pendingJobs })
                } else {
                    $syncResults = @(Invoke-CloudCartridgeSaveSyncQueue -QueuePath $queuePath -CloudCartridgeSyncEnabled ([bool]$config.enable_cloud_save_sync))
                    Write-Result ([PSCustomObject]@{ applied = $true; dry_run = $false; results = $syncResults })
                }
            }
            'versions' {
                $historyRoot = Get-ArgumentValue '--history'
                $saveKey = Get-ArgumentValue '--key'
                if ([string]::IsNullOrWhiteSpace($historyRoot) -or [string]::IsNullOrWhiteSpace($saveKey)) { throw 'Use: cloudcartridge save versions --history <pasta> --key <id> [--json]' }
                Write-Result @(Get-CloudCartridgeSaveVersions -HistoryRoot $historyRoot -SaveKey $saveKey)
            }
            'restore' {
                $versionPath = Get-ArgumentValue '--version'
                $historyRoot = Get-ArgumentValue '--history'
                $destinationPath = Get-ArgumentValue '--destination'
                $destinationRoot = Get-ArgumentValue '--destination-root'
                $saveKey = Get-ArgumentValue '--key'
                $requiredArguments = @($versionPath, $historyRoot, $destinationPath, $destinationRoot, $saveKey)
                if (@($requiredArguments | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) { throw 'Use: cloudcartridge save restore --version <arquivo> --history <pasta> --destination <arquivo> --destination-root <pasta> --key <id> [--yes] [--json]' }
                Write-Result (Restore-CloudCartridgeSaveVersion -VersionPath $versionPath -HistoryRoot $historyRoot -DestinationPath $destinationPath -DestinationRoot $destinationRoot -SaveKey $saveKey -Apply:$confirmed)
            }
            default { throw 'Use: cloudcartridge save doctor|reconcile|queue|jobs|sync|versions|restore [opcoes]' }
        }
    }
    'library' {
        $subcommand = if ($filteredArguments.Count -gt 0) { $filteredArguments[0] } else { 'index' }
        $indexPath = Get-ArgumentValue '--index'
        switch ($subcommand) {
            'index' {
                $libraryRoot = Get-ArgumentValue '--root'
                if ([string]::IsNullOrWhiteSpace($libraryRoot) -or [string]::IsNullOrWhiteSpace($indexPath)) { throw 'Use: cloudcartridge library index --root <pasta> --index <arquivo> [--yes] [--json]' }
                Write-Result (Update-CloudCartridgeCatalogIndex -LibraryRoot $libraryRoot -IndexPath $indexPath -Apply:$confirmed)
            }
            'inventory' {
                if ([string]::IsNullOrWhiteSpace($indexPath)) { throw 'Use: cloudcartridge library inventory --index <arquivo> [--json]' }
                Write-Result @(Get-CloudCartridgeCatalogInventory -IndexPath $indexPath)
            }
            default { throw 'Use: cloudcartridge library index|inventory [opcoes]' }
        }
    }
    'playlist' {
        $subcommand = if ($filteredArguments.Count -gt 0) { $filteredArguments[0] } else { 'sync' }
        if ($subcommand -ne 'sync') { throw 'Use: cloudcartridge playlist sync --rom-root <pasta> --playlist <arquivo> [--core-path <arquivo>] [--core-name <nome>] [--yes] [--json]' }
        $romRoot = Get-ArgumentValue '--rom-root'
        $playlistPath = Get-ArgumentValue '--playlist'
        $corePath = Get-ArgumentValue '--core-path'
        $coreName = Get-ArgumentValue '--core-name'
        if ([string]::IsNullOrWhiteSpace($romRoot) -or [string]::IsNullOrWhiteSpace($playlistPath)) { throw 'Use: cloudcartridge playlist sync --rom-root <pasta> --playlist <arquivo> [--core-path <arquivo>] [--core-name <nome>] [--yes] [--json]' }
        if ([string]::IsNullOrWhiteSpace($corePath)) { $corePath = 'DETECT' }
        if ([string]::IsNullOrWhiteSpace($coreName)) { $coreName = 'DETECT' }
        $candidates = @(Get-CloudCartridgeRomCandidates -RomRoot $romRoot)
        Write-Result (Merge-CloudCartridgePlaylist -PlaylistPath $playlistPath -DiscoveredItems $candidates -DefaultCorePath $corePath -DefaultCoreName $coreName -Apply:$confirmed)
    }
    'thumbnails' {
        $subcommand = if ($filteredArguments.Count -gt 0) { $filteredArguments[0] } else { 'plan' }
        switch ($subcommand) {
            'plan' {
                $playlistPath = Get-ArgumentValue '--playlist'
                $thumbnailDirectory = Get-ArgumentValue '--directory'
                if ([string]::IsNullOrWhiteSpace($playlistPath) -or [string]::IsNullOrWhiteSpace($thumbnailDirectory)) { throw 'Use: cloudcartridge thumbnails plan --playlist <arquivo> --directory <pasta> [--json]' }
                $playlistData = Get-Content -LiteralPath $playlistPath -Raw -Encoding UTF8 | ConvertFrom-Json
                Write-Result @(Repair-CloudCartridgeMissingThumbnails -PlaylistItems @($playlistData.items) -ThumbnailDirectory $thumbnailDirectory)
            }
            'download' {
                $url = Get-ArgumentValue '--url'
                $target = Get-ArgumentValue '--target'
                if ([string]::IsNullOrWhiteSpace($url) -or [string]::IsNullOrWhiteSpace($target)) { throw 'Use: cloudcartridge thumbnails download --url <url-oficial> --target <arquivo> [--yes] [--json]' }
                if (-not $confirmed) { Write-Result ([PSCustomObject]@{ applied = $false; dry_run = $true; url = $url; target = $target }) }
                else { Write-Result (Invoke-CloudCartridgeThumbnailDownload -Url $url -TargetPath $target) }
            }
            default { throw 'Use: cloudcartridge thumbnails plan|download [opcoes]' }
        }
    }
    default {
        throw "Comando desconhecido: $Command. Use status, doctor, detect, emulators, cores, cache, downloads, save, library, playlist ou thumbnails."
    }
}
