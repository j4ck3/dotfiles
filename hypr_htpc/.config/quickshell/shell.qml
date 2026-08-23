//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

import "."
import "popups"

ShellRoot {
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: bar
            required property var modelData
            screen: modelData
            anchors.top: true
            anchors.left: true
            anchors.right: true
            implicitHeight: Theme.barHeight
            exclusiveZone: Theme.barHeight
            color: Theme.background
            WlrLayershell.namespace: "quickshell-htpc-bar"
            WlrLayershell.layer: WlrLayer.Top

            Bar {
                anchors.fill: parent
                modelData: bar.modelData
            }
        }
    }

    LauncherPopup { screen: Globals.focusedScreen() }
    VolumePopup { screen: Globals.focusedScreen() }
    DisplayPopup { screen: Globals.focusedScreen() }
    PowerPopup { screen: Globals.focusedScreen() }

    IpcHandler {
        target: "shell"
        function toggleLauncher(): void { Globals.toggle("launcher") }
        function toggleVolume(): void { Globals.toggle("volume") }
        function toggleDisplay(): void { Globals.toggle("display") }
        function togglePower(): void { Globals.toggle("power") }
        function closeAll(): void { Globals.closeAll() }
    }
}
