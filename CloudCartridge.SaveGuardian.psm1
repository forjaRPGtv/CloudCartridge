Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'CloudCartridge.Core.psm1')

function Get-CloudCartridgeSaveFingerprint {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [PSCustomObject]@{ exists = $false; path = $Path; sha256 = $null; size = 0; modified_utc = $null }
    }
    $item = Get-Item -LiteralPath $Path
    return [PSCustomObject]@{
        exists = $true
        path = $item.FullName
        sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        size = [long]$item.Length
        modified_utc = $item.LastWriteTimeUtc.ToString('o')
    }
}

function Get-CloudCartridgeSaveDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$LocalPath,
        [Parameter(Mandatory = $true)][string]$RemotePath,
        [AllowNull()][string]$BaselineSha256
    )
    $local = Get-CloudCartridgeSaveFingerprint -Path $LocalPath
    $remote = Get-CloudCartridgeSaveFingerprint -Path $RemotePath
    $decision = 'no_save_found'
    $reason = 'both_missing'

    if ($local.exists -and $remote.exists) {
        if ($local.sha256 -eq $remote.sha256) {
            $decision = 'in_sync'; $reason = 'content_equal'
        } elseif ([string]::IsNullOrWhiteSpace($BaselineSha256)) {
            $decision = 'conflict'; $reason = 'divergent_without_baseline'
        } else {
            $localChanged = $local.sha256 -ne $BaselineSha256
            $remoteChanged = $remote.sha256 -ne $BaselineSha256
            if ($localChanged -and -not $remoteChanged) {
                $decision = 'upload_versioned'; $reason = 'local_changed'
            } elseif (-not $localChanged -and $remoteChanged) {
                $decision = 'download_with_backup'; $reason = 'remote_changed'
            } else {
                $decision = 'conflict'; $reason = 'both_changed'
            }
        }
    } elseif ($local.exists) {
        if ([string]::IsNullOrWhiteSpace($BaselineSha256)) {
            $decision = 'upload_new'; $reason = 'remote_never_synced'
        } else {
            $decision = 'remote_missing_review'; $reason = 'remote_missing_after_sync'
        }
    } elseif ($remote.exists) {
        if ([string]::IsNullOrWhiteSpace($BaselineSha256)) {
            $decision = 'download_new'; $reason = 'local_never_synced'
        } else {
            $decision = 'local_missing_review'; $reason = 'local_missing_after_sync'
        }
    }

    return [PSCustomObject]@{
        decision = $decision
        reason = $reason
        baseline_sha256 = $BaselineSha256
        local = $local
        remote = $remote
    }
}

function Read-CloudCartridgeRetroArchSaveSettings {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string[]]$ConfigPaths)
    $effective = [ordered]@{
        savefile_directory = $null
        savestate_directory = $null
        sort_savefiles_enable = $null
        sort_savestates_enable = $null
        sources = @()
    }
    foreach ($configPath in $ConfigPaths) {
        if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { continue }
        $effective.sources += [System.IO.Path]::GetFullPath($configPath)
        foreach ($line in Get-Content -LiteralPath $configPath -Encoding UTF8) {
            if ($line -notmatch '^\s*([a-zA-Z0-9_]+)\s*=\s*"?(.*?)"?\s*$') { continue }
            $key = $matches[1]
            $value = $matches[2].Trim().Trim('"')
            if ($key -notin @('savefile_directory', 'savestate_directory', 'sort_savefiles_enable', 'sort_savestates_enable')) { continue }
            if ($key -like 'sort_*') {
                $effective[$key] = $value -eq 'true'
            } else {
                $effective[$key] = if ($value -eq 'default' -or [string]::IsNullOrWhiteSpace($value)) { $null } else { [Environment]::ExpandEnvironmentVariables($value) }
            }
        }
    }
    return [PSCustomObject]$effective
}

function Get-CloudCartridgeNativeSaveSyncState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string[]]$ConfigPaths,
        [bool]$CloudCartridgeSyncEnabled = $true
    )
    $nativeEnabled = $false
    $evidence = @()
    foreach ($configPath in $ConfigPaths) {
        if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { continue }
        foreach ($line in Get-Content -LiteralPath $configPath -Encoding UTF8) {
            if ($line -match '^\s*(cloud_sync_enable|cloud_sync_sync_saves)\s*=\s*"?true"?\s*$') {
                $nativeEnabled = $true
                $evidence += [PSCustomObject]@{ config_path = [System.IO.Path]::GetFullPath($configPath); setting = $matches[1] }
            }
        }
    }
    return [PSCustomObject]@{
        native_sync_enabled = $nativeEnabled
        cloudcartridge_sync_enabled = $CloudCartridgeSyncEnabled
        conflict = $nativeEnabled -and $CloudCartridgeSyncEnabled
        action = if ($nativeEnabled -and $CloudCartridgeSyncEnabled) { 'block_double_sync' } else { 'none' }
        evidence = $evidence
    }
}

