[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $repoRoot 'CloudCartridge.Core.psm1') -Force
$script:passed = 0
$script:failed = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Invoke-Test {
    param([string]$Name, [scriptblock]$Body)
    try {
        & $Body
        $script:passed++
        Write-Host "PASS $Name" -ForegroundColor Green
    } catch {
        $script:failed++
        Write-Host "FAIL $Name :: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.ScriptStackTrace) {
            Write-Host "  $($_.ScriptStackTrace)" -ForegroundColor DarkRed
        }
    }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('cloudcartridge-tests-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
    Invoke-Test 'PowerShell scripts parse as UTF-8' {
        $scripts = Get-ChildItem -LiteralPath $repoRoot -Recurse -File | Where-Object { $_.Extension -in @('.ps1', '.psm1') }
        foreach ($scriptFile in $scripts) {
            $text = [System.IO.File]::ReadAllText($scriptFile.FullName, [System.Text.Encoding]::UTF8)
            $tokens = $null
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errors) | Out-Null
            Assert-True ($errors.Count -eq 0) "Erro de sintaxe em $($scriptFile.Name)"
        }
    }

    Invoke-Test 'Tracked JSON files are valid' {
        Get-ChildItem -LiteralPath $repoRoot -File -Filter '*.json' | ForEach-Object {
            Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null
        }
    }

    Invoke-Test 'Default config is stable' {
        $config = Get-CloudCartridgeConfig -ConfigPath (Join-Path $tempRoot 'missing.json')
        Assert-True ($config.retention_days -eq 3) 'Retencao padrao incorreta.'
        Assert-True ($config.max_concurrent_downloads -eq 3) 'Concorrencia padrao incorreta.'
    }

    Invoke-Test 'Invalid config is rejected' {
        $configPath = Join-Path $tempRoot 'invalid.json'
        [System.IO.File]::WriteAllText($configPath, '{"retention_days":0}', [System.Text.Encoding]::UTF8)
        $rejected = $false
        try { Get-CloudCartridgeConfig -ConfigPath $configPath | Out-Null } catch { $rejected = $true }
        Assert-True $rejected 'Configuracao invalida foi aceita.'
    }

    Invoke-Test 'Managed path guard rejects traversal and prefix collision' {
        $root = Join-Path $tempRoot 'cache'
        Assert-True (Test-CloudCartridgePathWithinRoot -Path (Join-Path $root 'Console\Game.chd') -Root $root) 'Caminho interno rejeitado.'
        Assert-True (-not (Test-CloudCartridgePathWithinRoot -Path (Join-Path $tempRoot 'cache-evil\Game.chd') -Root $root)) 'Colisao de prefixo aceita.'
        Assert-True (-not (Test-CloudCartridgePathWithinRoot -Path (Join-Path $root '..\outside.chd') -Root $root)) 'Traversal aceito.'
    }

    Invoke-Test 'Atomic JSON write leaves no partial residue' {
        $jsonPath = Join-Path $tempRoot 'state\registry.json'
        Write-CloudCartridgeJsonAtomic -InputObject ([PSCustomObject]@{ ok = $true; count = 2 }) -Path $jsonPath
        $loaded = Get-Content -LiteralPath $jsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-True ($loaded.ok -eq $true -and $loaded.count -eq 2) 'JSON atomico invalido.'
        $jsonDirectory = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($jsonPath))
        Assert-True (@(Get-ChildItem -LiteralPath $jsonDirectory -Filter '*.partial.*').Count -eq 0) 'Residuo partial encontrado.'
    }

    Invoke-Test 'Save sync creates, deduplicates and versions conflicts' {
        $source = Join-Path $tempRoot 'source.srm'
        $destinationRoot = Join-Path $tempRoot 'remote-saves'
        $destination = Join-Path $destinationRoot 'retroarch\game.srm'
        [System.IO.File]::WriteAllText($source, 'save-v1', [System.Text.Encoding]::UTF8)
        $created = Copy-CloudCartridgeSaveSafely -SourcePath $source -DestinationPath $destination -DestinationRoot $destinationRoot
        Assert-True ($created.status -eq 'created') 'Primeira copia nao criada.'
        $unchanged = Copy-CloudCartridgeSaveSafely -SourcePath $source -DestinationPath $destination -DestinationRoot $destinationRoot
        Assert-True ($unchanged.status -eq 'unchanged') 'Save identico nao deduplicado.'
        [System.IO.File]::WriteAllText($source, 'save-v2', [System.Text.Encoding]::UTF8)
        $updated = Copy-CloudCartridgeSaveSafely -SourcePath $source -DestinationPath $destination -DestinationRoot $destinationRoot
        Assert-True ($updated.status -eq 'updated_with_backup') 'Conflito nao versionado.'
        Assert-True (Test-Path -LiteralPath $updated.backup_path -PathType Leaf) 'Backup do conflito ausente.'
        Assert-True ((Get-Content -LiteralPath $updated.backup_path -Raw) -eq 'save-v1') 'Backup anterior incorreto.'
        Assert-True ((Get-Content -LiteralPath $destination -Raw) -eq 'save-v2') 'Destino atualizado incorretamente.'
    }

    Invoke-Test 'Publish script has no force push' {
        $publishText = Get-Content -LiteralPath (Join-Path $repoRoot 'Publicar_no_GitHub.cmd') -Raw
        Assert-True ($publishText -notmatch 'push[^\r\n]*--force') 'Force push ainda presente.'
    }

    Invoke-Test 'Watcher resolves scripts from its own directory' {
        $watcherText = Get-Content -LiteralPath (Join-Path $repoRoot 'CloudROM_Watcher.ps1') -Raw -Encoding UTF8
        Assert-True ($watcherText -match '\$PSScriptRoot') 'Watcher nao usa PSScriptRoot.'
        Assert-True ($watcherText -notmatch '_Arthur_Projetos') 'Watcher ainda aponta para a copia antiga.'
    }

    Invoke-Test 'Feature flags are enforced by runtime scripts' {
        $launcherText = Get-Content -LiteralPath (Join-Path $repoRoot 'CloudROM_Launcher.ps1') -Raw -Encoding UTF8
        $telemetryText = Get-Content -LiteralPath (Join-Path $repoRoot 'CloudROM_Telemetry.ps1') -Raw -Encoding UTF8
        Assert-True ($launcherText -match 'enable_cloud_save_sync') 'Launcher ignora flag de save sync.'
        Assert-True ($telemetryText -match 'enable_cloud_save_sync') 'Telemetria ignora flag de save sync.'
        Assert-True ($telemetryText -match 'enable_multi_disc_prefetch') 'Telemetria ignora flag multidisco.'
        Assert-True ($launcherText -match 'cleanup_enabled') 'Launcher ignora flag de limpeza.'
    }

    Invoke-Test 'Launcher and telemetry smoke use isolated fixtures' {
        $fixtureRoot = Join-Path $tempRoot 'runtime-fixture'
        $fixtureLibrary = Join-Path $fixtureRoot 'library'
        $fixtureSystem = Join-Path $fixtureLibrary 'Test System'
        New-Item -ItemType Directory -Path $fixtureSystem -Force | Out-Null
        foreach ($name in @('CloudCartridge.Core.psm1', 'CloudROM_Launcher.ps1', 'CloudROM_Telemetry.ps1')) {
            Copy-Item -LiteralPath (Join-Path $repoRoot $name) -Destination $fixtureRoot
        }
        $fixtureConfig = [PSCustomObject]@{
            google_drive_roms_path     = ''
            local_roms_path            = $fixtureLibrary
            retroarch_path             = (Join-Path $fixtureRoot 'missing-retroarch.exe')
            retention_days             = 3
            cleanup_enabled            = $true
            enable_cloud_save_sync     = $false
            enable_multi_disc_prefetch = $false
            enable_telemetry_hud       = $false
            max_concurrent_downloads   = 3
        }
        Write-CloudCartridgeJsonAtomic -InputObject $fixtureConfig -Path (Join-Path $fixtureRoot 'config.json')

        $previousPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $launcherOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fixtureRoot 'CloudROM_Launcher.ps1') -PurgeOnly 2>&1
        $launcherExitCode = $LASTEXITCODE
        $ErrorActionPreference = $previousPreference
        Assert-True ($launcherExitCode -eq 0) "Smoke do Launcher falhou: $($launcherOutput -join ' ')"

        $fakeGame = Join-Path $fixtureSystem 'Fixture Game.chd'
        [System.IO.File]::WriteAllBytes($fakeGame, [byte[]](1, 2, 3, 4, 5, 6, 7, 8))
        $ErrorActionPreference = 'Continue'
        $telemetryOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fixtureRoot 'CloudROM_Telemetry.ps1') -FilePath $fakeGame -PrefetchOnly 2>&1
        $telemetryExitCode = $LASTEXITCODE
        $ErrorActionPreference = $previousPreference
        Assert-True ($telemetryExitCode -eq 0) "Smoke da Telemetria falhou: $($telemetryOutput -join ' ')"

        $registryPath = Join-Path $fixtureLibrary '.cache_registry.json'
        Assert-True (Test-Path -LiteralPath $registryPath -PathType Leaf) 'Telemetria nao criou registro isolado.'
        $registry = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-True (@($registry.games.PSObject.Properties).Count -eq 1) 'Registro isolado nao recebeu o jogo ficticio.'
    }

    Invoke-Test 'CLI doctor emits versioned JSON' {
        $previousPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $doctorOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'CloudCartridge.ps1') doctor --json 2>&1
        $doctorExitCode = $LASTEXITCODE
        $ErrorActionPreference = $previousPreference
        Assert-True ($doctorExitCode -eq 0) "Doctor falhou: $($doctorOutput -join ' ')"
        $doctor = ($doctorOutput -join "`n") | ConvertFrom-Json
        Assert-True ($doctor.schema_version -eq 1) 'Schema JSON do doctor incorreto.'
        Assert-True ($doctor.retroarch.state -in @('detected', 'not_installed')) 'Estado do RetroArch invalido.'
    }
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`nRESULT passed=$script:passed failed=$script:failed"
if ($script:failed -gt 0) { exit 1 }
exit 0
