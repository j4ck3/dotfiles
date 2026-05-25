# OddSnap: no login startup, clipboard capture, Alt+left-click via AutoHotkey.
# Run: powershell -ExecutionPolicy Bypass -File configure-oddsnap.ps1

$ErrorActionPreference = 'Stop'

$settingsPath = Join-Path $env:APPDATA 'OddSnap\settings.json'
$ahkScript = Join-Path $PSScriptRoot 'oddsnap-win-mouse1.ahk'
$runKeyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$runName = 'OddSnapWinMouse1'

function Get-AutoHotkeyExe {
    $candidates = @(
        "${env:ProgramFiles}\AutoHotkey\v2\AutoHotkey64.exe",
        "${env:ProgramFiles}\AutoHotkey\v2\AutoHotkey32.exe",
        "${env:LocalAppData}\Programs\AutoHotkey\v2\AutoHotkey64.exe"
    )
    foreach ($path in $candidates) {
        if (Test-Path $path) { return $path }
    }
    $cmd = Get-Command AutoHotkey64.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

if (-not (Test-Path $ahkScript)) {
    throw "Missing script: $ahkScript"
}

if (-not (Get-AutoHotkeyExe)) {
    Write-Host 'Installing AutoHotkey v2...'
    winget install --id AutoHotkey.AutoHotkey --accept-package-agreements --accept-source-agreements
    $ahkExe = Get-AutoHotkeyExe
    if (-not $ahkExe) { throw 'AutoHotkey install failed or executable not found.' }
} else {
    $ahkExe = Get-AutoHotkeyExe
}

Get-Process -Name 'OddSnap' -ErrorAction SilentlyContinue | Stop-Process -Force

if (Test-Path $settingsPath) {
    $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
    $settings.StartWithWindows = $false
    $settings.HotkeyModifiers = 6          # Ctrl+Shift (internal trigger for AHK)
    $settings.HotkeyKey = 123              # F12
    $settings.AfterCapture = 0             # CopyToClipboard
    $settings.SaveToFile = $false
    $settings | ConvertTo-Json -Depth 20 | Set-Content $settingsPath -Encoding utf8
    Write-Host "Updated $settingsPath"
} else {
    Write-Warning "Settings not found at $settingsPath - open OddSnap once, then re-run."
}

if (Get-ItemProperty -Path $runKeyPath -Name 'OddSnap' -ErrorAction SilentlyContinue) {
    Remove-ItemProperty -Path $runKeyPath -Name 'OddSnap'
    Write-Host 'Removed OddSnap from Windows startup.'
}

$runCommand = ('"{0}" "{1}"' -f $ahkExe, $ahkScript)
Set-ItemProperty -Path $runKeyPath -Name $runName -Value $runCommand
Write-Host ('Registered ' + $runName + ' startup entry.')

Start-Process -FilePath $ahkExe -ArgumentList @($ahkScript)
Write-Host 'Alt+left-click -> region capture -> clipboard.'
Write-Host 'OddSnap starts on first capture only; tray -> Quit to stop it.'
Write-Host 'AutoHotkey helper stays in background for the hotkey.'
