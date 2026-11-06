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

    $retentionDays = [int]$defaults.retention_days
    if ($retentionDays -lt 1 -or $retentionDays -gt 3650) {
        throw 'retention_days deve estar entre 1 e 3650.'
    }
    $maxDownloads = [int]$defaults.max_concurrent_downloads
    if ($maxDownloads -lt 1 -or $maxDownloads -gt 16) {
        throw 'max_concurrent_downloads deve estar entre 1 e 16.'
    }

    return [PSCustomObject]$defaults
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

Export-ModuleMember -Function @(
    'Get-CloudCartridgeConfig',
    'Test-CloudCartridgePathWithinRoot',
    'Write-CloudCartridgeJsonAtomic',
    'Copy-CloudCartridgeSaveSafely'
)
