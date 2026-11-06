Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Security
Import-Module (Join-Path $PSScriptRoot 'CloudCartridge.Core.psm1')

function New-CloudCartridgeRandomSecret {
    param([int]$Bytes = 32)
    $buffer = New-Object byte[] $Bytes
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($buffer) } finally { $rng.Dispose() }
    return [Convert]::ToBase64String($buffer).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function Get-CloudCartridgeSha256Text {
    param([string]$Value)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return (($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Value)) | ForEach-Object { $_.ToString('x2') }) -join '') } finally { $sha.Dispose() }
}

function Get-CloudCartridgeRecoveryVerifier {
    param([string]$RecoveryKey, [byte[]]$Salt, [int]$Iterations = 200000)
    $derive = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($RecoveryKey, $Salt, $Iterations, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    try { return [Convert]::ToBase64String($derive.GetBytes(32)) } finally { $derive.Dispose() }
}

function Read-CloudCartridgeHostDatabase {
    param([string]$DatabasePath)
    if (-not (Test-Path -LiteralPath $DatabasePath -PathType Leaf)) { return [PSCustomObject]@{ schema_version = 1; profiles = @(); invites = @() } }
    try {
        $database = Get-Content -LiteralPath $DatabasePath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $database.PSObject.Properties['profiles']) { throw 'Campo profiles ausente.' }
        if (-not $database.PSObject.Properties['invites']) { $database | Add-Member NoteProperty invites @() }
        return $database
    } catch { throw "Banco do Host invalido: $($_.Exception.Message)" }
}

function New-CloudCartridgeHostInvite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DatabasePath,
        [Parameter(Mandatory = $true)][string]$DisplayName,
        [string]$ProfileCode,
        [ValidateRange(1, 10080)][int]$ExpiresInMinutes = 60
    )
    $database = Read-CloudCartridgeHostDatabase -DatabasePath $DatabasePath
    $activeCount = @($database.profiles | Where-Object { $_.active }).Count
    $pendingCount = @($database.invites | Where-Object {
        -not $_.used_utc -and [DateTimeOffset]::Parse([string]$_.expires_utc).UtcDateTime -gt [DateTime]::UtcNow
    }).Count
    if ($activeCount + $pendingCount -ge 5) { throw 'Nao ha vaga disponivel para novo convite.' }
    if (-not $ProfileCode) { $ProfileCode = (New-CloudCartridgeRandomSecret -Bytes 8).ToUpperInvariant() -replace '[^A-Z0-9]', ''; $ProfileCode = $ProfileCode.PadRight(8, 'X').Substring(0, 8) }
    $ProfileCode = $ProfileCode.ToUpperInvariant()
    if ($ProfileCode -notmatch '^[A-Z0-9]{8}$') { throw 'profile_code deve conter exatamente 8 caracteres A-Z/0-9.' }
    if (@($database.profiles | Where-Object { $_.profile_code -ieq $ProfileCode }).Count -gt 0 -or @($database.invites | Where-Object { $_.profile_code -ieq $ProfileCode -and -not $_.used_utc }).Count -gt 0) { throw 'profile_code ja utilizado.' }
    $token = New-CloudCartridgeRandomSecret -Bytes 32
    $invite = [PSCustomObject][ordered]@{
        invite_id = [Guid]::NewGuid().ToString('D'); token_hash = Get-CloudCartridgeSha256Text $token
        display_name = $DisplayName; profile_code = $ProfileCode; created_utc = [DateTime]::UtcNow.ToString('o')
        expires_utc = [DateTime]::UtcNow.AddMinutes($ExpiresInMinutes).ToString('o'); used_utc = $null; profile_id = $null
    }
    $database.invites = @($database.invites) + $invite
    Write-CloudCartridgeJsonAtomic -InputObject $database -Path $DatabasePath -Depth 10
    return [PSCustomObject]@{ invite_id = $invite.invite_id; invite_token = $token; display_name = $DisplayName; profile_code = $ProfileCode; expires_utc = $invite.expires_utc }
}

function Use-CloudCartridgeHostInvite {
    [CmdletBinding()]
    param([string]$DatabasePath, [string]$DataRoot, [string]$InviteToken)
    if (-not $InviteToken) { throw 'Convite invalido ou expirado.' }
    $database = Read-CloudCartridgeHostDatabase -DatabasePath $DatabasePath
    $tokenHash = Get-CloudCartridgeSha256Text $InviteToken
    $invite = @($database.invites | Where-Object { $_.token_hash -eq $tokenHash -and -not $_.used_utc } | Select-Object -First 1)
    if ($invite.Count -eq 0) { throw 'Convite invalido, usado ou desconhecido.' }
    $expiresUtc = [DateTimeOffset]::Parse([string]$invite[0].expires_utc).UtcDateTime
    if ($expiresUtc -le [DateTime]::UtcNow) { throw 'Convite expirado.' }
    $profile = New-CloudCartridgeHostProfile -DatabasePath $DatabasePath -DataRoot $DataRoot -DisplayName $invite[0].display_name -ProfileCode $invite[0].profile_code
    $database = Read-CloudCartridgeHostDatabase -DatabasePath $DatabasePath
    $storedInvite = @($database.invites | Where-Object { $_.invite_id -eq $invite[0].invite_id } | Select-Object -First 1)
    $storedInvite[0].used_utc = [DateTime]::UtcNow.ToString('o')
    $storedInvite[0].profile_id = $profile.profile_id
    Write-CloudCartridgeJsonAtomic -InputObject $database -Path $DatabasePath -Depth 10
    return $profile
}

