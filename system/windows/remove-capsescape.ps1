#Requires -RunAsAdministrator
# Removes the Caps Lock -> Escape Scancode Map.

$ErrorActionPreference = 'Stop'

$regPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout'
$name = 'Scancode Map'

if (-not (Get-ItemProperty -Path $regPath -Name $name -ErrorAction SilentlyContinue)) {
    Write-Host 'No Scancode Map is configured.'
    exit 0
}

Remove-ItemProperty -Path $regPath -Name $name
Write-Host 'Caps Lock -> Escape removed.'
Write-Host 'Sign out or reboot for the change to take effect.'
