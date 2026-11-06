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

    Invoke-Test 'Cache policy supports preview, apply and off' {
        $policyPath = Join-Path $tempRoot 'policy\config.json'
        $preview = Update-CloudCartridgeConfig -ConfigPath $policyPath -Values @{ retention_days = 14; cleanup_enabled = $true } -DryRun
        Assert-True ($preview.retention_days -eq 14 -and $preview.cleanup_enabled) 'Preview de 14 dias incorreto.'
        Assert-True (-not (Test-Path -LiteralPath $policyPath)) 'Dry-run gravou config.json.'

        $disabled = Update-CloudCartridgeConfig -ConfigPath $policyPath -Values @{ retention_days = $null; cleanup_enabled = $false }
        Assert-True ($null -eq $disabled.retention_days -and -not $disabled.cleanup_enabled) 'Politica off incorreta.'
        Assert-True (Test-Path -LiteralPath $policyPath -PathType Leaf) 'Aplicacao nao criou config.json.'

        $enabled = Update-CloudCartridgeConfig -ConfigPath $policyPath -Values @{ retention_days = 7; cleanup_enabled = $true }
        Assert-True ($enabled.retention_days -eq 7 -and $enabled.cleanup_enabled) 'Reativacao em 7 dias incorreta.'
    }

    Invoke-Test 'Managed path guard rejects traversal and prefix collision' {
        $root = Join-Path $tempRoot 'cache'
        Assert-True (Test-CloudCartridgePathWithinRoot -Path (Join-Path $root 'Console\Game.chd') -Root $root) 'Caminho interno rejeitado.'
        Assert-True (-not (Test-CloudCartridgePathWithinRoot -Path (Join-Path $tempRoot 'cache-evil\Game.chd') -Root $root)) 'Colisao de prefixo aceita.'
        Assert-True (-not (Test-CloudCartridgePathWithinRoot -Path (Join-Path $root '..\outside.chd') -Root $root)) 'Traversal aceito.'
    }

    Invoke-Test 'Portable emulator detection refreshes without installing' {
        $portablePath = Join-Path $tempRoot 'portable\retroarch.exe'
        $missing = Find-CloudCartridgeExecutable -CandidatePaths @($portablePath)
        Assert-True ($missing.state -eq 'not_installed' -and $null -eq $missing.path) 'Ausencia foi detectada incorretamente.'
        Assert-True (-not (Test-Path -LiteralPath $portablePath)) 'Detector instalou ou criou executavel.'

        New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($portablePath)) -Force | Out-Null
        [System.IO.File]::WriteAllBytes($portablePath, [byte[]](77, 90, 0, 0))
        $detected = Find-CloudCartridgeExecutable -CandidatePaths @($portablePath)
        Assert-True ($detected.state -eq 'detected' -and $detected.path -eq [System.IO.Path]::GetFullPath($portablePath)) 'Executavel portatil nao foi detectado apos refresh.'
    }

    Invoke-Test 'Atomic JSON write leaves no partial residue' {
        $jsonPath = Join-Path $tempRoot 'state\registry.json'
        Write-CloudCartridgeJsonAtomic -InputObject ([PSCustomObject]@{ ok = $true; count = 2 }) -Path $jsonPath
        $loaded = Get-Content -LiteralPath $jsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-True ($loaded.ok -eq $true -and $loaded.count -eq 2) 'JSON atomico invalido.'
        $jsonDirectory = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($jsonPath))
        Assert-True (@(Get-ChildItem -LiteralPath $jsonDirectory -Filter '*.partial.*').Count -eq 0) 'Residuo partial encontrado.'
    }

    Invoke-Test 'Cache pin previews and applies only inside managed root' {
        $cacheRoot = Join-Path $tempRoot 'pin-cache'
        $gamePath = Join-Path $cacheRoot 'Console\Game.chd'
        $registryPath = Join-Path $cacheRoot '.cache_registry.json'
        $games = [PSCustomObject]@{}
        $games | Add-Member -MemberType NoteProperty -Name $gamePath -Value ([PSCustomObject]@{ catalog_id = 'game-001'; is_pinned = $false; status = 'local_cached' })
        Write-CloudCartridgeJsonAtomic -InputObject ([PSCustomObject]@{ retention_days = 3; games = $games }) -Path $registryPath

        $preview = Set-CloudCartridgeCachePin -RegistryPath $registryPath -ManagedRoot $cacheRoot -Identifier 'game-001' -Pinned $true -DryRun
        Assert-True (-not $preview.applied -and $preview.pinned) 'Preview de pin incorreto.'
        $afterPreview = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-True (-not [bool]$afterPreview.games.$gamePath.is_pinned) 'Preview alterou o registro.'

        $applied = Set-CloudCartridgeCachePin -RegistryPath $registryPath -ManagedRoot $cacheRoot -Identifier $gamePath -Pinned $true
        Assert-True ($applied.applied) 'Pin nao foi aplicado.'
        $afterApply = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-True ([bool]$afterApply.games.$gamePath.is_pinned) 'Registro nao persistiu pin.'

        $outsideGames = [PSCustomObject]@{}
        $outsidePath = Join-Path $tempRoot 'outside\Game.chd'
        $outsideGames | Add-Member -MemberType NoteProperty -Name $outsidePath -Value ([PSCustomObject]@{ catalog_id = 'outside-001'; is_pinned = $false })
        Write-CloudCartridgeJsonAtomic -InputObject ([PSCustomObject]@{ games = $outsideGames }) -Path $registryPath
        $rejected = $false
        try { Set-CloudCartridgeCachePin -RegistryPath $registryPath -ManagedRoot $cacheRoot -Identifier 'outside-001' -Pinned $true | Out-Null } catch { $rejected = $true }
        Assert-True $rejected 'Pin fora da raiz gerenciada foi aceito.'
    }

    Invoke-Test 'Cache cleanup preserves recent, pinned and unsafe entries' {
        $cleanupRoot = Join-Path $tempRoot 'cleanup-cache'
        $cleanupRegistry = Join-Path $cleanupRoot '.cache_registry.json'
        $now = [DateTime]::UtcNow
        $recentPath = Join-Path $cleanupRoot 'Console\Recent.chd'
        $expiredPath = Join-Path $cleanupRoot 'Console\Expired.chd'
        $pinnedPath = Join-Path $cleanupRoot 'Console\Pinned.chd'
        $protectedPath = Join-Path $cleanupRoot '_RA_SAVES\Save.srm'
        $outsidePath = Join-Path $tempRoot 'outside-cache\Outside.chd'
        foreach ($path in @($recentPath, $expiredPath, $pinnedPath, $protectedPath, $outsidePath)) {
            New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($path)) -Force | Out-Null
            [System.IO.File]::WriteAllBytes($path, [byte[]](1, 2, 3))
        }
        $games = [PSCustomObject]@{}
        $games | Add-Member NoteProperty $recentPath ([PSCustomObject]@{ title = 'Recent'; last_played = $now.AddDays(-1).ToString('o'); status = 'local_cached'; is_pinned = $false })
        $games | Add-Member NoteProperty $expiredPath ([PSCustomObject]@{ title = 'Expired'; last_played = $now.AddDays(-5).ToString('o'); status = 'local_cached'; is_pinned = $false })
        $games | Add-Member NoteProperty $pinnedPath ([PSCustomObject]@{ title = 'Pinned'; last_played = $now.AddDays(-20).ToString('o'); status = 'local_cached'; is_pinned = $true })
        $games | Add-Member NoteProperty $protectedPath ([PSCustomObject]@{ title = 'Save'; last_played = $now.AddDays(-20).ToString('o'); status = 'local_cached'; is_pinned = $false })
        $games | Add-Member NoteProperty $outsidePath ([PSCustomObject]@{ title = 'Outside'; last_played = $now.AddDays(-20).ToString('o'); status = 'local_cached'; is_pinned = $false })
        Write-CloudCartridgeJsonAtomic -InputObject ([PSCustomObject]@{ games = $games }) -Path $cleanupRegistry

        $preview = @(Invoke-CloudCartridgeCacheCleanup -RegistryPath $cleanupRegistry -ManagedRoot $cleanupRoot -RetentionDays 3 -CleanupEnabled $true -DryRun)
        Assert-True (($preview | Where-Object path -eq $expiredPath).decision -eq 'dehydrate') 'Expirado nao entrou no plano.'
        Assert-True (($preview | Where-Object path -eq $recentPath).reason -eq 'not_expired') 'Recente seria removido.'
        Assert-True (($preview | Where-Object path -eq $pinnedPath).reason -eq 'pinned') 'Fixado seria removido.'
        Assert-True (($preview | Where-Object path -eq $protectedPath).reason -eq 'outside_managed_cache') 'Save protegido seria removido.'
        Assert-True (($preview | Where-Object path -eq $outsidePath).reason -eq 'outside_managed_cache') 'Arquivo externo seria removido.'

        $applied = @(Invoke-CloudCartridgeCacheCleanup -RegistryPath $cleanupRegistry -ManagedRoot $cleanupRoot -RetentionDays 3 -CleanupEnabled $true -DehydrateAction { param($path) return $path -eq $expiredPath })
        Assert-True (($applied | Where-Object path -eq $expiredPath).decision -eq 'dehydrated') 'Expirado nao foi desidratado.'
        $after = Get-Content -LiteralPath $cleanupRegistry -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-True ($after.games.$expiredPath.status -eq 'cloud_only') 'Registro nao confirmou desidratacao.'
        Assert-True ($after.games.$recentPath.status -eq 'local_cached') 'Recente mudou de estado.'

        $after.games.$expiredPath.status = 'local_cached'
        Write-CloudCartridgeJsonAtomic -InputObject $after -Path $cleanupRegistry
        $failed = @(Invoke-CloudCartridgeCacheCleanup -RegistryPath $cleanupRegistry -ManagedRoot $cleanupRoot -RetentionDays 3 -CleanupEnabled $true -DehydrateAction { return $false })
        Assert-True (($failed | Where-Object path -eq $expiredPath).decision -eq 'failed') 'Falha de desidratacao nao foi reportada.'
        $afterFailure = Get-Content -LiteralPath $cleanupRegistry -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-True ($afterFailure.games.$expiredPath.status -eq 'local_cached') 'Falha marcou cache como removido.'
    }

    Invoke-Test 'CLI cache cleanup previews without changing registry' {
        $cliRoot = Join-Path $tempRoot 'cleanup-cli'
        $cliLibrary = Join-Path $cliRoot 'library'
        $cliGame = Join-Path $cliLibrary 'Console\Expired.chd'
        $cliRegistry = Join-Path $cliLibrary '.cache_registry.json'
        New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($cliGame)) -Force | Out-Null
        [System.IO.File]::WriteAllBytes($cliGame, [byte[]](1, 2, 3))
        Copy-Item -LiteralPath (Join-Path $repoRoot 'CloudCartridge.Core.psm1') -Destination $cliRoot
        Copy-Item -LiteralPath (Join-Path $repoRoot 'CloudCartridge.ps1') -Destination $cliRoot
        Write-CloudCartridgeJsonAtomic -InputObject ([PSCustomObject]@{
            local_roms_path = $cliLibrary
            retention_days = 3
            cleanup_enabled = $true
        }) -Path (Join-Path $cliRoot 'config.json')
        $games = [PSCustomObject]@{}
        $games | Add-Member NoteProperty $cliGame ([PSCustomObject]@{
            title = 'Expired'
            last_played = ([DateTime]::UtcNow.AddDays(-5).ToString('o'))
            status = 'local_cached'
            is_pinned = $false
        })
        Write-CloudCartridgeJsonAtomic -InputObject ([PSCustomObject]@{ games = $games }) -Path $cliRegistry

        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $cliRoot 'CloudCartridge.ps1') cache cleanup --json 2>&1
        Assert-True ($LASTEXITCODE -eq 0) "CLI cleanup falhou: $($output -join ' ')"
        $result = ($output -join "`n") | ConvertFrom-Json
        Assert-True ($result.dry_run -and -not $result.applied -and $result.candidates -eq 1) 'CLI nao apresentou a limpeza esperada.'
        $afterPreview = Get-Content -LiteralPath $cliRegistry -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-True ($afterPreview.games.$cliGame.status -eq 'local_cached') 'CLI em preview alterou o registro.'
    }

    Invoke-Test 'Download journal deduplicates and orders priorities' {
        $downloadRoot = Join-Path $tempRoot 'download-cache'
        $journalPath = Join-Path $downloadRoot '.download_jobs.json'
        $gameA = Join-Path $downloadRoot 'Console\Game A.chd'
        $gameB = Join-Path $downloadRoot 'Console\Game B.chd'
        $gameC = Join-Path $downloadRoot 'Console\Game C.chd'

        $first = Register-CloudCartridgeDownloadJob -JournalPath $journalPath -ManagedRoot $downloadRoot -FilePath $gameA -CatalogId 'game-a' -Priority prefetch
        $duplicate = Register-CloudCartridgeDownloadJob -JournalPath $journalPath -ManagedRoot $downloadRoot -FilePath $gameA -CatalogId 'game-a' -Priority current
        Assert-True (-not $first.deduplicated -and $duplicate.deduplicated) 'Job duplicado nao foi deduplicado.'
        Assert-True ($first.job.job_id -eq $duplicate.job.job_id) 'Deduplicacao criou outro job.'

        $null = Register-CloudCartridgeDownloadJob -JournalPath $journalPath -ManagedRoot $downloadRoot -FilePath $gameB -CatalogId 'game-b' -Priority current
        $null = Register-CloudCartridgeDownloadJob -JournalPath $journalPath -ManagedRoot $downloadRoot -FilePath $gameC -CatalogId 'game-c' -Priority resume
        $jobs = @(Get-CloudCartridgeDownloadJobs -JournalPath $journalPath)
        Assert-True ($jobs.Count -eq 3) 'Quantidade de jobs incorreta.'
        Assert-True ($jobs[0].catalog_id -eq 'game-b' -and $jobs[1].catalog_id -eq 'game-c' -and $jobs[2].catalog_id -eq 'game-a') 'Prioridades em ordem incorreta.'

        $completed = Set-CloudCartridgeDownloadJobState -JournalPath $journalPath -JobId $first.job.job_id -State completed -BytesDownloaded 10 -TotalBytes 10
        Assert-True ($completed.state -eq 'completed' -and $completed.bytes_downloaded -eq 10) 'Estado do job nao persistiu.'
        $replacement = Register-CloudCartridgeDownloadJob -JournalPath $journalPath -ManagedRoot $downloadRoot -FilePath $gameA -CatalogId 'game-a' -Priority current
        Assert-True (-not $replacement.deduplicated -and $replacement.job.job_id -ne $first.job.job_id) 'Job concluido bloqueou nova solicitacao.'

        $schedulePath = Join-Path $downloadRoot '.schedule_jobs.json'
        $low = Register-CloudCartridgeDownloadJob -JournalPath $schedulePath -ManagedRoot $downloadRoot -FilePath $gameA -CatalogId 'low' -Priority prefetch
        $high = Register-CloudCartridgeDownloadJob -JournalPath $schedulePath -ManagedRoot $downloadRoot -FilePath $gameB -CatalogId 'high' -Priority current
        Assert-True (-not (Enter-CloudCartridgeDownloadJob -JournalPath $schedulePath -JobId $low.job.job_id -MaxConcurrent 1)) 'Prefetch furou a prioridade.'
        Assert-True (Enter-CloudCartridgeDownloadJob -JournalPath $schedulePath -JobId $high.job.job_id -MaxConcurrent 1) 'Job atual nao obteve slot.'
        $null = Set-CloudCartridgeDownloadJobState -JournalPath $schedulePath -JobId $high.job.job_id -State completed
        Assert-True (Enter-CloudCartridgeDownloadJob -JournalPath $schedulePath -JobId $low.job.job_id -MaxConcurrent 1) 'Prefetch nao obteve slot liberado.'
    }

    Invoke-Test 'Concurrent requests create only one download job' {
        $parallelRoot = Join-Path $tempRoot 'parallel-cache'
        $parallelJournal = Join-Path $parallelRoot '.download_jobs.json'
        $parallelGame = Join-Path $parallelRoot 'Console\Parallel Game.chd'
        $gatePath = Join-Path $parallelRoot 'start.gate'
        New-Item -ItemType Directory -Path $parallelRoot -Force | Out-Null
        $worker = {
            param($ModulePath, $JournalPath, $ManagedRoot, $FilePath, $GatePath)
            Import-Module $ModulePath -Force
            while (-not (Test-Path -LiteralPath $GatePath)) { Start-Sleep -Milliseconds 20 }
            Register-CloudCartridgeDownloadJob -JournalPath $JournalPath -ManagedRoot $ManagedRoot -FilePath $FilePath -CatalogId 'parallel-game' -Priority current
        }
        $jobOne = Start-Job -ScriptBlock $worker -ArgumentList (Join-Path $repoRoot 'CloudCartridge.Core.psm1'), $parallelJournal, $parallelRoot, $parallelGame, $gatePath
        $jobTwo = Start-Job -ScriptBlock $worker -ArgumentList (Join-Path $repoRoot 'CloudCartridge.Core.psm1'), $parallelJournal, $parallelRoot, $parallelGame, $gatePath
        try {
            [System.IO.File]::WriteAllText($gatePath, 'go', [System.Text.Encoding]::ASCII)
            $null = Wait-Job -Job @($jobOne, $jobTwo) -Timeout 15
            Assert-True ($jobOne.State -eq 'Completed' -and $jobTwo.State -eq 'Completed') 'Workers paralelos nao terminaram.'
            $results = @((Receive-Job $jobOne), (Receive-Job $jobTwo))
            Assert-True (@($results | Where-Object { $_.deduplicated }).Count -eq 1) 'Deduplicacao paralela nao elegeu um unico job.'
            Assert-True (@($results | Where-Object { -not $_.deduplicated }).Count -eq 1) 'Quantidade de criadores do job incorreta.'
            Assert-True (@(Get-CloudCartridgeDownloadJobs -JournalPath $parallelJournal).Count -eq 1) 'Journal paralelo contem jobs duplicados.'
        } finally {
            Remove-Job -Job @($jobOne, $jobTwo) -Force -ErrorAction SilentlyContinue
        }
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