function Save-CloudCartridgeClientCredential {
    [CmdletBinding()]
    param([string]$CredentialPath, [string]$ProfileId, [string]$ProfileCode, [string]$DeviceToken, [string]$RecoveryKey, [scriptblock]$ProtectAction)
    if (-not $ProfileId -or -not $DeviceToken -or -not $RecoveryKey) { throw 'Credencial incompleta.' }
    $entropy = [System.Text.Encoding]::UTF8.GetBytes('CloudCartridge-v1')
    $protect = {
        param($value)
        if ($ProtectAction) { return [string](& $ProtectAction $value) }
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($value)
        [Convert]::ToBase64String([System.Security.Cryptography.ProtectedData]::Protect($bytes, $entropy, [System.Security.Cryptography.DataProtectionScope]::CurrentUser))
    }
    $record = [PSCustomObject]@{ schema_version = 1; profile_id = $ProfileId; profile_code = $ProfileCode; device_token_dpapi = (& $protect $DeviceToken); recovery_key_dpapi = (& $protect $RecoveryKey) }
    Write-CloudCartridgeJsonAtomic -InputObject $record -Path $CredentialPath -Depth 5
    return [PSCustomObject]@{ saved = $true; path = $CredentialPath; profile_id = $ProfileId }
}

function Get-CloudCartridgeClientCredential {
    [CmdletBinding()]
    param([string]$CredentialPath, [scriptblock]$UnprotectAction)
    $record = Get-Content -LiteralPath $CredentialPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $entropy = [System.Text.Encoding]::UTF8.GetBytes('CloudCartridge-v1')
    $unprotect = {
        param($value)
        if ($UnprotectAction) { return [string](& $UnprotectAction $value) }
        $plain = [System.Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String($value), $entropy, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
        [System.Text.Encoding]::UTF8.GetString($plain)
    }
    return [PSCustomObject]@{ profile_id = $record.profile_id; profile_code = $record.profile_code; device_token = (& $unprotect $record.device_token_dpapi); recovery_key = (& $unprotect $record.recovery_key_dpapi) }
}

function New-CloudCartridgeHostProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DatabasePath,
        [Parameter(Mandatory = $true)][string]$DataRoot,
        [Parameter(Mandatory = $true)][string]$DisplayName,
        [string]$ProfileCode
    )
    if ([string]::IsNullOrWhiteSpace($DisplayName)) { throw 'Nome do perfil obrigatorio.' }
    $database = Read-CloudCartridgeHostDatabase -DatabasePath $DatabasePath
    if (@($database.profiles | Where-Object { $_.active }).Count -ge 5) { throw 'Limite de cinco convidados ativos atingido.' }
    if (-not $ProfileCode) { $ProfileCode = (New-CloudCartridgeRandomSecret -Bytes 8).ToUpperInvariant() -replace '[^A-Z0-9]', ''; $ProfileCode = $ProfileCode.PadRight(8, 'X').Substring(0, 8) }
    $ProfileCode = $ProfileCode.ToUpperInvariant()
    if ($ProfileCode -notmatch '^[A-Z0-9]{8}$') { throw 'profile_code deve conter exatamente 8 caracteres A-Z/0-9.' }
    if (@($database.profiles | Where-Object { $_.profile_code -ieq $ProfileCode }).Count -gt 0) { throw 'profile_code ja utilizado.' }

    $profileId = [Guid]::NewGuid().ToString('D')
    $recoveryKey = New-CloudCartridgeRandomSecret -Bytes 32
    $salt = New-Object byte[] 16
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($salt) } finally { $rng.Dispose() }
    $deviceToken = New-CloudCartridgeRandomSecret -Bytes 32
    $profile = [PSCustomObject][ordered]@{
        profile_id = $profileId; profile_code = $ProfileCode; display_name = $DisplayName; active = $true
        recovery_salt = [Convert]::ToBase64String($salt); recovery_iterations = 200000
        recovery_verifier = Get-CloudCartridgeRecoveryVerifier -RecoveryKey $recoveryKey -Salt $salt
        devices = @([PSCustomObject]@{ device_id = [Guid]::NewGuid().ToString('D'); token_hash = Get-CloudCartridgeSha256Text $deviceToken; active = $true; created_utc = [DateTime]::UtcNow.ToString('o') })
        created_utc = [DateTime]::UtcNow.ToString('o'); revoked_utc = $null
    }
    $database.profiles = @($database.profiles) + $profile
    Write-CloudCartridgeJsonAtomic -InputObject $database -Path $DatabasePath -Depth 10
    $saveRoot = Join-Path (Join-Path $DataRoot 'saves') $profileId
    foreach ($folder in @('retroarch', 'standalone', 'mister', 'versions')) { New-Item -ItemType Directory -Path (Join-Path $saveRoot $folder) -Force | Out-Null }
    return [PSCustomObject]@{ profile_id = $profileId; profile_code = $ProfileCode; display_name = $DisplayName; recovery_key = $recoveryKey; device_token = $deviceToken; save_root = $saveRoot }
}

