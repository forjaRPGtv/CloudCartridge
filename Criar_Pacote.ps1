[CmdletBinding()]
param(
    [string]$OutputPath,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($PSScriptRoot)
if (-not $OutputPath) {
    $OutputPath = Join-Path $root ("dist\CloudCartridge-{0}.zip" -f [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'))
}
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

$excludedDirectories = @('.git', '.tmp', 'host-data', 'backups', 'dist', '.cache', 'logs')
$excludedNames = @('config.json', 'standalone_emulators.json', '.cache_registry.json', '.download_jobs.json')
$files = @(Get-ChildItem -LiteralPath $root -File -Recurse | Where-Object {
    $relative = $_.FullName.Substring($root.Length).TrimStart('\', '/')
    $parts = @($relative -split '[\\/]')
    -not ($parts | Where-Object { $_ -in $excludedDirectories }) -and
    $_.Name -notin $excludedNames -and
    $_.Extension -notin @('.log', '.tmp', '.bak', '.zip')
})

$plan = [PSCustomObject][ordered]@{
    applied = $false
    dry_run = -not $Apply
    output_path = $OutputPath
    file_count = $files.Count
    excluded_runtime_data = $true
}
if (-not $Apply) { $plan | ConvertTo-Json; exit 0 }
if (Test-Path -LiteralPath $OutputPath) { throw "O pacote ja existe: $OutputPath" }

$outputDirectory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$stage = Join-Path ([System.IO.Path]::GetTempPath()) ('cloudcartridge-package-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage -Force | Out-Null
try {
    $manifest = @()
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($root.Length).TrimStart('\', '/')
        $target = Join-Path $stage $relative
        $targetDirectory = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $targetDirectory)) { New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null }
        Copy-Item -LiteralPath $file.FullName -Destination $target
        $hash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
        $manifest += "$hash  $($relative.Replace('\', '/'))"
    }
    $manifest | Set-Content -LiteralPath (Join-Path $stage 'MANIFEST-SHA256.txt') -Encoding UTF8
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $OutputPath -CompressionLevel Optimal
} finally {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
$plan.applied = $true
$plan | Add-Member NoteProperty sha256 ((Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash.ToLowerInvariant())
$plan | ConvertTo-Json

