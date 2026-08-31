$projectRoot = 'D:\Projects\SEPEHR'
$evidenceRoot = Join-Path $projectRoot 'sepehr-chain\evidence\phase2'

New-Item -ItemType Directory -Force -Path $evidenceRoot | Out-Null

$phaseProcess = Start-Process `
    -FilePath 'wsl.exe' `
    -ArgumentList @(
        'bash',
        '/mnt/d/Projects/SEPEHR/sepehr-chain/scripts/phase2/run-transition-recovery.sh',
        'clean-3'
    ) `
    -RedirectStandardOutput (Join-Path $evidenceRoot 'clean-3-run.log') `
    -RedirectStandardError (Join-Path $evidenceRoot 'clean-3-run.err.log') `
    -WindowStyle Hidden `
    -PassThru

Set-Content -LiteralPath (Join-Path $evidenceRoot 'clean-3-run.pid') -Value $phaseProcess.Id
Write-Output $phaseProcess.Id
