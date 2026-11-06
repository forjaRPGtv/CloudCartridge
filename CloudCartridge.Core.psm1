Set-StrictMode -Version Latest

function Get-CloudCartridgeConfig {
    [CmdletBinding()]
    param([string]$ConfigPath = (Join-Path $PSScriptRoot 'config.json'))

    $defaults = [ordered]@{
        google_drive_roms_path     = ''
        local_roms_path            = 'Z:\_ISOS_ROMS_'
        retroarch_path             = 'C:\RetroArch-Win64\retroarch.exe'
        retention_days             = 3
        cleanup_enabled            = $true
        enable_cloud_save_sync     = $true
        enable_multi_disc_prefetch = $true
        enable_telemetry_hud       = $true
        max_concurrent_downloads   = 3
    }

    if (Test-Path -LiteralPath $ConfigPath) {
        try {
            $loaded = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($property in $loaded.PSObject.Properties) {
                if ($defaults.Contains($property.Name)) {
                    $defaults[$property.Name] = $property.Value
                }
            }
        } catch {
            throw "Configuracao invalida em '$ConfigPath': $($_.Exception.Message)"
        }
    }

    if ($null -eq $defaults.retention_days -or [string]$defaults.retention_days -eq 'off') {
        $defaults.retention_days = $null
        $defaults.cleanup_enabled = $false
    } else {
        $retentionDays = [int]$defaults.retention_days
        if ($retentionDays -lt 1 -or $retentionDays -gt 3650) {
            throw 'retention_days deve estar entre 1 e 3650, null ou off.'
        }
        $defaults.retention_days = $retentionDays
    }
    $maxDownloads = [int]$defaults.max_concurrent_downloads
    if ($maxDownloads -lt 1 -or $maxDownloads -gt 16) {
        throw 'max_concurrent_downloads deve estar entre 1 e 16.'
    }

    return [PSCustomObject]$defaults
}

function Update-CloudCartridgeConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ConfigPath,
        [Parameter(Mandatory = $true)][hashtable]$Values,
        [switch]$DryRun
    )

    $current = Get-CloudCartridgeConfig -ConfigPath $ConfigPath
    foreach ($key in $Values.Keys) {
        if (-not $current.PSObject.Properties[$key]) {
            throw "Opcao de configuracao desconhecida: $key"
        }
        $current.$key = $Values[$key]
    }

    $validationPath = "$ConfigPath.validation.$([Guid]::NewGuid().ToString('N')).json"
    try {
        Write-CloudCartridgeJsonAtomic -InputObject $current -Path $validationPath
        $validated = Get-CloudCartridgeConfig -ConfigPath $validationPath
    } finally {
        if (Test-Path -LiteralPath $validationPath) {
            Remove-Item -LiteralPath $validationPath -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not $DryRun) {
        Write-CloudCartridgeJsonAtomic -InputObject $validated -Path $ConfigPath
    }
    return $validated
}

function Test-CloudCartridgePathWithinRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    try {
        $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
        $pathFull = [System.IO.Path]::GetFullPath($Path)
        return $pathFull.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)
    } catch {
        return $false
    }
}

function Find-CloudCartridgeExecutable {
    [CmdletBinding()]
    param(
        [string[]]$CandidatePaths = @(),
        [string[]]$CommandNames = @()
    )
    foreach ($candidate in @($CandidatePaths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return [PSCustomObject]@{
                state = 'detected'
                path = [System.IO.Path]::GetFullPath($candidate)
                source = 'candidate'
            }
        }
    }
    foreach ($commandName in @($CommandNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        $command = Get-Command $commandName -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) {
            return [PSCustomObject]@{
                state = 'detected'
                path = $command.Source
                source = 'path'
            }
        }
    }
    return [PSCustomObject]@{ state = 'not_installed'; path = $null; source = $null }
}

