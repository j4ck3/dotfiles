//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

import "."
import "popups"

ShellRoot {
    id: root

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: bar
            required property var modelData
            screen: modelData

            // Hide the bar only on the monitor displaying a fullscreen workspace.
            readonly property var hyprMonitor: Hyprland.monitors.values.find(m => m.name === bar.screen.name) ?? null
            readonly property bool fullscreenActive: hyprMonitor?.activeWorkspace?.hasFullscreen ?? false
            visible: !fullscreenActive

            anchors {
                top: true
                left: true
                right: !Theme.barVertical
                bottom: Theme.barVertical
            }

            implicitHeight: Theme.barVertical ? 0 : Theme.barHeight
            implicitWidth: Theme.barVertical ? Theme.barWidth : 0
            // Window stays transparent; the bar background lives on barSlide so
            // the auto-hidden bar can slide out without resizing the surface.
            color: "transparent"
            // Auto-hide overlays windows instead of reserving space. Setting
            // exclusiveZone would force exclusionMode back to Normal.
            exclusionMode: Theme.barAutoHide ? ExclusionMode.Ignore : ExclusionMode.Normal
            exclusiveZone: Theme.barAutoHide ? 0 : Theme.barThickness

            WlrLayershell.namespace: "quickshell-bar"
            WlrLayershell.layer: Theme.barAutoHide ? WlrLayer.Overlay : WlrLayer.Top

            // Revealed while the pointer is on the bar (or its hot edge), while a
            // bar popup is open, and for barHideDelay ms after both end.
            property bool revealed: !Theme.barAutoHide
            readonly property bool holdOpen: edgeHover.hovered || barHover.hovered || Globals.barPopupOpen

            onHoldOpenChanged: {
                if (!Theme.barAutoHide)
                    return
                if (holdOpen) {
                    hideTimer.stop()
                    revealed = true
                } else {
                    hideTimer.restart()
                }
            }

            Timer {
                id: hideTimer
                interval: Theme.barHideDelay
                onTriggered: {
                    if (!bar.holdOpen)
                        bar.revealed = false
                }
            }

            // Hidden: only the thin hot edge takes input, so the rest of the
            // strip passes clicks through to the windows underneath.
            mask: Region {
                x: 0
                y: 0
                width: bar.revealed || !Theme.barVertical ? bar.width : Theme.barHotEdgeSize
                height: bar.revealed || Theme.barVertical ? bar.height : Theme.barHotEdgeSize
            }

            // Hot edge: fixed on-screen trigger along the whole docked screen
            // edge while the bar is slid away.
            Item {
                x: 0
                y: 0
                width: Theme.barVertical ? Theme.barHotEdgeSize : parent.width
                height: Theme.barVertical ? parent.height : Theme.barHotEdgeSize
                HoverHandler { id: edgeHover }
            }

            Rectangle {
                id: barSlide
                width: parent.width
                height: parent.height
                x: Theme.barVertical && !bar.revealed ? -width : 0
                y: !Theme.barVertical && !bar.revealed ? -height : 0
                // Vertical: solid so strip reads on dark wallpaper (top bar stays translucent).
                color: Theme.barVertical ? "#000000" : Qt.rgba(0, 0, 0, 0.72)

                // Ancestor of every bar module, so it stays hovered over buttons.
                HoverHandler { id: barHover }

                // Snappy slide-in, unhurried slide-out.
                Behavior on x {
                    NumberAnimation {
                        duration: bar.revealed ? Theme.barRevealDuration : Theme.animNormal
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on y {
                    NumberAnimation {
                        duration: bar.revealed ? Theme.barRevealDuration : Theme.animNormal
                        easing.type: Easing.OutCubic
                    }
                }

                Loader {
                    anchors.fill: parent
                    sourceComponent: Theme.barVertical ? verticalBarComp : horizontalBarComp
                }
            }

            Component {
                id: horizontalBarComp
                Bar {
                    anchors.fill: parent
                    modelData: bar.modelData
                }
            }

            Component {
                id: verticalBarComp
                VerticalBar {
                    anchors.fill: parent
                    modelData: bar.modelData
                }
            }
        }
    }

    VolumePopup {
        screen: Globals.focusedScreen()
    }

    MediaPopup {
        screen: Globals.focusedScreen()
    }

    PowerMenu {
        screen: Globals.focusedScreen()
    }

    UtilitiesPopup {
        screen: Globals.focusedScreen()
    }

    DisplayPopup {
        screen: Globals.focusedScreen()
    }

    ShortcutsPopup {
        screen: Globals.focusedScreen()
    }

    LauncherPopup {
        screen: Globals.focusedScreen()
    }

    SessionPopup {
        screen: Globals.focusedScreen()
    }

    ClipboardPopup {
        screen: Globals.focusedScreen()
    }

    DashboardPopup {
        screen: Globals.focusedScreen()
    }

    TowerPopup {
        screen: Globals.focusedScreen()
    }

    MousePopup {
        screen: Globals.focusedScreen()
    }

    DictationOverlay {}

    NotificationOSD {}

    SessionAnimation { id: sessionAnimation }

    IpcHandler {
        target: "shell"

        function toggleVolume(): void { Globals.toggleVolume() }
        function toggleMedia(): void { Globals.toggleMedia() }
        function togglePower(): void { Globals.togglePower() }
        function toggleUtilities(): void { Globals.toggleUtilities() }
        function toggleShortcuts(): void { Globals.toggleShortcuts() }
        function toggleLauncher(): void { Globals.toggleLauncher() }
        function toggleSession(): void { Globals.toggleSession() }
        function toggleClipboard(): void { Globals.toggleClipboard() }
        function toggleDashboard(): void { Globals.toggleDashboard() }
        function toggleTower(): void { Globals.toggleTower() }
        function cancelDictation(): void { Globals.cancelDictation() }
        function closeAll(): void { Globals.closeAll() }
        function lock(): void { Globals.lockSession() }
        function playSessionAnimation(): string { return sessionAnimation.play() }
        function sessionAnimationStatus(): string { return sessionAnimation.phase }
    }
}
