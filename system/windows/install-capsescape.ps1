#Requires -RunAsAdministrator
# Maps Caps Lock to Escape via the Windows Scancode Map registry key.
# Sign out or reboot after running for the change to take effect.

$ErrorActionPreference = 'Stop'

$regPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout'
$name = 'Scancode Map'

# Header + 1 mapping + terminator. Pair order is (new scancode, original scancode).
# Caps Lock 0x003A -> Escape 0x0001
$map = [byte[]](
    0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00,
    0x02, 0x00, 0x00, 0x00,
    0x01, 0x00, 0x3A, 0x00,
    0x00, 0x00, 0x00, 0x00
)

Set-ItemProperty -Path $regPath -Name $name -Value $map -Type Binary
Write-Host 'Caps Lock -> Escape installed.'
Write-Host 'Sign out or reboot for the remap to take effect.'