function Write-CloudCartridgeJsonAtomic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$InputObject,
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$Depth = 8
    )

    $directory = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($Path))
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $tempPath = "$Path.partial.$([Guid]::NewGuid().ToString('N'))"
    try {
        $json = $InputObject | ConvertTo-Json -Depth $Depth
        [System.IO.File]::WriteAllText($tempPath, $json, (New-Object System.Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $tempPath -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Copy-CloudCartridgeSaveSafely {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [Parameter(Mandatory = $true)][string]$DestinationRoot,
        [switch]$DryRun
    )

    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        throw "Save de origem inexistente: $SourcePath"
    }
    if (-not (Test-CloudCartridgePathWithinRoot -Path $DestinationPath -Root $DestinationRoot)) {
        throw "Destino fora da raiz autorizada de saves: $DestinationPath"
    }

    $sourceHash = (Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash
    $destinationExists = Test-Path -LiteralPath $DestinationPath -PathType Leaf
    if ($destinationExists) {
        $destinationHash = (Get-FileHash -LiteralPath $DestinationPath -Algorithm SHA256).Hash
        if ($sourceHash -eq $destinationHash) {
            return [PSCustomObject]@{ status = 'unchanged'; backup_path = $null; sha256 = $sourceHash }
        }
    }

    $rootFull = [System.IO.Path]::GetFullPath($DestinationRoot).TrimEnd('\', '/')
    $relativePath = [System.IO.Path]::GetFullPath($DestinationPath).Substring($rootFull.Length).TrimStart('\', '/')
    $backupPath = $null
    if ($destinationExists) {
        $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffffffZ')
        $backupPath = Join-Path (Join-Path $DestinationRoot '.versions') "$relativePath.$stamp.bak"
    }

    if ($DryRun) {
        return [PSCustomObject]@{ status = 'would_update'; backup_path = $backupPath; sha256 = $sourceHash }
    }

    $destinationDirectory = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($DestinationPath))
    if (-not (Test-Path -LiteralPath $destinationDirectory)) {
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
    }
    if ($destinationExists) {
        $backupDirectory = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($backupPath))
        if (-not (Test-Path -LiteralPath $backupDirectory)) {
            New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
        }
        Copy-Item -LiteralPath $DestinationPath -Destination $backupPath
    }

    $tempPath = "$DestinationPath.partial.$([Guid]::NewGuid().ToString('N'))"
    try {
        Copy-Item -LiteralPath $SourcePath -Destination $tempPath
        $tempHash = (Get-FileHash -LiteralPath $tempPath -Algorithm SHA256).Hash
        if ($tempHash -ne $sourceHash) {
            throw 'Falha de integridade ao preparar o save para sincronizacao.'
        }
        Move-Item -LiteralPath $tempPath -Destination $DestinationPath -Force
    } finally {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }

    return [PSCustomObject]@{
        status      = if ($destinationExists) { 'updated_with_backup' } else { 'created' }
        backup_path = $backupPath
        sha256      = $sourceHash
    }
}

function Set-CloudCartridgeCachePin {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RegistryPath,
        [Parameter(Mandatory = $true)][string]$ManagedRoot,
        [Parameter(Mandatory = $true)][string]$Identifier,
        [Parameter(Mandatory = $true)][bool]$Pinned,
        [switch]$DryRun
    )

    if (-not (Test-Path -LiteralPath $RegistryPath -PathType Leaf)) {
        throw "Registro de cache inexistente: $RegistryPath"
    }
    try {
        $registry = Get-Content -LiteralPath $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        throw "Registro de cache invalido: $($_.Exception.Message)"
    }
    $entries = if ($registry.games) { @($registry.games.PSObject.Properties) } else { @() }
    $matches = @($entries | Where-Object {
        $_.Name -eq $Identifier -or
        ($_.Value.PSObject.Properties['catalog_id'] -and $_.Value.catalog_id -eq $Identifier)
    })
    if ($matches.Count -eq 0) { throw "Jogo nao encontrado no cache: $Identifier" }
    if ($matches.Count -gt 1) { throw "Identificador ambiguo no cache: $Identifier" }

    $entry = $matches[0]
    if (-not (Test-CloudCartridgePathWithinRoot -Path $entry.Name -Root $ManagedRoot)) {
        throw "Entrada de cache fora da raiz gerenciada: $($entry.Name)"
    }
    $previous = [bool]$entry.Value.is_pinned
    if (-not $DryRun) {
        $entry.Value.is_pinned = $Pinned
        Write-CloudCartridgeJsonAtomic -InputObject $registry -Path $RegistryPath
    }
    return [PSCustomObject]@{
        identifier = $Identifier
        path = $entry.Name
        previous = $previous
        pinned = $Pinned
        applied = -not [bool]$DryRun
    }
}

function Get-CloudCartridgeCacheCleanupPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RegistryPath,
        [Parameter(Mandatory = $true)][string]$ManagedRoot,
        [AllowNull()][Nullable[int]]$RetentionDays,
        [bool]$CleanupEnabled = $true,
        [DateTime]$NowUtc = ([DateTime]::UtcNow)
    )
    if (-not (Test-Path -LiteralPath $RegistryPath -PathType Leaf)) { return @() }
    try {
        $registry = Get-Content -LiteralPath $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        throw "Registro de cache invalido: $($_.Exception.Message)"
    }
    $plan = @()
    foreach ($property in @($registry.games.PSObject.Properties)) {
        $item = $property.Value
        $decision = 'retained'
        $reason = 'not_expired'
        $ageDays = $null
        if (-not $CleanupEnabled -or $null -eq $RetentionDays) {
            $reason = 'cleanup_disabled'
        } elseif (-not (Test-CloudCartridgePathWithinRoot -Path $property.Name -Root $ManagedRoot) -or $property.Name -like '*\_RA_*') {
            $decision = 'blocked'
            $reason = 'outside_managed_cache'
        } elseif ([bool]$item.is_pinned) {
            $reason = 'pinned'
        } elseif ($item.status -ne 'local_cached') {
            $reason = 'not_local_cached'
        } elseif (-not $item.last_played) {
            $reason = 'missing_last_played'
        } else {
            try {
                $lastPlayedUtc = ([DateTime]$item.last_played).ToUniversalTime()
                $ageDays = ($NowUtc.ToUniversalTime() - $lastPlayedUtc).TotalDays
                if ($ageDays -ge [int]$RetentionDays) {
                    $decision = 'dehydrate'
                    $reason = 'expired'
                }
            } catch {
                $decision = 'blocked'
                $reason = 'invalid_last_played'
            }
        }
        $plan += [PSCustomObject]@{
            path = $property.Name
            title = $item.title
            decision = $decision
            reason = $reason
            age_days = if ($null -eq $ageDays) { $null } else { [math]::Round($ageDays, 3) }
        }
    }
    return $plan
}

