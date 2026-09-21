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

            anchors {
                top: true
                left: true
                right: !Theme.barVertical
                bottom: Theme.barVertical
            }

            implicitHeight: Theme.barVertical ? 0 : Theme.barHeight
            implicitWidth: Theme.barVertical ? Theme.barWidth : 0
            // Vertical: solid so strip reads on dark wallpaper (top bar stays translucent).
            color: Theme.barVertical ? "#000000" : Qt.rgba(0, 0, 0, 0.72)
            exclusiveZone: Theme.barThickness

            WlrLayershell.namespace: "quickshell-bar"
            WlrLayershell.layer: WlrLayer.Top

            Loader {
                anchors.fill: parent
                sourceComponent: Theme.barVertical ? verticalBarComp : horizontalBarComp
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

    ClipboardPopup {
        screen: Globals.focusedScreen()
    }

    DashboardPopup {
        screen: Globals.focusedScreen()
    }

    TowerPopup {
        screen: Globals.focusedScreen()
    }

    DictationOverlay {}

    NotificationOSD {}

    IpcHandler {
        target: "shell"

        function toggleVolume(): void { Globals.toggleVolume() }
        function toggleMedia(): void { Globals.toggleMedia() }
        function togglePower(): void { Globals.togglePower() }
        function toggleUtilities(): void { Globals.toggleUtilities() }
        function toggleShortcuts(): void { Globals.toggleShortcuts() }
        function toggleLauncher(): void { Globals.toggleLauncher() }
        function toggleClipboard(): void { Globals.toggleClipboard() }
        function toggleDashboard(): void { Globals.toggleDashboard() }
        function toggleTower(): void { Globals.toggleTower() }
        function cancelDictation(): void { Globals.cancelDictation() }
        function closeAll(): void { Globals.closeAll() }
        function lock(): void { Globals.lockSession() }
    }
}
