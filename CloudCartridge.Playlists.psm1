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
    return @(Get-ChildItem -LiteralPath $RomRoot -Recurse -File | Where-Object { $_.Extension.ToLowerInvariant() -in $Extensions } | ForEach-Object {
        [PSCustomObject]@{ path = $_.FullName; label = $_.BaseName }
    })
}

Export-ModuleMember -Function @('Merge-CloudCartridgePlaylist', 'Get-CloudCartridgeRomCandidates')
