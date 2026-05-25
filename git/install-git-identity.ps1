# Set global git author identity (all repos on this machine).
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File install-git-identity.ps1

$ErrorActionPreference = 'Stop'

$git = Get-Command git -ErrorAction Stop

& $git.Source config --global user.name 'j4ck3'
& $git.Source config --global user.email 'jacobhallgren@live.se'

Write-Host 'Global git identity:'
& $git.Source config --global --get user.name
& $git.Source config --global --get user.email
