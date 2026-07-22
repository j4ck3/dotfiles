import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import ".."

PanelWindow {
    id: root
    visible: Globals.powerOpen
    color: "transparent"
    exclusiveZone: 0

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    WlrLayershell.namespace: "qs-power"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    function run(cmd: var): void {
        Quickshell.execDetached(cmd)
        Globals.powerOpen = false
    }

    HyprlandFocusGrab {
        active: root.visible
        windows: [root]
        onCleared: Globals.powerOpen = false
    }

    MouseArea {
        anchors.fill: parent
        onClicked: Globals.powerOpen = false
    }

    PopupCard {
        anchors.fill: parent
        title: "Power"
        cardWidth: 300
        onClosed: Globals.powerOpen = false

        M3Section {
            title: "VIRTUAL MACHINES"

            M3IconButton {
                Layout.fillWidth: true
                wide: true
                icon: "󰖳"
                label: "Windows 11"
                onClicked: root.run(["xdg-terminal-exec", "--", "windows11-start", "--yes"])
            }

            M3IconButton {
                Layout.fillWidth: true
                wide: true
                icon: "󰖳"
                label: "Windows 11 Stealth"
                onClicked: root.run(["xdg-terminal-exec", "--", "windows11-stealth-start", "--yes"])
            }
        }

        M3Section {
            title: "SESSION"

            M3IconButton {
                Layout.fillWidth: true
                wide: true
                icon: "󰌾"
                label: "Lock Screen"
                onClicked: root.run(["loginctl", "lock-session"])
            }

            M3IconButton {
                Layout.fillWidth: true
                wide: true
                icon: "󰤄"
                label: "Suspend"
                onClicked: root.run(["systemctl", "suspend"])
            }

            M3IconButton {
                Layout.fillWidth: true
                wide: true
                icon: "󰜉"
                label: "Reboot"
                onClicked: root.run(["systemctl", "reboot"])
            }

            M3IconButton {
                Layout.fillWidth: true
                wide: true
                icon: "󰐥"
                label: "Shut Down"
                danger: true
                onClicked: root.run(["systemctl", "poweroff"])
            }

            M3IconButton {
                Layout.fillWidth: true
                wide: true
                icon: "󰍃"
                label: "Log Out"
                onClicked: root.run(["hyprctl", "dispatch", "exit"])
            }
        }
    }
}