function Enter-CloudCartridgeSaveLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$LockRoot,
        [Parameter(Mandatory = $true)][string]$SaveKey
    )
    New-Item -ItemType Directory -Path $LockRoot -Force | Out-Null
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        $keyHash = (($algorithm.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($SaveKey)) | ForEach-Object { $_.ToString('x2') }) -join '')
    } finally { $algorithm.Dispose() }
    $lockPath = Join-Path $LockRoot ("$keyHash.lock")
    $token = [Guid]::NewGuid().ToString('N')
    for ($attempt = 0; $attempt -lt 2; $attempt++) {
        try {
            $stream = New-Object System.IO.FileStream($lockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            try {
                $payload = [System.Text.Encoding]::UTF8.GetBytes((([PSCustomObject]@{ token = $token; owner_pid = $PID; acquired_utc = [DateTime]::UtcNow.ToString('o'); save_key = $SaveKey }) | ConvertTo-Json -Compress))
                $stream.Write($payload, 0, $payload.Length)
                $stream.Flush($true)
            } finally { $stream.Dispose() }
            return [PSCustomObject]@{ acquired = $true; recovered_stale = ($attempt -gt 0); token = $token; lock_path = $lockPath }
        } catch [System.IO.IOException] {
            $ownerAlive = $true
            try {
                $existing = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $ownerAlive = $existing.owner_pid -and ($null -ne (Get-Process -Id ([int]$existing.owner_pid) -ErrorAction SilentlyContinue))
            } catch { $ownerAlive = $false }
            if ($ownerAlive -or $attempt -gt 0) {
                return [PSCustomObject]@{ acquired = $false; recovered_stale = $false; token = $null; lock_path = $lockPath }
            }
            Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Exit-CloudCartridgeSaveLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$LockPath,
        [Parameter(Mandatory = $true)][string]$Token
    )
    if (-not (Test-Path -LiteralPath $LockPath -PathType Leaf)) { return $false }
    try { $existing = Get-Content -LiteralPath $LockPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $false }
    if ($existing.token -ne $Token) { return $false }
    Remove-Item -LiteralPath $LockPath -Force
    return $true
}

function Find-CloudCartridgeSaveCandidates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$GameName,
        [Parameter(Mandatory = $true)][string[]]$CurrentDirectories,
        [string[]]$LegacyDirectories = @(),
        [string[]]$Extensions = @('.srm', '.sav', '.mcd', '.state')
    )
    $names = @($GameName, ($GameName -replace '\s*\([^\)]*\)\s*$', '')) | Where-Object { $_ } | Select-Object -Unique
    $candidates = @()
    $roots = @()
    foreach ($directory in $CurrentDirectories) { $roots += [PSCustomObject]@{ path = $directory; source = 'current' } }
    foreach ($directory in $LegacyDirectories) { $roots += [PSCustomObject]@{ path = $directory; source = 'legacy' } }
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root.path -PathType Container)) { continue }
        foreach ($file in Get-ChildItem -LiteralPath $root.path -Recurse -File -ErrorAction SilentlyContinue) {
            if ($file.Extension.ToLowerInvariant() -notin $Extensions) { continue }
            if ($file.BaseName -notin $names) { continue }
            $fingerprint = Get-CloudCartridgeSaveFingerprint -Path $file.FullName
            $candidates += [PSCustomObject]@{
                path = $file.FullName
                source = $root.source
                sha256 = $fingerprint.sha256
                size = $fingerprint.size
                modified_utc = $fingerprint.modified_utc
            }
        }
    }
    $legacyFound = @($candidates | Where-Object { $_.source -eq 'legacy' }).Count -gt 0
    $currentFound = @($candidates | Where-Object { $_.source -eq 'current' }).Count -gt 0
    $status = if ($currentFound) { 'found_current_save' } elseif ($legacyFound) { 'found_legacy_save' } else { 'no_save_found' }
    return [PSCustomObject]@{
        status = $status
        path_changed = $legacyFound -and -not $currentFound
        game_name = $GameName
        candidates = $candidates
    }
}

function Read-CloudCartridgeSaveManifest {
    param([Parameter(Mandatory = $true)][string]$ManifestPath)
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        return [PSCustomObject]@{ schema_version = 1; saves = [PSCustomObject]@{} }
    }
    try {
        $manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $manifest.PSObject.Properties['saves']) { throw 'Campo saves ausente.' }
        return $manifest
    } catch {
        throw "Manifesto de saves invalido: $($_.Exception.Message)"
    }
}

