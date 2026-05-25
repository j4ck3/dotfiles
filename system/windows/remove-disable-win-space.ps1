# Undo install-disable-win-space.ps1

$ErrorActionPreference = 'Stop'

$runKeyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$runName = 'DisableWinSpace'

if (Get-ItemProperty -Path $runKeyPath -Name $runName -ErrorAction SilentlyContinue) {
    Remove-ItemProperty -Path $runKeyPath -Name $runName
    Write-Host ('Removed Run entry: ' + $runName)
}

Get-CimInstance Win32_Process -Filter "Name LIKE 'AutoHotkey%'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*disable-win-space.ahk*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Write-Host 'Win+Space block removed. Reboot or sign out if the key still does nothing until AHK exits.'
