pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland

Singleton {
    property bool launcherOpen: false
    property bool volumeOpen: false
    property bool displayOpen: false
    property bool powerOpen: false

    readonly property string scriptsDir: {
        const url = Qt.resolvedUrl("./scripts").toString()
        return url.replace(/^file:\/\//, "")
    }

    function closeAll(): void {
        launcherOpen = false
        volumeOpen = false
        displayOpen = false
        powerOpen = false
    }

    function toggle(name: string): void {
        const next = name === "launcher" ? !launcherOpen
            : name === "volume" ? !volumeOpen
            : name === "display" ? !displayOpen
            : name === "power" ? !powerOpen : false
        closeAll()
        if (name === "launcher") launcherOpen = next
        else if (name === "volume") volumeOpen = next
        else if (name === "display") displayOpen = next
        else if (name === "power") powerOpen = next
    }

    function focusedScreen(): var {
        const screens = Quickshell.screens
        if (!screens || screens.length === 0)
            return null
        const monitor = Hyprland.focusedMonitor
        if (!monitor)
            return screens[0]
        for (let i = 0; i < screens.length; i++) {
            if (screens[i].name === monitor.name)
                return screens[i]
        }
        return screens[0]
    }
}