function Copy-CloudCartridgeSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$HistoryRoot,
        [Parameter(Mandatory = $true)][string]$SaveKey,
        [ValidateRange(1, 50)][int]$RetainVersions = 5
    )
    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) { return $null }
    $safeKey = $SaveKey -replace '[^a-zA-Z0-9._-]', '_'
    $saveHistoryRoot = Join-Path $HistoryRoot $safeKey
    New-Item -ItemType Directory -Path $saveHistoryRoot -Force | Out-Null
    $fingerprint = Get-CloudCartridgeSaveFingerprint -Path $SourcePath
    $extension = [System.IO.Path]::GetExtension($SourcePath)
    $shortHash = $fingerprint.sha256.Substring(0, 16)
    $snapshotPath = Join-Path $saveHistoryRoot ("{0}-{1}{2}" -f ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ')), $shortHash, $extension)
    $temporaryPath = "$snapshotPath.partial"
    Copy-Item -LiteralPath $SourcePath -Destination $temporaryPath -Force
    Move-Item -LiteralPath $temporaryPath -Destination $snapshotPath
    $snapshots = @(Get-ChildItem -LiteralPath $saveHistoryRoot -File | Sort-Object LastWriteTimeUtc -Descending)
    foreach ($old in @($snapshots | Select-Object -Skip $RetainVersions)) {
        Remove-Item -LiteralPath $old.FullName -Force
    }
    return $snapshotPath
}

function Invoke-CloudCartridgeSaveReconcile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SaveKey,
        [Parameter(Mandatory = $true)][string]$LocalPath,
        [Parameter(Mandatory = $true)][string]$RemotePath,
        [Parameter(Mandatory = $true)][string]$LocalRoot,
        [Parameter(Mandatory = $true)][string]$RemoteRoot,
        [Parameter(Mandatory = $true)][string]$ManifestPath,
        [Parameter(Mandatory = $true)][string]$HistoryRoot,
        [ValidateRange(1, 50)][int]$RetainVersions = 5,
        [switch]$Apply
    )
    if (-not (Test-CloudCartridgePathWithinRoot -Path $LocalPath -Root $LocalRoot)) { throw 'Save local fora da raiz permitida.' }
    if (-not (Test-CloudCartridgePathWithinRoot -Path $RemotePath -Root $RemoteRoot)) { throw 'Save remoto fora da raiz permitida.' }
    $manifest = Read-CloudCartridgeSaveManifest -ManifestPath $ManifestPath
    $manifestEntry = $manifest.saves.PSObject.Properties[$SaveKey]
    $baseline = if ($manifestEntry) { [string]$manifestEntry.Value.baseline_sha256 } else { $null }
    $analysis = Get-CloudCartridgeSaveDecision -LocalPath $LocalPath -RemotePath $RemotePath -BaselineSha256 $baseline
    $result = [ordered]@{
        save_key = $SaveKey
        decision = $analysis.decision
        reason = $analysis.reason
        applied = $false
        action = 'none'
        baseline_sha256 = $baseline
        local_sha256 = $analysis.local.sha256
        remote_sha256 = $analysis.remote.sha256
        preserved = @()
    }
    if (-not $Apply) { return [PSCustomObject]$result }

    $newBaseline = $null
    switch ($analysis.decision) {
        'in_sync' {
            $newBaseline = $analysis.local.sha256
            $result.action = 'manifest_refreshed'
            $result.applied = $true
        }
        'upload_new' {
            $copy = Copy-CloudCartridgeSaveSafely -SourcePath $LocalPath -DestinationPath $RemotePath -DestinationRoot $RemoteRoot
            $newBaseline = $analysis.local.sha256
            $result.action = $copy.status
            $result.applied = $true
        }
        'upload_versioned' {
            $snapshot = Copy-CloudCartridgeSnapshot -SourcePath $RemotePath -HistoryRoot $HistoryRoot -SaveKey $SaveKey -RetainVersions $RetainVersions
            $copy = Copy-CloudCartridgeSaveSafely -SourcePath $LocalPath -DestinationPath $RemotePath -DestinationRoot $RemoteRoot
            $newBaseline = $analysis.local.sha256
            $result.preserved = @($snapshot)
            $result.action = $copy.status
            $result.applied = $true
        }
        'download_new' {
            $copy = Copy-CloudCartridgeSaveSafely -SourcePath $RemotePath -DestinationPath $LocalPath -DestinationRoot $LocalRoot
            $newBaseline = $analysis.remote.sha256
            $result.action = $copy.status
            $result.applied = $true
        }
        'download_with_backup' {
            $snapshot = Copy-CloudCartridgeSnapshot -SourcePath $LocalPath -HistoryRoot $HistoryRoot -SaveKey $SaveKey -RetainVersions $RetainVersions
            $copy = Copy-CloudCartridgeSaveSafely -SourcePath $RemotePath -DestinationPath $LocalPath -DestinationRoot $LocalRoot
            $newBaseline = $analysis.remote.sha256
            $result.preserved = @($snapshot)
            $result.action = $copy.status
            $result.applied = $true
        }
        'conflict' {
            $localSnapshot = Copy-CloudCartridgeSnapshot -SourcePath $LocalPath -HistoryRoot $HistoryRoot -SaveKey "$SaveKey-local-conflict" -RetainVersions $RetainVersions
            $remoteSnapshot = Copy-CloudCartridgeSnapshot -SourcePath $RemotePath -HistoryRoot $HistoryRoot -SaveKey "$SaveKey-remote-conflict" -RetainVersions $RetainVersions
            $result.preserved = @($localSnapshot, $remoteSnapshot)
            $result.action = 'conflict_preserved'
            $result.applied = $true
        }
    }

    if ($newBaseline) {
        $previousGeneration = if ($manifestEntry -and $manifestEntry.Value.generation) { [int]$manifestEntry.Value.generation } else { 0 }
        $entry = [PSCustomObject][ordered]@{
            local_path = [System.IO.Path]::GetFullPath($LocalPath)
            remote_path = [System.IO.Path]::GetFullPath($RemotePath)
            baseline_sha256 = $newBaseline
            generation = $previousGeneration + 1
            confirmed_utc = [DateTime]::UtcNow.ToString('o')
        }
        if ($manifestEntry) { $manifest.saves.($SaveKey) = $entry } else { $manifest.saves | Add-Member NoteProperty $SaveKey $entry }
        Write-CloudCartridgeJsonAtomic -InputObject $manifest -Path $ManifestPath -Depth 8
        $result.baseline_sha256 = $newBaseline
    }
    return [PSCustomObject]$result
}

