Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'CloudCartridge.Core.psm1')

function Get-CloudCartridgePlaylist {
    param([string]$PlaylistPath, [string]$DefaultCorePath = 'DETECT', [string]$DefaultCoreName = 'DETECT')
    if (-not (Test-Path -LiteralPath $PlaylistPath -PathType Leaf)) {
        return [PSCustomObject][ordered]@{
            version = '1.5'; default_core_path = $DefaultCorePath; default_core_name = $DefaultCoreName
            label_display_mode = 0; right_thumbnail_mode = 0; left_thumbnail_mode = 0
            thumbnail_match_mode = 0; sort_mode = 0; items = @()
        }
    }
    try {
        $playlist = Get-Content -LiteralPath $PlaylistPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $playlist.PSObject.Properties['items']) { throw 'Campo items ausente.' }
        return $playlist
    } catch { throw "Playlist invalida: $($_.Exception.Message)" }
}

function Merge-CloudCartridgePlaylist {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$PlaylistPath,
        [Parameter(Mandatory = $true)][object[]]$DiscoveredItems,
        [string]$DefaultCorePath = 'DETECT',
        [string]$DefaultCoreName = 'DETECT',
        [switch]$Apply
    )
    $playlist = Get-CloudCartridgePlaylist -PlaylistPath $PlaylistPath -DefaultCorePath $DefaultCorePath -DefaultCoreName $DefaultCoreName
    $items = @($playlist.items)
    $paths = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($item in $items) { if ($item.path) { $null = $paths.Add([System.IO.Path]::GetFullPath([string]$item.path)) } }
    $added = @()
    foreach ($candidate in @($DiscoveredItems | Sort-Object path)) {
        if (-not $candidate.path) { continue }
        $fullPath = [System.IO.Path]::GetFullPath([string]$candidate.path)
        if (-not $paths.Add($fullPath)) { continue }
        $candidateLabel = if ($candidate.PSObject.Properties['label']) { [string]$candidate.label } else { '' }
        $candidateCorePath = if ($candidate.PSObject.Properties['core_path']) { [string]$candidate.core_path } else { '' }
        $candidateCoreName = if ($candidate.PSObject.Properties['core_name']) { [string]$candidate.core_name } else { '' }
        $candidateCrc32 = if ($candidate.PSObject.Properties['crc32']) { [string]$candidate.crc32 } else { '' }
        $candidateDbName = if ($candidate.PSObject.Properties['db_name']) { [string]$candidate.db_name } else { '' }
        $entry = [PSCustomObject][ordered]@{
            path = $fullPath
            label = if ($candidateLabel) { $candidateLabel } else { [System.IO.Path]::GetFileNameWithoutExtension($fullPath) }
            core_path = if ($candidateCorePath) { $candidateCorePath } else { $DefaultCorePath }
            core_name = if ($candidateCoreName) { $candidateCoreName } else { $DefaultCoreName }
            crc32 = if ($candidateCrc32) { $candidateCrc32 } else { 'DETECT' }
            db_name = if ($candidateDbName) { $candidateDbName } else { [System.IO.Path]::GetFileName($PlaylistPath) }
        }
        $items += $entry
        $added += $entry
    }
    $playlist.items = @($items | Sort-Object @{ Expression = { [string]$_.label } }, @{ Expression = { [string]$_.path } })
    $result = [PSCustomObject]@{ applied = [bool]$Apply; dry_run = -not $Apply; added = $added.Count; total = $playlist.items.Count; playlist_path = $PlaylistPath; playlist = $playlist }
    if ($Apply -and $added.Count -gt 0) { Write-CloudCartridgeJsonAtomic -InputObject $playlist -Path $PlaylistPath -Depth 10 }
    return $result
}

