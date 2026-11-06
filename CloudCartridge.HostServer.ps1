[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$DatabasePath,
    [Parameter(Mandatory = $true)][string]$DataRoot,
    [string]$CatalogIndexPath = '',
    [string]$ListenAddress = '127.0.0.1',
    [ValidateRange(1024, 65535)][int]$Port = 42731,
    [switch]$AllowLan,
    [switch]$Once
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'CloudCartridge.HostApi.psm1') -Force

if (-not (Test-CloudCartridgeHostBindAddress -Address $ListenAddress -AllowLan:$AllowLan)) {
    throw 'Endereco recusado. Use loopback ou IP privado com -AllowLan; bind publico e proibido.'
}

$ipAddress = [System.Net.IPAddress]::Parse($ListenAddress)
$listener = New-Object System.Net.Sockets.TcpListener($ipAddress, $Port)
try {
    $listener.Start()
    Write-Host "CloudCartridge Host ativo em http://${ListenAddress}:$Port/" -ForegroundColor Green
    if ($AllowLan) { Write-Warning 'LAN habilitada: use somente rede confiavel ou VPN; nao publique esta porta na internet.' }
    do {
        $client = $listener.AcceptTcpClient()
        $stream = $null
        $reader = $null
        try {
            $stream = $client.GetStream()
            $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8, $false, 4096, $true)
            $requestLine = $reader.ReadLine()
            $requestParts = @($requestLine -split ' ')
            if ($requestParts.Count -lt 2) { throw 'Linha HTTP invalida.' }
            $method = $requestParts[0]
            $requestPath = ([Uri]("http://localhost" + $requestParts[1])).AbsolutePath
            $headers = @{}
            while ($true) {
                $line = $reader.ReadLine()
                if ([string]::IsNullOrEmpty($line)) { break }
                $separator = $line.IndexOf(':')
                if ($separator -gt 0) { $headers[$line.Substring(0, $separator).Trim()] = $line.Substring($separator + 1).Trim() }
            }
            $contentLength = 0
            if ($headers.ContainsKey('Content-Length')) { $contentLength = [int]$headers['Content-Length'] }
            if ($contentLength -gt 1MB) { throw 'Corpo da requisicao excede 1 MB.' }
            $body = $null
            if ($contentLength -gt 0) {
                $buffer = New-Object char[] $contentLength
                $read = 0
                while ($read -lt $contentLength) { $count = $reader.Read($buffer, $read, $contentLength - $read); if ($count -le 0) { break }; $read += $count }
                $text = New-Object string($buffer, 0, $read)
                if ($text) { $body = $text | ConvertFrom-Json }
            }
            $remoteAddress = ([System.Net.IPEndPoint]$client.Client.RemoteEndPoint).Address.ToString()
            $result = Invoke-CloudCartridgeHostApiRequest -Method $method -Path $requestPath -Headers $headers -Body $body -DatabasePath $DatabasePath -DataRoot $DataRoot -CatalogIndexPath $CatalogIndexPath -ClientAddress $remoteAddress
            $json = $result.body | ConvertTo-Json -Depth 10 -Compress
            $payload = [System.Text.Encoding]::UTF8.GetBytes($json)
            $reason = switch ($result.status) { 200 { 'OK' } 400 { 'Bad Request' } 401 { 'Unauthorized' } 404 { 'Not Found' } 409 { 'Conflict' } 429 { 'Too Many Requests' } 503 { 'Service Unavailable' } default { 'Response' } }
            $responseHeaders = "HTTP/1.1 $($result.status) $reason`r`nContent-Type: application/json; charset=utf-8`r`nContent-Length: $($payload.Length)`r`nConnection: close`r`n`r`n"
            $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($responseHeaders)
            $stream.Write($headerBytes, 0, $headerBytes.Length)
            $stream.Write($payload, 0, $payload.Length)
            $stream.Flush()
        } finally {
            if ($reader) { $reader.Dispose() }
            if ($stream) { $stream.Dispose() }
            $client.Close()
        }
    } while (-not $Once)
} finally {
    $listener.Stop()
}
