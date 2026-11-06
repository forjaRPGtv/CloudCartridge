[CmdletBinding()]
param(
    [string]$DatabasePath = (Join-Path $PSScriptRoot 'host-data\admin\users.json'),
    [ValidateRange(1, 300)][int]$RefreshSeconds = 3,
    [switch]$Once,
    [switch]$NoColor
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'CloudCartridge.Host.psm1') -Force

function Write-MonitorLine {
    param([string]$Text, [ConsoleColor]$Color = [ConsoleColor]::Gray)
    if ($NoColor -or [Console]::IsOutputRedirected) { Write-Output $Text }
    else { Write-Host $Text -ForegroundColor $Color }
}

do {
    $status = Get-CloudCartridgeHostStatus -DatabasePath $DatabasePath
    if (-not $Once -and -not [Console]::IsOutputRedirected) { Clear-Host }
    Write-MonitorLine 'CloudCartridge Host — monitor privado' Cyan
    Write-MonitorLine ("Atualizado (UTC): {0}" -f [DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss')) DarkGray
    Write-MonitorLine ("Convidados ativos: {0}/{1} | Vagas: {2} | Convites pendentes: {3}" -f $status.active_guests, $status.capacity, $status.free_slots, $status.pending_invites) Yellow
    Write-MonitorLine ''
    if (@($status.profiles).Count -eq 0) {
        Write-MonitorLine 'Nenhum perfil cadastrado.' DarkGray
    } else {
        Write-MonitorLine ('{0,-22} {1,-10} {2,-9} {3,8}' -f 'NOME', 'CODIGO', 'ESTADO', 'DISPOSITIVOS') Cyan
        foreach ($profile in @($status.profiles | Sort-Object display_name)) {
            $state = if ($profile.active) { 'ativo' } else { 'revogado' }
            Write-MonitorLine ('{0,-22} {1,-10} {2,-9} {3,8}' -f ([string]$profile.display_name).Substring(0, [Math]::Min(22, ([string]$profile.display_name).Length)), $profile.profile_code, $state, $profile.devices)
        }
    }
    Write-MonitorLine ''
    Write-MonitorLine 'O painel nunca mostra tokens, recovery keys ou verificadores.' DarkGray
    if (-not $Once) { Start-Sleep -Seconds $RefreshSeconds }
} while (-not $Once)

