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
    exclusionMode: ExclusionMode.Ignore

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    margins {
        top: Theme.barHeight
    }

    WlrLayershell.namespace: "qs-power"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    function run(cmd: var): void {
        Quickshell.execDetached(cmd)
        Globals.powerOpen = false
    }

    property bool shutDownArmed: false

    onVisibleChanged: {
        if (visible) {
            shutDownArmed = false
            card.playIn()
        } else {
            shutDownArmed = false
            card.resetOut()
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: Globals.powerOpen = false
    }

    PopupCard {
        id: card
        anchors.fill: parent
        title: "Power"
        cardWidth: 300
        topMargin: Theme.widgetTopGap
        rightMargin: Globals.powerPopupRightMargin
        animateIn: true
        onClosed: Globals.powerOpen = false
        onCardHover: inside => Globals.setPowerHover(inside)

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
                onClicked: {
                    Globals.powerOpen = false
                    Globals.lockSession()
                }
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
                label: root.shutDownArmed ? "Confirm Shut Down?" : "Shut Down"
                danger: true
                onClicked: {
                    if (root.shutDownArmed)
                        root.run(["systemctl", "poweroff"])
                    else
                        root.shutDownArmed = true
                }
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
