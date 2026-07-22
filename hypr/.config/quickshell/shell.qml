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
                right: true
            }

            implicitHeight: Theme.barHeight
            color: Qt.rgba(0, 0, 0, 0.72)
            exclusiveZone: Theme.barHeight

            WlrLayershell.namespace: "quickshell-bar"
            WlrLayershell.layer: WlrLayer.Top

            Bar {
                anchors.fill: parent
                modelData: bar.modelData
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

    ShortcutsPopup {
        screen: Globals.focusedScreen()
    }

    LauncherPopup {
        screen: Globals.focusedScreen()
    }

    ClipboardPopup {
        screen: Globals.focusedScreen()
    }

    NotificationOSD {}

    IpcHandler {
        target: "shell"

        function toggleVolume(): void { Globals.toggleVolume() }
        function toggleMedia(): void { Globals.toggleMedia() }
        function togglePower(): void { Globals.togglePower() }
        function toggleShortcuts(): void { Globals.toggleShortcuts() }
        function toggleLauncher(): void { Globals.toggleLauncher() }
        function toggleClipboard(): void { Globals.toggleClipboard() }
        function closeAll(): void { Globals.closeAll() }
    }
}