function Get-CloudCartridgeRomCandidates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RomRoot,
        [string[]]$Extensions = @('.7z', '.zip', '.chd', '.rvz', '.iso', '.gdi', '.cue', '.m3u', '.bin', '.rom')
    )
    if (-not (Test-Path -LiteralPath $RomRoot -PathType Container)) { return @() }
    $allFiles = @(Get-ChildItem -LiteralPath $RomRoot -Recurse -File | Where-Object { $_.Extension.ToLowerInvariant() -in $Extensions })
    $discMembers = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($manifest in @($allFiles | Where-Object { $_.Extension -ieq '.m3u' })) {
        foreach ($line in Get-Content -LiteralPath $manifest.FullName -Encoding UTF8) {
            $reference = $line.Trim()
            if (-not $reference -or $reference.StartsWith('#')) { continue }
            $resolved = if ([System.IO.Path]::IsPathRooted($reference)) { $reference } else { Join-Path $manifest.DirectoryName $reference }
            if ((Test-CloudCartridgePathWithinRoot -Path $resolved -Root $RomRoot) -and (Test-Path -LiteralPath $resolved -PathType Leaf)) {
                $null = $discMembers.Add([System.IO.Path]::GetFullPath($resolved))
            }
        }
    }
    return @($allFiles | Where-Object { -not $discMembers.Contains($_.FullName) } | ForEach-Object {
        [PSCustomObject]@{ path = $_.FullName; label = $_.BaseName }
    })
}

function Update-CloudCartridgeCatalogIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$LibraryRoot,
        [Parameter(Mandatory = $true)][string]$IndexPath,
        [string[]]$Extensions = @('.7z', '.zip', '.chd', '.rvz', '.iso', '.gdi', '.cue', '.m3u', '.bin', '.rom'),
        [switch]$Apply
    )
    $previous = @{}
    if (Test-Path -LiteralPath $IndexPath -PathType Leaf) {
        $oldIndex = Get-Content -LiteralPath $IndexPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($entry in @($oldIndex.items)) { $previous[[string]$entry.path] = $entry }
    }
    $items = @()
    $reused = 0
    $updated = 0
    foreach ($file in @(Get-ChildItem -LiteralPath $LibraryRoot -Recurse -File | Where-Object { $_.Extension.ToLowerInvariant() -in $Extensions } | Sort-Object FullName)) {
        $old = $previous[$file.FullName]
        $modified = $file.LastWriteTimeUtc.ToString('o')
        $oldModified = $null
        if ($old) {
            try { $oldModified = (ConvertTo-CloudCartridgeUtcDateTime $old.modified_utc).ToString('o') } catch { $oldModified = $null }
        }
        if ($old -and [long]$old.size -eq [long]$file.Length -and $oldModified -eq $modified) {
            $items += $old
            $reused++
        } else {
            $relative = $file.FullName.Substring([System.IO.Path]::GetFullPath($LibraryRoot).TrimEnd('\').Length).TrimStart('\')
            $system = if ($relative.Contains('\')) { $relative.Split('\')[0] } else { '' }
            $items += [PSCustomObject][ordered]@{
                catalog_id = Get-CloudCartridgeCatalogIdForPath -Path $file.FullName
                system = $system
                path = $file.FullName
                label = $file.BaseName
                extension = $file.Extension.ToLowerInvariant()
                size = [long]$file.Length
                modified_utc = $modified
            }
            $updated++
        }
    }
    $index = [PSCustomObject][ordered]@{ schema_version = 1; library_root = [System.IO.Path]::GetFullPath($LibraryRoot); generated_utc = [DateTime]::UtcNow.ToString('o'); items = $items }
    if ($Apply -and ($updated -gt 0 -or $items.Count -ne $previous.Count)) { Write-CloudCartridgeJsonAtomic -InputObject $index -Path $IndexPath -Depth 8 }
    return [PSCustomObject]@{ applied = [bool]$Apply; dry_run = -not $Apply; total = $items.Count; reused = $reused; updated = $updated; index_path = $IndexPath; index = $index }
}

function Get-CloudCartridgeCatalogInventory {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$IndexPath)
    if (-not (Test-Path -LiteralPath $IndexPath -PathType Leaf)) { throw 'Indice de catalogo nao encontrado.' }
    $index = Get-Content -LiteralPath $IndexPath -Raw -Encoding UTF8 | ConvertFrom-Json
    return @($index.items | Group-Object system | Sort-Object Name | ForEach-Object {
        $groupItems = @($_.Group)
        [PSCustomObject][ordered]@{
            system = $_.Name
            titles = $groupItems.Count
            bytes = [long](($groupItems | Measure-Object -Property size -Sum).Sum)
            extensions = @($groupItems | Group-Object extension | Sort-Object Name | ForEach-Object { [PSCustomObject]@{ extension = $_.Name; count = $_.Count } })
        }
    })
}

function Test-CloudCartridgePngFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $item = Get-Item -LiteralPath $Path
    if ($item.Length -lt 8 -or $item.Length -gt 20MB) { return $false }
    $expected = [byte[]](137, 80, 78, 71, 13, 10, 26, 10)
    $actual = New-Object byte[] 8
    $stream = [System.IO.File]::OpenRead($Path)
    try { if ($stream.Read($actual, 0, 8) -ne 8) { return $false } } finally { $stream.Dispose() }
    for ($index = 0; $index -lt 8; $index++) { if ($actual[$index] -ne $expected[$index]) { return $false } }
    return $true
}

function Invoke-CloudCartridgeThumbnailDownload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [scriptblock]$WebRequestAction
    )
    $uri = [Uri]$Url
    if ($uri.Scheme -ne 'https' -or $uri.Host -ne 'thumbnails.libretro.com') { throw 'Thumbnail recusada: origem nao oficial.' }
    if (Test-Path -LiteralPath $TargetPath -PathType Leaf) { return [PSCustomObject]@{ status = 'preserved_existing'; path = $TargetPath } }
    $directory = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($TargetPath))
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $temporary = "$TargetPath.partial.$([Guid]::NewGuid().ToString('N'))"
    try {
        if ($WebRequestAction) { & $WebRequestAction $Url $temporary } else { Invoke-WebRequest -Uri $Url -OutFile $temporary -UseBasicParsing -TimeoutSec 30 }
        if (-not (Test-CloudCartridgePngFile -Path $temporary)) { throw 'Thumbnail baixada nao e PNG valida.' }
        Move-Item -LiteralPath $temporary -Destination $TargetPath
        return [PSCustomObject]@{ status = 'downloaded'; path = $TargetPath; bytes = (Get-Item -LiteralPath $TargetPath).Length }
    } finally { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
}

