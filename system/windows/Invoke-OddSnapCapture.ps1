# Start OddSnap (if needed) and trigger region capture.
param(
    [string]$ProcessName = 'OddSnap.exe',
    [string]$OddSnapExe = "$env:LOCALAPPDATA\JasperDevs.OddSnap\current\OddSnap.exe"
)

$ErrorActionPreference = 'Stop'
$procBase = $ProcessName -replace '\.exe$', ''

if (-not (Test-Path $OddSnapExe)) {
    Write-Error "OddSnap not found: $OddSnapExe"
    exit 1
}

if (-not (Get-Process -Name $procBase -ErrorAction SilentlyContinue)) {
    Start-Process -FilePath $OddSnapExe | Out-Null
    $deadline = (Get-Date).AddSeconds(20)
    while ((Get-Date) -lt $deadline) {
        if (Get-Process -Name $procBase -ErrorAction SilentlyContinue) { break }
        Start-Sleep -Milliseconds 250
    }
    Start-Sleep -Seconds 2
}

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class KbdCapture {
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    public static void PressCtrlShiftF12() {
        keybd_event(0x11, 0, 0, UIntPtr.Zero);
        keybd_event(0x10, 0, 0, UIntPtr.Zero);
        keybd_event(0x7B, 0, 0, UIntPtr.Zero);
        keybd_event(0x7B, 0, 2, UIntPtr.Zero);
        keybd_event(0x10, 0, 2, UIntPtr.Zero);
        keybd_event(0x11, 0, 2, UIntPtr.Zero);
    }
}
'@

[KbdCapture]::PressCtrlShiftF12()
exit 0
