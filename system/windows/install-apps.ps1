# Install packages listed in ~/dotfiles/winget-packages.txt via winget.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File "$HOME\dotfiles\system\windows\install-apps.ps1"

param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$packageFile = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path 'winget-packages.txt'

if (-not (Test-Path $packageFile)) {
    throw "Missing package list: $packageFile"
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw 'winget is not available. Install App Installer from the Microsoft Store.'
}

$packages = Get-Content $packageFile |
    Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*#' } |
    ForEach-Object { $_.Trim() }

if ($packages.Count -eq 0) {
    throw "No packages found in $packageFile"
}

$wingetArgs = @(
    'install',
    '--exact',
    '--accept-package-agreements',
    '--accept-source-agreements',
    '--disable-interactivity'
)

$failed = @()

Write-Host "Package list: $packageFile"
Write-Host "Packages: $($packages.Count)"
Write-Host ''

foreach ($id in $packages) {
    Write-Host "==> $id"

    if ($DryRun) {
        continue
    }

    & winget @wingetArgs --id $id
    if ($LASTEXITCODE -ne 0) {
        $failed += $id
        Write-Warning "winget install failed for $id (exit $LASTEXITCODE)"
    }

    Write-Host ''
}

if ($DryRun) {
    Write-Host 'Dry run only — no packages were installed.'
    exit 0
}

if ($failed.Count -gt 0) {
    Write-Warning "Finished with $($failed.Count) failure(s): $($failed -join ', ')"
    exit 1
}

Write-Host 'All packages installed (or already present).'
