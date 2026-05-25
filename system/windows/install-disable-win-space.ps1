# Block Win+Space via AutoHotkey (Windows has no built-in off switch).
# Run: powershell -ExecutionPolicy Bypass -File install-disable-win-space.ps1

$ErrorActionPreference = 'Stop'

$ahkScript = Join-Path $PSScriptRoot 'disable-win-space.ahk'
$runKeyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$runName = 'DisableWinSpace'

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

$togglePath = 'HKCU:\Keyboard Layout\Toggle'
if (Test-Path $togglePath) {
    Set-ItemProperty -Path $togglePath -Name 'Language Hotkey' -Value 3 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $togglePath -Name 'Layout Hotkey' -Value 3 -Type DWord -ErrorAction SilentlyContinue
}

$runCommand = ('"{0}" "{1}"' -f $ahkExe, $ahkScript)
Set-ItemProperty -Path $runKeyPath -Name $runName -Value $runCommand
Start-Process -FilePath $ahkExe -ArgumentList @($ahkScript)

Write-Host 'Win+Space disabled (AutoHotkey hook + login Run entry).'
Write-Host ('Run key: ' + $runName)