function Repair-CloudCartridgeMissingThumbnails {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$PlaylistItems,
        [Parameter(Mandatory = $true)][string]$ThumbnailDirectory,
        [scriptblock]$Fetcher,
        [switch]$Apply
    )
    $results = @()
    foreach ($item in $PlaylistItems) {
        $safeLabel = ([string]$item.label) -replace '[&*/:`"<>?\\|]', '_'
        $target = Join-Path $ThumbnailDirectory "$safeLabel.png"
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            $results += [PSCustomObject]@{ label = $item.label; path = $target; decision = 'preserved_existing' }
            continue
        }
        if (-not $Apply) {
            $results += [PSCustomObject]@{ label = $item.label; path = $target; decision = 'missing' }
            continue
        }
        if (-not $Fetcher) { throw 'Fetcher obrigatorio para aplicar reparo de thumbnail.' }
        New-Item -ItemType Directory -Path $ThumbnailDirectory -Force | Out-Null
        $temporary = "$target.partial"
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
        $fetched = [bool](& $Fetcher $item $temporary)
        if ($fetched -and (Test-CloudCartridgePngFile -Path $temporary)) {
            Move-Item -LiteralPath $temporary -Destination $target
            $results += [PSCustomObject]@{ label = $item.label; path = $target; decision = 'downloaded' }
        } else {
            Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
            $results += [PSCustomObject]@{ label = $item.label; path = $target; decision = 'failed' }
        }
    }
    return $results
}

Export-ModuleMember -Function @('Merge-CloudCartridgePlaylist', 'Get-CloudCartridgeRomCandidates', 'Update-CloudCartridgeCatalogIndex', 'Get-CloudCartridgeCatalogInventory', 'Invoke-CloudCartridgeThumbnailDownload', 'Repair-CloudCartridgeMissingThumbnails')
