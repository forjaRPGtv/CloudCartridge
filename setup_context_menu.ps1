# ==============================================================================
# setup_context_menu.ps1 - Gerenciador do Menu de Contexto do Windows Explorer
# CloudROM Open-Source Edition
# ==============================================================================

[CmdletBinding()]
param (
    [switch]$Uninstall = $false
)

$scriptDir = $PSScriptRoot
$telemetryScript = Join-Path $scriptDir "CloudROM_Telemetry.ps1"

$extensions = @(
    '.7z', '.zip', '.chd', '.iso', '.cso', '.bin', '.cue', 
    '.pbp', '.wbfs', '.rvz', '.nes', '.sfc', '.smc', '.gba', 
    '.gb', '.gbc', '.n64', '.z64', '.v64', '.nds'
)

if ($Uninstall) {
    Write-Host "Removendo atalhos do CloudROM do menu de contexto..." -ForegroundColor Yellow
    foreach ($ext in $extensions) {
        $keyPlay = "HKCU:\Software\Classes\SystemFileAssociations\$ext\shell\CloudROM_Play"
        $keyFree = "HKCU:\Software\Classes\SystemFileAssociations\$ext\shell\CloudROM_Free"
        if (Test-Path -LiteralPath $keyPlay) { Remove-Item -LiteralPath $keyPlay -Recurse -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $keyFree) { Remove-Item -LiteralPath $keyFree -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Write-Host "Menu de contexto removido com sucesso!" -ForegroundColor Green
    exit 0
}

Write-Host "Registrando atalhos do CloudROM no menu de contexto do Windows..." -ForegroundColor Cyan

foreach ($ext in $extensions) {
    # 1. Jogar com CloudROM Telemetria
    $keyPlay = "HKCU:\Software\Classes\SystemFileAssociations\$ext\shell\CloudROM_Play"
    $cmdPlay = "$keyPlay\command"
    if (-not (Test-Path -LiteralPath $cmdPlay)) {
        New-Item -Path $cmdPlay -Force | Out-Null
    }
    Set-ItemProperty -LiteralPath $keyPlay -Name '(Default)' -Value "Jogar com CloudCartridge Telemetria"
    Set-ItemProperty -LiteralPath $cmdPlay -Name '(Default)' -Value "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$telemetryScript`" -FilePath `"%1`" -LaunchAfter"

    # 2. Liberar Espaço no PC (Manter na Nuvem)
    $keyFree = "HKCU:\Software\Classes\SystemFileAssociations\$ext\shell\CloudROM_Free"
    $cmdFree = "$keyFree\command"
    if (-not (Test-Path -LiteralPath $cmdFree)) {
        New-Item -Path $cmdFree -Force | Out-Null
    }
    Set-ItemProperty -LiteralPath $keyFree -Name '(Default)' -Value "CloudCartridge: Liberar Espaço no PC (Manter na Nuvem)"
    Set-ItemProperty -LiteralPath $cmdFree -Name '(Default)' -Value "attrib.exe +u -p `"%1`""
}

Write-Host "Menu de contexto registrado com sucesso para $($extensions.Count) tipos de ROMs e ISOs!" -ForegroundColor Green
