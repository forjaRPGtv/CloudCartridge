Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'CloudCartridge.Core.psm1')
Import-Module (Join-Path $PSScriptRoot 'CloudCartridge.Host.psm1')

function New-CloudCartridgeApiResponse {
    param([int]$Status, [string]$Code, $Data = $null)
    return [PSCustomObject]@{ status = $Status; body = [PSCustomObject]@{ ok = $Status -ge 200 -and $Status -lt 300; code = $Code; data = $Data } }
}

function Test-CloudCartridgeHostBindAddress {
    [CmdletBinding()]
    param([string]$Address, [switch]$AllowLan)
    $parsed = $null
    if (-not [System.Net.IPAddress]::TryParse($Address, [ref]$parsed)) { return $false }
    if ([System.Net.IPAddress]::IsLoopback($parsed)) { return $true }
    if (-not $AllowLan -or $parsed.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) { return $false }
    $bytes = $parsed.GetAddressBytes()
    return ($bytes[0] -eq 10) -or ($bytes[0] -eq 192 -and $bytes[1] -eq 168) -or ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) -or ($bytes[0] -eq 100 -and $bytes[1] -ge 64 -and $bytes[1] -le 127)
}

function Write-CloudCartridgeHostAudit {
    param([string]$AuditPath, [string]$ClientAddress, [string]$ProfileId, [string]$Method, [string]$Path, [int]$Status, [string]$Code)
    $directory = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($AuditPath))
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $record = [PSCustomObject][ordered]@{ timestamp_utc = [DateTime]::UtcNow.ToString('o'); client = $ClientAddress; profile_id = $ProfileId; method = $Method; path = $Path; status = $Status; code = $Code }
    [System.IO.File]::AppendAllText($AuditPath, (($record | ConvertTo-Json -Compress) + [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))
}

function Test-CloudCartridgeApiRateLimit {
    param([string]$StatePath, [string]$ClientAddress, [int]$Limit = 30, [int]$WindowSeconds = 60)
    $now = [DateTime]::UtcNow
    $state = if (Test-Path -LiteralPath $StatePath -PathType Leaf) { Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json } else { [PSCustomObject]@{ requests = @() } }
    $cutoff = $now.AddSeconds(-$WindowSeconds)
    $requests = @($state.requests | Where-Object { (ConvertTo-CloudCartridgeUtcDateTime $_.timestamp_utc) -gt $cutoff })
    $clientRequests = @($requests | Where-Object { $_.client -eq $ClientAddress })
    if ($clientRequests.Count -ge $Limit) { return $false }
    $requests += [PSCustomObject]@{ client = $ClientAddress; timestamp_utc = $now.ToString('o') }
    $state.requests = $requests
    Write-CloudCartridgeJsonAtomic -InputObject $state -Path $StatePath -Depth 5
    return $true
}

function Test-CloudCartridgeApiNonce {
    param([string]$StatePath, [string]$ProfileId, [string]$Nonce, [long]$TimestampUnix)
    $now = [DateTimeOffset]::UtcNow
    if ([math]::Abs($now.ToUnixTimeSeconds() - $TimestampUnix) -gt 300) { return [PSCustomObject]@{ valid = $false; code = 'stale_request' } }
    if ($Nonce -notmatch '^[A-Za-z0-9_-]{16,128}$') { return [PSCustomObject]@{ valid = $false; code = 'invalid_nonce' } }
    $state = if (Test-Path -LiteralPath $StatePath -PathType Leaf) { Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json } else { [PSCustomObject]@{ nonces = @() } }
    $cutoff = [DateTime]::UtcNow.AddMinutes(-10)
    $nonces = @($state.nonces | Where-Object { (ConvertTo-CloudCartridgeUtcDateTime $_.seen_utc) -gt $cutoff })
    if (@($nonces | Where-Object { $_.profile_id -eq $ProfileId -and $_.nonce -eq $Nonce }).Count -gt 0) { return [PSCustomObject]@{ valid = $false; code = 'replay_detected' } }
    $nonces += [PSCustomObject]@{ profile_id = $ProfileId; nonce = $Nonce; seen_utc = [DateTime]::UtcNow.ToString('o') }
    $state.nonces = $nonces
    Write-CloudCartridgeJsonAtomic -InputObject $state -Path $StatePath -Depth 5
    return [PSCustomObject]@{ valid = $true; code = 'ok' }
}

function Invoke-CloudCartridgeHostApiRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Path,
        [hashtable]$Headers = @{},
        $Body = $null,
        [Parameter(Mandatory = $true)][string]$DatabasePath,
        [Parameter(Mandatory = $true)][string]$DataRoot,
        [string]$CatalogIndexPath,
        [string]$ClientAddress = 'unknown',
        [int]$RateLimit = 30
    )
    $stateRoot = Join-Path $DataRoot 'admin\runtime'
    $auditPath = Join-Path $DataRoot 'admin\audit\host-api.jsonl'
    $response = $null
    $profileId = if ($Headers.ContainsKey('X-Profile-Id')) { [string]$Headers['X-Profile-Id'] } else { '' }
    try {
        if (-not (Test-CloudCartridgeApiRateLimit -StatePath (Join-Path $stateRoot 'rate.json') -ClientAddress $ClientAddress -Limit $RateLimit)) {
            $response = New-CloudCartridgeApiResponse 429 'rate_limited'; return $response
        }
        if ($Method -eq 'GET' -and $Path -eq '/health') { $response = New-CloudCartridgeApiResponse 200 'ok' ([PSCustomObject]@{ service = 'CloudCartridge Host'; status = 'ok' }); return $response }
        $authorization = if ($Headers.ContainsKey('Authorization')) { [string]$Headers['Authorization'] } else { '' }
        $deviceToken = if ($authorization -match '^Bearer\s+(.+)$') { $matches[1] } else { '' }
        if (-not (Test-CloudCartridgeHostDeviceCredential -DatabasePath $DatabasePath -ProfileId $profileId -DeviceToken $deviceToken)) {
            $response = New-CloudCartridgeApiResponse 401 'unauthorized'; return $response
        }
        $nonce = if ($Headers.ContainsKey('X-Request-Nonce')) { [string]$Headers['X-Request-Nonce'] } else { '' }
        $timestampText = if ($Headers.ContainsKey('X-Request-Timestamp')) { [string]$Headers['X-Request-Timestamp'] } else { '' }
        $timestamp = 0L
        if (-not [long]::TryParse($timestampText, [ref]$timestamp)) { $response = New-CloudCartridgeApiResponse 400 'invalid_timestamp'; return $response }
        $nonceResult = Test-CloudCartridgeApiNonce -StatePath (Join-Path $stateRoot 'nonces.json') -ProfileId $profileId -Nonce $nonce -TimestampUnix $timestamp
        if (-not $nonceResult.valid) { $response = New-CloudCartridgeApiResponse 409 $nonceResult.code; return $response }

        if ($Method -eq 'GET' -and $Path -eq '/v1/profile') {
            $profile = Get-CloudCartridgeHostProfileSummary -DatabasePath $DatabasePath -ProfileId $profileId
            $response = New-CloudCartridgeApiResponse 200 'ok' $profile; return $response
        }
        if ($Method -eq 'POST' -and $Path -eq '/v1/saves/resolve') {
            $relativePath = if ($Body -and $Body.PSObject.Properties['relative_path']) { [string]$Body.relative_path } else { '' }
            if (-not $relativePath) { $response = New-CloudCartridgeApiResponse 400 'relative_path_required'; return $response }
            $savePath = Get-CloudCartridgeAuthorizedSavePath -DatabasePath $DatabasePath -DataRoot $DataRoot -ProfileId $profileId -DeviceToken $deviceToken -RelativePath $relativePath
            $response = New-CloudCartridgeApiResponse 200 'ok' ([PSCustomObject]@{ relative_path = $relativePath; resolved_path = $savePath }); return $response
        }
        if ($Method -eq 'GET' -and $Path -match '^/v1/catalog/([a-zA-Z0-9_-]+)$') {
            if (-not $CatalogIndexPath -or -not (Test-Path -LiteralPath $CatalogIndexPath -PathType Leaf)) { $response = New-CloudCartridgeApiResponse 503 'catalog_unavailable'; return $response }
            $catalog = Get-Content -LiteralPath $CatalogIndexPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $item = @($catalog.items | Where-Object { $_.catalog_id -eq $matches[1] } | Select-Object -First 1)
            if ($item.Count -eq 0) { $response = New-CloudCartridgeApiResponse 404 'catalog_item_not_found'; return $response }
            $response = New-CloudCartridgeApiResponse 200 'ok' $item[0]; return $response
        }
        $response = New-CloudCartridgeApiResponse 404 'not_found'; return $response
    } catch {
        $response = New-CloudCartridgeApiResponse 400 'request_rejected' ([PSCustomObject]@{ message = $_.Exception.Message })
        return $response
    } finally {
        if ($response) { Write-CloudCartridgeHostAudit -AuditPath $auditPath -ClientAddress $ClientAddress -ProfileId $profileId -Method $Method -Path $Path -Status $response.status -Code $response.body.code }
    }
}

Export-ModuleMember -Function @('Test-CloudCartridgeHostBindAddress', 'Invoke-CloudCartridgeHostApiRequest')
