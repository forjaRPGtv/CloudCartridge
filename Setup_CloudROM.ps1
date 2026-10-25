# ==============================================================================
# Setup_CloudROM.ps1 - Assistente de Configuração Inicial do CloudCartridge
# Open-Source Edition
# ==============================================================================

[CmdletBinding()]
param ()

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Clear-Host
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "       CloudCartridge - Assistente de Configuração Inicial       " -ForegroundColor Yellow
Write-Host "    Jogue na Nuvem via Google Drive sem ocupar espaço no SSD    " -ForegroundColor Gray
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host ""

$scriptDir = $PSScriptRoot
$configFile = Join-Path $scriptDir "config.json"
$configTemplate = Join-Path $scriptDir "config.template.json"

# 1. Definir Caminho do Google Drive
Write-Host "[1/4] Localização das suas ROMs no Google Drive:" -ForegroundColor Cyan
Write-Host "Exemplo: G:\Meu Drive\_ISOS_ROMS_ ou G:\.shortcut-targets-by-id\..." -ForegroundColor Gray

$defaultDrive = "G:\Meu Drive\_ISOS_ROMS_"
$gDrivePath = Read-Host "Caminho da pasta no Google Drive [Pressione Enter para '$defaultDrive']"
if ([string]::IsNullOrWhiteSpace($gDrivePath)) {
    $gDrivePath = $defaultDrive
}

while (-not (Test-Path -LiteralPath $gDrivePath)) {
    Write-Host "Aviso: O caminho informado não foi encontrado no momento." -ForegroundColor Yellow
    Write-Host "Certifique-se de que o Google Drive para Desktop está aberto e montado." -ForegroundColor Gray
    $retry = Read-Host "Deseja continuar com esse caminho mesmo assim? (S/N)"
    if ($retry -match '^(s|sim|y|yes)$') { break }
    $gDrivePath = Read-Host "Digite o caminho correto da pasta no Google Drive"
}

# 2. Definir Caminho Local das Junções de ROMs
Write-Host "`n[2/4] Onde você deseja acessar suas ROMs no PC (Pastas Virtuais):" -ForegroundColor Cyan
Write-Host "Exemplo: Z:\_ISOS_ROMS_ ou C:\Games\ROMs" -ForegroundColor Gray

$defaultLocal = "Z:\_ISOS_ROMS_"
$localPath = Read-Host "Caminho da pasta local [Pressione Enter para '$defaultLocal']"
if ([string]::IsNullOrWhiteSpace($localPath)) {
    $localPath = $defaultLocal
}

if (-not (Test-Path -LiteralPath $localPath)) {
    New-Item -ItemType Directory -Path $localPath -Force | Out-Null
    Write-Host "Criada pasta local: $localPath" -ForegroundColor Green
}

# 3. Localizar RetroArch
Write-Host "`n[3/4] Executável do RetroArch:" -ForegroundColor Cyan
$defaultRA = "C:\RetroArch-Win64\retroarch.exe"
$raPath = $defaultRA
if (-not (Test-Path -LiteralPath $raPath)) {
    $raPath = Read-Host "Digite o caminho completo do retroarch.exe"
} else {
    Write-Host "RetroArch detectado automaticamente em: $raPath" -ForegroundColor Green
}

# 4. Salvar config.json
$settings = [PSCustomObject]@{
    google_drive_roms_path     = $gDrivePath
    local_roms_path            = $localPath
    retroarch_path             = $raPath
    retention_days             = 3
    enable_cloud_save_sync     = $true
    enable_multi_disc_prefetch = $true
    enable_telemetry_hud       = $true
}

$settings | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $configFile -Encoding UTF8
Write-Host "`nConfigurações gravadas com sucesso em config.json!" -ForegroundColor Green

# 5. Criar Junções NTFS para os Consoles
Write-Host "`n[5/5] Criando Junções NTFS para seus consoles..." -ForegroundColor Cyan
if (Test-Path -LiteralPath $gDrivePath) {
    $subDirs = Get-ChildItem -LiteralPath $gDrivePath -Directory
    $count = 0
    foreach ($dir in $subDirs) {
        $name = $dir.Name
        # Pular pastas de controle
        if ($name -like '_RA_*' -or $name -like '_INSTALLERS*' -or $name -eq 'cheats') {
            continue
        }
        $destJunction = Join-Path $localPath $name
        if (-not (Test-Path -LiteralPath $destJunction)) {
            New-Item -ItemType Junction -Path $destJunction -Target $dir.FullName | Out-Null
            Write-Host "  -> Junção criada: $name" -ForegroundColor Green
            $count++
        }
    }
    Write-Host "Total de $count consoles conectados com 0 bytes ocupados!" -ForegroundColor Green
}

# 6. Registrar Menu de Contexto (Opcional)
$askMenu = Read-Host "`nDeseja adicionar atalhos do CloudROM no botão direito do mouse? (S/N)"
if ($askMenu -match '^(s|sim|y|yes)$') {
    $contextScript = Join-Path $scriptDir "setup_context_menu.ps1"
    if (Test-Path -LiteralPath $contextScript) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $contextScript
    }
}

Write-Host "`n=================================================================" -ForegroundColor Cyan
Write-Host "            Instalação e Configuração Concluídas!                " -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "Você já pode iniciar seus jogos usando: Jogar.cmd" -ForegroundColor White
Write-Host "Pressione qualquer tecla para finalizar..." -ForegroundColor Gray
[void][System.Console]::ReadKey($true)