function Test-CloudCartridgeHostDeviceCredential {
    [CmdletBinding()]
    param([string]$DatabasePath, [string]$ProfileId, [string]$DeviceToken)
    if (-not $ProfileId -or -not $DeviceToken) { return $false }
    $database = Read-CloudCartridgeHostDatabase -DatabasePath $DatabasePath
    $profile = @($database.profiles | Where-Object { $_.profile_id -eq $ProfileId -and $_.active } | Select-Object -First 1)
    if ($profile.Count -eq 0) { return $false }
    $tokenHash = Get-CloudCartridgeSha256Text $DeviceToken
    return @($profile[0].devices | Where-Object { $_.active -and $_.token_hash -eq $tokenHash }).Count -gt 0
}

function New-CloudCartridgeRecoveredDevice {
    [CmdletBinding()]
    param([string]$DatabasePath, [string]$ProfileCode, [string]$RecoveryKey)
    $database = Read-CloudCartridgeHostDatabase -DatabasePath $DatabasePath
    $profile = @($database.profiles | Where-Object { $_.profile_code -ieq $ProfileCode -and $_.active } | Select-Object -First 1)
    if ($profile.Count -eq 0 -or -not $RecoveryKey) { throw 'Recuperacao negada.' }
    $salt = [Convert]::FromBase64String([string]$profile[0].recovery_salt)
    $verifier = Get-CloudCartridgeRecoveryVerifier -RecoveryKey $RecoveryKey -Salt $salt -Iterations ([int]$profile[0].recovery_iterations)
    if ($verifier -ne $profile[0].recovery_verifier) { throw 'Recuperacao negada.' }
    $token = New-CloudCartridgeRandomSecret -Bytes 32
    $device = [PSCustomObject]@{ device_id = [Guid]::NewGuid().ToString('D'); token_hash = Get-CloudCartridgeSha256Text $token; active = $true; created_utc = [DateTime]::UtcNow.ToString('o') }
    $profile[0].devices = @($profile[0].devices) + $device
    Write-CloudCartridgeJsonAtomic -InputObject $database -Path $DatabasePath -Depth 10
    return [PSCustomObject]@{ profile_id = $profile[0].profile_id; device_id = $device.device_id; device_token = $token }
}

function Get-CloudCartridgeAuthorizedSavePath {
    [CmdletBinding()]
    param([string]$DatabasePath, [string]$DataRoot, [string]$ProfileId, [string]$DeviceToken, [string]$RelativePath)
    if (-not (Test-CloudCartridgeHostDeviceCredential -DatabasePath $DatabasePath -ProfileId $ProfileId -DeviceToken $DeviceToken)) { throw 'Acesso nao autorizado.' }
    $profileRoot = Join-Path (Join-Path $DataRoot 'saves') $ProfileId
    $target = Join-Path $profileRoot $RelativePath
    if (-not (Test-CloudCartridgePathWithinRoot -Path $target -Root $profileRoot)) { throw 'Caminho de save fora do perfil.' }
    return [System.IO.Path]::GetFullPath($target)
}

function Revoke-CloudCartridgeHostProfile {
    [CmdletBinding()]
    param([string]$DatabasePath, [string]$ProfileCode)
    $database = Read-CloudCartridgeHostDatabase -DatabasePath $DatabasePath
    $profile = @($database.profiles | Where-Object { $_.profile_code -ieq $ProfileCode -and $_.active } | Select-Object -First 1)
    if ($profile.Count -eq 0) { throw 'Perfil ativo nao encontrado.' }
    $profile[0].active = $false
    $profile[0].revoked_utc = [DateTime]::UtcNow.ToString('o')
    foreach ($device in @($profile[0].devices)) { $device.active = $false }
    Write-CloudCartridgeJsonAtomic -InputObject $database -Path $DatabasePath -Depth 10
    return $profile[0]
}

Export-ModuleMember -Function @('New-CloudCartridgeHostInvite', 'Use-CloudCartridgeHostInvite', 'New-CloudCartridgeHostProfile', 'Test-CloudCartridgeHostDeviceCredential', 'New-CloudCartridgeRecoveredDevice', 'Get-CloudCartridgeAuthorizedSavePath', 'Revoke-CloudCartridgeHostProfile', 'Save-CloudCartridgeClientCredential', 'Get-CloudCartridgeClientCredential')
