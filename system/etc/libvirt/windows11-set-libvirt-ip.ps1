# Run in elevated PowerShell inside the windows11 VM (console/VNC mode).
# Resets the Red Hat VirtIO NIC to DHCP for LAN bridge mode.

$ErrorActionPreference = 'Stop'

$nic = Get-NetAdapter | Where-Object {
    $_.Status -eq 'Up' -and $_.InterfaceDescription -match 'VirtIO'
} | Select-Object -First 1

if (-not $nic) {
    Write-Host 'No Up VirtIO adapter found. Adapters:'
    Get-NetAdapter | Format-Table Name, InterfaceDescription, Status
    exit 1
}

Write-Host "Using: $($nic.Name) ($($nic.InterfaceDescription))"

Get-NetIPAddress -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
Get-NetRoute -InterfaceIndex $nic.ifIndex -ErrorAction SilentlyContinue |
    Where-Object { $_.DestinationPrefix -eq '0.0.0.0/0' } |
    Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

Set-NetIPInterface -InterfaceIndex $nic.ifIndex -Dhcp Enabled
Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -ResetServerAddresses
ipconfig /renew

Write-Host ''
Write-Host 'Test FROM WINDOWS:'
Write-Host '  ipconfig'
Write-Host '  ping 10.0.0.1'
Write-Host ''
Write-Host 'Test FROM ANOTHER PC ON THE LAN:'
Write-Host '  ping <windows-lan-ip>'
Write-Host '  mstsc /v:<windows-lan-ip>'
