#Requires AutoHotkey v2.0
; Alt + left click -> OddSnap region capture.

#SingleInstance Force

global CaptureScript := A_ScriptDir "\Invoke-OddSnapCapture.ps1"

TriggerCapture(*) {
    static busy := false
    if busy
        return
    busy := true
    try {
        if GetKeyState("Alt", "P")
            Send("{Alt up}")

        if !FileExist(CaptureScript) {
            MsgBox("Missing: " CaptureScript, "oddsnap-win-mouse1", "Icon!")
            return
        }

        shell := ComObject("WScript.Shell")
        exitCode := shell.Run(
            'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' CaptureScript '"',
            0,
            true)

        if exitCode != 0
            MsgBox("OddSnap capture helper failed (exit " exitCode ").", "oddsnap-win-mouse1", "Icon!")
    } finally {
        busy := false
    }
}

#HotIf GetKeyState("Alt", "P")
*LButton:: TriggerCapture()
#HotIf
