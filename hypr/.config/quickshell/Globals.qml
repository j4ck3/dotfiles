pragma Singleton
import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Hyprland

Singleton {
    id: root

    property bool volumeOpen: false
    property bool displayOpen: false
    property bool mediaOpen: false
    property bool powerOpen: false
    property bool shortcutsOpen: false
    property bool launcherOpen: false
    property bool clipboardOpen: false
    property bool dashboardOpen: false

    readonly property string lockscreenPath: {
        // Kept for reference; lockSession() uses hyprlock (QS lock disabled).
        const u = Qt.resolvedUrl("./lockscreen.qml").toString()
        return u.replace(/^file:\/\//, "")
    }

    // Hover bridges (bar trigger ↔ popup card). Overlay must not cover the bar
    // or the trigger loses hover and the popup flash-loops open/close.
    property bool volumeHover: false
    // Display: bar + card tracked separately so card HoverHandler(false) on
    // open does not kill popup while pointer still on BRT.
    property bool displayBarHover: false
    property bool displayCardHover: false
    property bool displayPinned: false
    readonly property bool displayHover: displayBarHover || displayCardHover || displayPinned
    property bool powerHover: false
    property bool mediaHover: false

    // Bar → popup: distance from screen right to center card under trigger.
    property int mediaPopupRightMargin: 280
    property int volumePopupRightMargin: 210
    property int displayPopupRightMargin: 210
    property int powerPopupRightMargin: 16
    property int notifRightMargin: 14

    function clampPopupMargin(margin: int, cardW: int, screenW: int): int {
        return Math.max(16, Math.min(margin, Math.max(16, screenW - cardW - 16)))
    }

    SoundEffect {
        id: hoverSfx
        source: Qt.resolvedUrl("./assets/hover-select.wav")
        volume: 0.7
    }

    function playHoverSound(): void {
        hoverSfx.play()
    }

    Timer {
        id: volumeCloseTimer
        interval: 80
        onTriggered: {
            if (!root.volumeHover)
                root.volumeOpen = false
        }
    }

    Timer {
        id: displayCloseTimer
        interval: 220
        onTriggered: {
            if (!root.displayBarHover && !root.displayCardHover && !root.displayPinned)
                root.displayOpen = false
        }
    }

    Timer {
        id: powerCloseTimer
        interval: 80
        onTriggered: {
            if (!root.powerHover)
                root.powerOpen = false
        }
    }

    Timer {
        id: mediaCloseTimer
        interval: 80
        onTriggered: {
            if (!root.mediaHover)
                root.mediaOpen = false
        }
    }

    function closeOthers(except: string): void {
        if (except !== "volume")
            volumeOpen = false
        if (except !== "display")
            displayOpen = false
        if (except !== "media")
            mediaOpen = false
        if (except !== "power")
            powerOpen = false
        shortcutsOpen = false
        launcherOpen = false
        clipboardOpen = false
        if (except !== "dashboard")
            dashboardOpen = false
        if (except !== "volume") {
            volumeHover = false
            volumeCloseTimer.stop()
        }
        if (except !== "display") {
            displayBarHover = false
            displayCardHover = false
            displayPinned = false
            displayCloseTimer.stop()
        }
        if (except !== "power") {
            powerHover = false
            powerCloseTimer.stop()
        }
        if (except !== "media") {
            mediaHover = false
            mediaCloseTimer.stop()
        }
    }

    function setVolumeHover(inside: bool): void {
        volumeHover = inside
        if (inside) {
            volumeCloseTimer.stop()
            if (!volumeOpen) {
                playHoverSound()
                closeOthers("volume")
                volumeOpen = true
            }
        } else {
            volumeCloseTimer.restart()
        }
    }

    function syncDisplayOpen(): void {
        if (displayBarHover || displayCardHover || displayPinned) {
            displayCloseTimer.stop()
            if (!displayOpen) {
                playHoverSound()
                closeOthers("display")
                displayOpen = true
            }
        } else {
            displayCloseTimer.restart()
        }
    }

    function setDisplayBarHover(inside: bool): void {
        displayBarHover = inside
        syncDisplayOpen()
    }

    function setDisplayCardHover(inside: bool): void {
        displayCardHover = inside
        syncDisplayOpen()
    }

    function setDisplayPinned(pinned: bool): void {
        displayPinned = pinned
        if (pinned) {
            displayCloseTimer.stop()
            if (!displayOpen) {
                playHoverSound()
                closeOthers("display")
                displayOpen = true
            }
        } else {
            syncDisplayOpen()
        }
    }

    // Back-compat for older call sites
    function setDisplayHover(inside: bool): void {
        setDisplayBarHover(inside)
    }

    function setPowerHover(inside: bool): void {
        powerHover = inside
        if (inside) {
            powerCloseTimer.stop()
            if (!powerOpen) {
                playHoverSound()
                closeOthers("power")
                powerOpen = true
            }
        } else {
            powerCloseTimer.restart()
        }
    }

    function setMediaHover(inside: bool): void {
        mediaHover = inside
        if (inside) {
            mediaCloseTimer.stop()
            if (!mediaOpen) {
                playHoverSound()
                closeOthers("media")
                mediaOpen = true
            }
        } else {
            mediaCloseTimer.restart()
        }
    }

    // Resolved against this file's directory (config root)
    readonly property string scriptsDir: {
        const u = Qt.resolvedUrl("./scripts").toString()
        return u.replace(/^file:\/\//, "")
    }

    readonly property string superTapScript: {
        const home = Quickshell.env("HOME") || ""
        return home + "/.config/hypr/scripts/super-tap-dashboard"
    }

    function cancelSuperTap(): void {
        Quickshell.execDetached([superTapScript, "cancel"])
    }

    function closeAll(): void {
        volumeOpen = false
        displayOpen = false
        mediaOpen = false
        powerOpen = false
        shortcutsOpen = false
        launcherOpen = false
        clipboardOpen = false
        dashboardOpen = false
        volumeHover = false
        displayBarHover = false
        displayCardHover = false
        displayPinned = false
        powerHover = false
        mediaHover = false
        volumeCloseTimer.stop()
        displayCloseTimer.stop()
        powerCloseTimer.stop()
        mediaCloseTimer.stop()
    }

    function toggleVolume(): void {
        cancelSuperTap()
        const next = !volumeOpen
        closeAll()
        volumeOpen = next
    }

    function toggleDisplay(): void {
        cancelSuperTap()
        const next = !(displayOpen && displayPinned)
        closeAll()
        if (next) {
            displayPinned = true
            displayOpen = true
        }
    }

    function toggleMedia(): void {
        cancelSuperTap()
        const next = !mediaOpen
        closeAll()
        mediaOpen = next
    }

    function togglePower(): void {
        cancelSuperTap()
        const next = !powerOpen
        closeAll()
        powerOpen = next
    }

    function toggleShortcuts(): void {
        cancelSuperTap()
        const next = !shortcutsOpen
        closeAll()
        shortcutsOpen = next
    }

    function toggleLauncher(): void {
        cancelSuperTap()
        const next = !launcherOpen
        closeAll()
        launcherOpen = next
    }

    function toggleClipboard(): void {
        cancelSuperTap()
        const next = !clipboardOpen
        closeAll()
        clipboardOpen = next
    }

    property double lastDashboardToggleMs: 0

    function toggleDashboard(): void {
        const now = Date.now()
        // Voyager / dual devices can fire Super release twice → open then instant close.
        if (now - lastDashboardToggleMs < 400)
            return
        lastDashboardToggleMs = now
        const next = !dashboardOpen
        closeAll()
        dashboardOpen = next
    }

    function lockSession(): void {
        closeAll()
        // hyprlock — Quickshell WlSessionLock was crashing the Hyprland session.
        Quickshell.execDetached(["sh", "-c", "pidof hyprlock || hyprlock"])
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
