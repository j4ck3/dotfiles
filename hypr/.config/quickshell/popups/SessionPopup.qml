import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import ".."

PanelWindow {
    id: root
    visible: Globals.sessionOpen
    color: "transparent"
    exclusiveZone: 0

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    WlrLayershell.namespace: "qs-session"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    property int selectedIndex: 0

    function close(): void {
        Globals.sessionOpen = false
    }

    function moveSelection(delta: int): void {
        selectedIndex = Math.max(0, Math.min(4, selectedIndex + delta))
    }

    function activateSelection(): void {
        switch (selectedIndex) {
        case 0:
            root.close()
            Globals.lockSession()
            break
        case 1:
            root.runSessionAction("suspend")
            break
        case 2:
            root.runSessionAction("reboot")
            break
        case 3:
            if (root.shutDownArmed)
                root.runSessionAction("poweroff")
            else
                root.shutDownArmed = true
            break
        case 4:
            root.runSessionAction("logout")
            break
        }
    }

    function runSessionAction(action: string): void {
        Quickshell.execDetached([Globals.sessionActionScript, action])
        root.close()
    }

    HyprlandFocusGrab {
        active: root.visible
        windows: [root]
        onCleared: root.close()
    }

    Item {
        id: sessionKeys
        anchors.fill: parent
        focus: root.visible

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                root.close()
                event.accepted = true
            } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
                root.moveSelection(1)
                event.accepted = true
            } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
                root.moveSelection(-1)
                event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Right) {
                root.activateSelection()
                event.accepted = true
            }
        }
    }

    LauncherCard {
        anchors.fill: parent
        visible: root.visible
        cardWidth: 360
        cardHeight: 296
        onScrimClicked: root.close()

        M3IconButton {
            Layout.fillWidth: true
            wide: true
            icon: "󰌾"
            label: "Lock Screen"
            active: root.selectedIndex === 0
            onClicked: {
                root.close()
                Globals.lockSession()
            }
        }

        M3IconButton {
            Layout.fillWidth: true
            wide: true
            icon: "󰤄"
            label: "Suspend"
            active: root.selectedIndex === 1
            onClicked: root.runSessionAction("suspend")
        }

        M3IconButton {
            Layout.fillWidth: true
            wide: true
            icon: "󰜉"
            label: "Reboot"
            active: root.selectedIndex === 2
            onClicked: root.runSessionAction("reboot")
        }

        M3IconButton {
            Layout.fillWidth: true
            wide: true
            icon: "󰐥"
            label: root.shutDownArmed ? "Confirm Shut Down?" : "Shut Down"
            active: root.selectedIndex === 3
            danger: true
            onClicked: {
                if (root.shutDownArmed)
                    root.runSessionAction("poweroff")
                else
                    root.shutDownArmed = true
            }
        }

        M3IconButton {
            Layout.fillWidth: true
            wide: true
            icon: "󰍃"
            label: "Log Out"
            active: root.selectedIndex === 4
            onClicked: root.runSessionAction("logout")
        }

        Text {
            Layout.fillWidth: true
            text: "↑↓ select · Enter confirm · Esc close"
            color: Theme.inkMuted
            font.family: Theme.fontFamily
            font.pixelSize: 11
        }
    }

    property bool shutDownArmed: false

    onVisibleChanged: {
        if (visible) {
            selectedIndex = 0
            shutDownArmed = false
            sessionKeys.forceActiveFocus()
        }
    }
}
