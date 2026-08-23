import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import ".."

PanelWindow {
    id: root
    visible: Globals.powerOpen
    color: "transparent"
    exclusiveZone: 0
    anchors.top: true
    anchors.right: true
    margins.top: Theme.barHeight + 8
    margins.right: 16
    implicitWidth: 370
    implicitHeight: card.implicitHeight
    WlrLayershell.namespace: "quickshell-htpc-power"
    WlrLayershell.layer: WlrLayer.Overlay
    property bool shutdownArmed: false

    function run(command: var): void {
        Globals.closeAll()
        Quickshell.execDetached(command)
    }

    Rectangle {
        id: card
        width: parent.width
        implicitHeight: content.implicitHeight + 36
        radius: Theme.radius
        color: Theme.panel
        border.width: 1
        border.color: Theme.border

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: 18
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: "System"
                    color: Theme.ink
                    font.family: Theme.fontFamily
                    font.pixelSize: 22
                    font.bold: true
                }
                PopupButton { text: "Close"; onClicked: Globals.powerOpen = false }
            }

            PopupButton {
                Layout.fillWidth: true
                text: "󰌾  Lock"
                onClicked: root.run(["sh", "-c", "pidof hyprlock || hyprlock"])
            }
            PopupButton {
                Layout.fillWidth: true
                text: "󰤄  Suspend"
                onClicked: root.run(["systemctl", "suspend"])
            }
            PopupButton {
                Layout.fillWidth: true
                text: "󰜉  Reboot"
                onClicked: root.run(["systemctl", "reboot"])
            }
            PopupButton {
                Layout.fillWidth: true
                text: root.shutdownArmed ? "Confirm shutdown" : "󰐥  Shut down"
                active: root.shutdownArmed
                onClicked: {
                    if (root.shutdownArmed)
                        root.run(["systemctl", "poweroff"])
                    else {
                        root.shutdownArmed = true
                        disarm.restart()
                    }
                }
            }
        }
    }

    Timer {
        id: disarm
        interval: 3000
        onTriggered: root.shutdownArmed = false
    }

    onVisibleChanged: if (!visible) root.shutdownArmed = false
}