function Invoke-CloudCartridgeCacheCleanup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RegistryPath,
        [Parameter(Mandatory = $true)][string]$ManagedRoot,
        [AllowNull()][Nullable[int]]$RetentionDays,
        [bool]$CleanupEnabled = $true,
        [switch]$DryRun,
        [scriptblock]$DehydrateAction
    )
    $plan = @(Get-CloudCartridgeCacheCleanupPlan -RegistryPath $RegistryPath -ManagedRoot $ManagedRoot -RetentionDays $RetentionDays -CleanupEnabled $CleanupEnabled)
    if ($DryRun -or $plan.Count -eq 0) { return $plan }
    $registry = Get-Content -LiteralPath $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $changed = $false
    foreach ($row in @($plan | Where-Object { $_.decision -eq 'dehydrate' })) {
        if (-not (Test-Path -LiteralPath $row.path -PathType Leaf)) {
            $row.decision = 'failed'
            $row.reason = 'file_missing'
            continue
        }
        try {
            $success = if ($DehydrateAction) {
                [bool](& $DehydrateAction $row.path)
            } else {
                $process = Start-Process -FilePath 'attrib.exe' -ArgumentList '+u', '-p', "`"$($row.path)`"" -NoNewWindow -Wait -PassThru
                $process.ExitCode -eq 0
            }
            if ($success) {
                $registry.games.($row.path).status = 'cloud_only'
                $row.decision = 'dehydrated'
                $row.reason = 'success'
                $changed = $true
            } else {
                $row.decision = 'failed'
                $row.reason = 'dehydrate_failed'
            }
        } catch {
            $row.decision = 'failed'
            $row.reason = 'dehydrate_exception'
        }
    }
    if ($changed) { Write-CloudCartridgeJsonAtomic -InputObject $registry -Path $RegistryPath }
    return $plan
}

function Invoke-CloudCartridgeFileLock {
    param(
        [Parameter(Mandatory = $true)][string]$LockPath,
        [Parameter(Mandatory = $true)][scriptblock]$Body,
        [int]$TimeoutMilliseconds = 5000
    )
    $directory = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($LockPath))
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
    $stream = $null
    while ($null -eq $stream -and [DateTime]::UtcNow -lt $deadline) {
        try {
            $stream = New-Object System.IO.FileStream($LockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        } catch [System.IO.IOException] {
            Start-Sleep -Milliseconds 50
        }
    }
    if ($null -eq $stream) { throw "Timeout aguardando lock: $LockPath" }
    try { return & $Body } finally { $stream.Dispose() }
}

function Get-CloudCartridgeDownloadPriority {
    param([string]$Priority)
    switch ($Priority) {
        'current' { return 100 }
        'resume' { return 80 }
        'prefetch' { return 40 }
        'maintenance' { return 10 }
        default { throw "Prioridade de download invalida: $Priority" }
    }
}

function Get-CloudCartridgeCatalogIdForPath {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)
    $normalized = [System.IO.Path]::GetFullPath($Path).Replace('/', '\').ToLowerInvariant()
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $algorithm.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($normalized))
        return 'path-' + (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
    } finally {
        $algorithm.Dispose()
    }
}

function Read-CloudCartridgeDownloadJournal {
    param([string]$JournalPath)
    if (-not (Test-Path -LiteralPath $JournalPath -PathType Leaf)) {
        return [PSCustomObject]@{ schema_version = 1; jobs = @() }
    }
    try {
        $journal = Get-Content -LiteralPath $JournalPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $journal.PSObject.Properties['jobs']) { throw 'Campo jobs ausente.' }
        return $journal
    } catch {
        throw "Journal de downloads invalido: $($_.Exception.Message)"
    }
}

function Register-CloudCartridgeDownloadJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$JournalPath,
        [Parameter(Mandatory = $true)][string]$ManagedRoot,
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$CatalogId,
        [ValidateSet('current', 'resume', 'prefetch', 'maintenance')][string]$Priority = 'current'
    )
    if (-not (Test-CloudCartridgePathWithinRoot -Path $FilePath -Root $ManagedRoot)) {
        throw "Download fora da raiz gerenciada: $FilePath"
    }
    $lockPath = "$JournalPath.lock"
    $result = Invoke-CloudCartridgeFileLock -LockPath $lockPath -Body {
        $journal = Read-CloudCartridgeDownloadJournal -JournalPath $JournalPath
        $jobs = @($journal.jobs)
        $existing = @($jobs | Where-Object {
            ($_.catalog_id -eq $CatalogId -or $_.file_path -eq $FilePath) -and $_.state -in @('queued', 'active')
        } | Select-Object -First 1)
        if ($existing.Count -gt 0) {
            return [PSCustomObject]@{ job = $existing[0]; deduplicated = $true }
        }
        $job = [PSCustomObject][ordered]@{
            job_id = [Guid]::NewGuid().ToString('D')
            catalog_id = $CatalogId
            file_path = $FilePath
            priority = $Priority
            priority_value = Get-CloudCartridgeDownloadPriority -Priority $Priority
            state = 'queued'
            bytes_downloaded = 0
            total_bytes = 0
            content_sha256 = $null
            created_at_utc = [DateTime]::UtcNow.ToString('o')
            updated_at_utc = [DateTime]::UtcNow.ToString('o')
            owner_pid = $null
            error = $null
        }
        $journal.jobs = @($jobs + $job)
        Write-CloudCartridgeJsonAtomic -InputObject $journal -Path $JournalPath
        return [PSCustomObject]@{ job = $job; deduplicated = $false }
    }
    return $result
}

function Get-CloudCartridgeDownloadJobs {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$JournalPath)
    $journal = Read-CloudCartridgeDownloadJournal -JournalPath $JournalPath
    return @($journal.jobs | Sort-Object @{ Expression = 'priority_value'; Descending = $true }, @{ Expression = 'created_at_utc'; Descending = $false })
}

function Set-CloudCartridgeDownloadJobState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$JournalPath,
        [Parameter(Mandatory = $true)][string]$JobId,
        [ValidateSet('queued', 'active', 'completed', 'failed')][string]$State,
        [Nullable[long]]$BytesDownloaded,
        [Nullable[long]]$TotalBytes,
        [string]$ContentSha256 = '',
        [string]$ErrorMessage = ''
    )
    $hasBytesDownloaded = $PSBoundParameters.ContainsKey('BytesDownloaded')
    $hasTotalBytes = $PSBoundParameters.ContainsKey('TotalBytes')
    $lockPath = "$JournalPath.lock"
    return Invoke-CloudCartridgeFileLock -LockPath $lockPath -Body {
        $journal = Read-CloudCartridgeDownloadJournal -JournalPath $JournalPath
        $job = @($journal.jobs | Where-Object { $_.job_id -eq $JobId } | Select-Object -First 1)
        if ($job.Count -eq 0) { throw "Job inexistente: $JobId" }
        $job[0].state = $State
        if ($hasBytesDownloaded) { $job[0].bytes_downloaded = [long]$BytesDownloaded }
        if ($hasTotalBytes) { $job[0].total_bytes = [long]$TotalBytes }
        if (-not $job[0].PSObject.Properties['content_sha256']) {
            $job[0] | Add-Member NoteProperty content_sha256 $null
        }
        if ($ContentSha256) { $job[0].content_sha256 = $ContentSha256.ToLowerInvariant() }
        $job[0].updated_at_utc = [DateTime]::UtcNow.ToString('o')
        $job[0].owner_pid = if ($State -eq 'active') { $PID } else { $null }
        $job[0].error = if ($ErrorMessage) { $ErrorMessage } else { $null }
        Write-CloudCartridgeJsonAtomic -InputObject $journal -Path $JournalPath
        return $job[0]
    }
}

function Enter-CloudCartridgeDownloadJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$JournalPath,
        [Parameter(Mandatory = $true)][string]$JobId,
        [ValidateRange(1, 16)][int]$MaxConcurrent = 3
    )
    $lockPath = "$JournalPath.lock"
    return Invoke-CloudCartridgeFileLock -LockPath $lockPath -Body {
        $journal = Read-CloudCartridgeDownloadJournal -JournalPath $JournalPath
        $jobs = @($journal.jobs)
        foreach ($activeJob in @($jobs | Where-Object { $_.state -eq 'active' })) {
            $ownerAlive = $false
            if ($activeJob.owner_pid) {
                $ownerAlive = $null -ne (Get-Process -Id ([int]$activeJob.owner_pid) -ErrorAction SilentlyContinue)
            }
            if (-not $ownerAlive) {
                $activeJob.state = 'queued'
                $activeJob.owner_pid = $null
                $activeJob.updated_at_utc = [DateTime]::UtcNow.ToString('o')
            }
        }
        $target = @($jobs | Where-Object { $_.job_id -eq $JobId } | Select-Object -First 1)
        if ($target.Count -eq 0) { throw "Job inexistente: $JobId" }
        if ($target[0].state -eq 'active' -and [int]$target[0].owner_pid -eq $PID) { return $true }
        if ($target[0].state -ne 'queued') { return $false }

        $activeCount = @($jobs | Where-Object { $_.state -eq 'active' }).Count
        $available = $MaxConcurrent - $activeCount
        if ($available -le 0) {
            Write-CloudCartridgeJsonAtomic -InputObject $journal -Path $JournalPath
            return $false
        }
        $eligible = @($jobs | Where-Object { $_.state -eq 'queued' } |
            Sort-Object @{ Expression = 'priority_value'; Descending = $true }, @{ Expression = 'created_at_utc'; Descending = $false } |
            Select-Object -First $available)
        if (@($eligible | Where-Object { $_.job_id -eq $JobId }).Count -eq 0) {
            Write-CloudCartridgeJsonAtomic -InputObject $journal -Path $JournalPath
            return $false
        }
        $target[0].state = 'active'
        $target[0].owner_pid = $PID
        $target[0].updated_at_utc = [DateTime]::UtcNow.ToString('o')
        Write-CloudCartridgeJsonAtomic -InputObject $journal -Path $JournalPath
        return $true
    }
}

Export-ModuleMember -Function @(
    'Get-CloudCartridgeConfig',
    'Update-CloudCartridgeConfig',
    'Find-CloudCartridgeExecutable',
    'Test-CloudCartridgePathWithinRoot',
    'Write-CloudCartridgeJsonAtomic',
    'Copy-CloudCartridgeSaveSafely',
    'Set-CloudCartridgeCachePin',
    'Get-CloudCartridgeCacheCleanupPlan',
    'Invoke-CloudCartridgeCacheCleanup',
    'Get-CloudCartridgeCatalogIdForPath',
    'Register-CloudCartridgeDownloadJob',
    'Get-CloudCartridgeDownloadJobs',
    'Set-CloudCartridgeDownloadJobState',
    'Enter-CloudCartridgeDownloadJob'
)
