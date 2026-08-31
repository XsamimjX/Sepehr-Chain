$projectRoot = 'D:\Projects\SEPEHR'
$evidenceRoot = Join-Path $projectRoot 'sepehr-chain\evidence\phase2'

New-Item -ItemType Directory -Force -Path $evidenceRoot | Out-Null

$phaseProcess = Start-Process `
    -FilePath 'wsl.exe' `
    -ArgumentList @(
        'env',
        'SEPEHR_PHASE2_PARTITION_TEST=true',
        'bash',
        '/mnt/d/Projects/SEPEHR/sepehr-chain/scripts/phase2/run-transition-recovery.sh',
        'partition'
    ) `
    -RedirectStandardOutput (Join-Path $evidenceRoot 'partition-run.log') `
    -RedirectStandardError (Join-Path $evidenceRoot 'partition-run.err.log') `
    -WindowStyle Hidden `
    -PassThru

Set-Content -LiteralPath (Join-Path $evidenceRoot 'partition-run.pid') -Value $phaseProcess.Id
Write-Output $phaseProcess.Id
