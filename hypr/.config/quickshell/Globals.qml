pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland

Singleton {
    id: root

    property bool volumeOpen: false
    property bool mediaOpen: false
    property bool powerOpen: false
    property bool shortcutsOpen: false
    property bool launcherOpen: false
    property bool clipboardOpen: false

    // Resolved against this file's directory (config root)
    readonly property string scriptsDir: {
        const u = Qt.resolvedUrl("./scripts").toString()
        return u.replace(/^file:\/\//, "")
    }

    function closeAll(): void {
        volumeOpen = false
        mediaOpen = false
        powerOpen = false
        shortcutsOpen = false
        launcherOpen = false
        clipboardOpen = false
    }

    function toggleVolume(): void {
        const next = !volumeOpen
        closeAll()
        volumeOpen = next
    }

    function toggleMedia(): void {
        const next = !mediaOpen
        closeAll()
        mediaOpen = next
    }

    function togglePower(): void {
        const next = !powerOpen
        closeAll()
        powerOpen = next
    }

    function toggleShortcuts(): void {
        const next = !shortcutsOpen
        closeAll()
        shortcutsOpen = next
    }

    function toggleLauncher(): void {
        const next = !launcherOpen
        closeAll()
        launcherOpen = next
    }

    function toggleClipboard(): void {
        const next = !clipboardOpen
        closeAll()
        clipboardOpen = next
    }

    function focusedScreen(): var {
        const mon = Hyprland.focusedMonitor
        const screens = Quickshell.screens
        if (!screens || screens.length === 0)
            return null
        if (!mon)
            return screens[0]
        for (let i = 0; i < screens.length; i++) {
            if (screens[i].name === mon.name)
                return screens[i]
        }
        return screens[0]
    }
}
