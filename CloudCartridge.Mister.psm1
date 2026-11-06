Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'CloudCartridge.Core.psm1')

function Get-CloudCartridgeMisterState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$HostName,
        [Parameter(Mandatory = $true)][string[]]$AuthorizedHosts,
        [scriptblock]$ProbeAction
    )
    if ($HostName -notin $AuthorizedHosts) { return [PSCustomObject]@{ state = 'unauthorized'; host = $HostName; connected = $false; cores = @(); free_bytes = $null; transport = $null } }
    if (-not $ProbeAction) { return [PSCustomObject]@{ state = 'offline'; host = $HostName; connected = $false; cores = @(); free_bytes = $null; transport = $null } }
    try {
        $probe = & $ProbeAction $HostName
        if (-not $probe -or -not $probe.connected) { throw 'offline' }
        return [PSCustomObject]@{ state = 'connected'; host = $HostName; connected = $true; cores = @($probe.cores); free_bytes = [long]$probe.free_bytes; transport = [string]$probe.transport }
    } catch {
        return [PSCustomObject]@{ state = 'offline'; host = $HostName; connected = $false; cores = @(); free_bytes = $null; transport = $null }
    }
}

function Get-CloudCartridgeMisterCompatibility {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$CompatibilityPath,
        [Parameter(Mandatory = $true)][string]$System,
        [Parameter(Mandatory = $true)][string]$Extension,
        [string[]]$InstalledCores = @()
    )
    $rules = Get-Content -LiteralPath $CompatibilityPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($System -in @($rules.pc_only_systems)) { return [PSCustomObject]@{ compatible = $false; state = 'pc_only'; reason = 'platform_not_supported_by_mister'; matched_core = $null; folder_per_game = $false } }
    $property = $rules.systems.PSObject.Properties[$System]
    if (-not $property) { return [PSCustomObject]@{ compatible = $false; state = 'unknown_system'; reason = 'no_compatibility_rule'; matched_core = $null; folder_per_game = $false } }
    $rule = $property.Value
    $matchedCore = @($InstalledCores | Where-Object { $installed = $_; @($rule.core_aliases | Where-Object { $installed -ieq $_ }).Count -gt 0 } | Select-Object -First 1)
    if ($matchedCore.Count -eq 0) { return [PSCustomObject]@{ compatible = $false; state = 'core_missing'; reason = 'required_core_not_installed'; matched_core = $null; folder_per_game = [bool]$rule.folder_per_game } }
    $normalizedExtension = if ($Extension.StartsWith('.')) { $Extension.ToLowerInvariant() } else { ".$($Extension.ToLowerInvariant())" }
    if ($normalizedExtension -notin @($rule.extensions)) { return [PSCustomObject]@{ compatible = $false; state = 'format_unsupported'; reason = 'format_not_supported_by_installed_core'; matched_core = $matchedCore[0]; folder_per_game = [bool]$rule.folder_per_game } }
    return [PSCustomObject]@{ compatible = $true; state = 'compatible'; reason = 'core_and_format_match'; matched_core = $matchedCore[0]; folder_per_game = [bool]$rule.folder_per_game }
}

function Invoke-CloudCartridgeMisterDistribution {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$LibraryRoot,
        [Parameter(Mandatory = $true)][string]$System,
        [Parameter(Mandatory = $true)]$MisterState,
        [Parameter(Mandatory = $true)][string]$CompatibilityPath,
        [Parameter(Mandatory = $true)][string]$RemoteRoot,
        [scriptblock]$TransferAction,
        [switch]$Apply
    )
    if (-not (Test-CloudCartridgePathWithinRoot -Path $SourcePath -Root $LibraryRoot)) { throw 'Arquivo fora da biblioteca autorizada.' }
    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) { throw 'Arquivo de origem nao encontrado.' }
    if (-not $MisterState.connected) { return [PSCustomObject]@{ applied = $false; state = 'offline'; pc_operation_blocked = $false; source = $SourcePath; destination = $null } }
    $compatibility = Get-CloudCartridgeMisterCompatibility -CompatibilityPath $CompatibilityPath -System $System -Extension ([System.IO.Path]::GetExtension($SourcePath)) -InstalledCores @($MisterState.cores)
    if (-not $compatibility.compatible) { return [PSCustomObject]@{ applied = $false; state = $compatibility.state; pc_operation_blocked = $false; source = $SourcePath; destination = $null } }
    $gameName = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath)
    $destinationDirectory = if ($compatibility.folder_per_game) { Join-Path (Join-Path $RemoteRoot $System) $gameName } else { Join-Path $RemoteRoot $System }
    $destination = Join-Path $destinationDirectory ([System.IO.Path]::GetFileName($SourcePath))
    if (-not $Apply) { return [PSCustomObject]@{ applied = $false; state = 'planned'; pc_operation_blocked = $false; source = $SourcePath; destination = $destination; core = $compatibility.matched_core } }
    if (-not $TransferAction) { throw 'TransferAction obrigatoria para distribuir ao MiSTer.' }
    $success = [bool](& $TransferAction $SourcePath $destination)
    return [PSCustomObject]@{ applied = $success; state = if ($success) { 'transferred' } else { 'failed' }; pc_operation_blocked = $false; source = $SourcePath; destination = $destination; core = $compatibility.matched_core }
}

Export-ModuleMember -Function @('Get-CloudCartridgeMisterState', 'Get-CloudCartridgeMisterCompatibility', 'Invoke-CloudCartridgeMisterDistribution')