function Invoke-CloudCartridgeSaveReconcileGuarded {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SaveKey,
        [Parameter(Mandatory = $true)][string]$LocalPath,
        [Parameter(Mandatory = $true)][string]$RemotePath,
        [Parameter(Mandatory = $true)][string]$LocalRoot,
        [Parameter(Mandatory = $true)][string]$RemoteRoot,
        [Parameter(Mandatory = $true)][string]$ManifestPath,
        [Parameter(Mandatory = $true)][string]$HistoryRoot,
        [string[]]$RetroArchConfigPaths = @(),
        [bool]$CloudCartridgeSyncEnabled = $true,
        [ValidateRange(1, 50)][int]$RetainVersions = 5,
        [switch]$Apply
    )
    if ($RetroArchConfigPaths.Count -gt 0) {
        $syncState = Get-CloudCartridgeNativeSaveSyncState -ConfigPaths $RetroArchConfigPaths -CloudCartridgeSyncEnabled $CloudCartridgeSyncEnabled
        if ($syncState.conflict) { throw 'Sincronizacao bloqueada: RetroArch Cloud Sync e CloudCartridge estao ativos para saves.' }
    }
    if (-not $Apply) {
        return Invoke-CloudCartridgeSaveReconcile -SaveKey $SaveKey -LocalPath $LocalPath -RemotePath $RemotePath -LocalRoot $LocalRoot -RemoteRoot $RemoteRoot -ManifestPath $ManifestPath -HistoryRoot $HistoryRoot -RetainVersions $RetainVersions
    }
    $manifestDirectory = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($ManifestPath))
    $lock = Enter-CloudCartridgeSaveLock -LockRoot (Join-Path $manifestDirectory '.save-locks') -SaveKey $SaveKey
    if (-not $lock.acquired) { throw "Save em uso por outro processo: $SaveKey" }
    try {
        return Invoke-CloudCartridgeSaveReconcile -SaveKey $SaveKey -LocalPath $LocalPath -RemotePath $RemotePath -LocalRoot $LocalRoot -RemoteRoot $RemoteRoot -ManifestPath $ManifestPath -HistoryRoot $HistoryRoot -RetainVersions $RetainVersions -Apply
    } finally {
        if (-not (Exit-CloudCartridgeSaveLock -LockPath $lock.lock_path -Token $lock.token)) {
            Write-Warning "Nao foi possivel liberar lock do save: $SaveKey"
        }
    }
}

Export-ModuleMember -Function @(
    'Get-CloudCartridgeSaveFingerprint',
    'Get-CloudCartridgeSaveDecision',
    'Read-CloudCartridgeRetroArchSaveSettings',
    'Get-CloudCartridgeNativeSaveSyncState',
    'Enter-CloudCartridgeSaveLock',
    'Exit-CloudCartridgeSaveLock',
    'Find-CloudCartridgeSaveCandidates',
    'Invoke-CloudCartridgeSaveReconcile',
    'Invoke-CloudCartridgeSaveReconcileGuarded'
)
