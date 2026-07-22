import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland

import ".."

Item {
    id: root

    readonly property var icons: ({
        "1": "j",
        "2": "k",
        "3": "l",
        "4": "ö",
        "10": "i",
        "11": "u",
        "12": "y",
        "15": "m"
    })
    readonly property var persistent: [1, 2, 3, 4, 5, 11, 12, 13, 15]
    readonly property int cellW: 24
    readonly property int pad: 3
    readonly property int activeId: Hyprland.focusedWorkspace?.id ?? 1

    implicitWidth: layout.implicitWidth + pad * 2
    implicitHeight: Theme.barInnerHeight
    Layout.preferredHeight: Theme.barInnerHeight
    Layout.fillHeight: false

    function labelFor(id: int): string {
        const key = String(id)
        return root.icons[key] !== undefined ? root.icons[key] : (id <= 9 ? String(id) : "·")
    }

    function occupied(id: int): bool {
        const list = Hyprland.workspaces.values
        for (let i = 0; i < list.length; i++) {
            if (list[i].id === id)
                return true
        }
        return false
    }

    function indexOfId(id: int): int {
        for (let i = 0; i < persistent.length; i++) {
            if (persistent[i] === id)
                return i
        }
        return 0
    }

    // Outer pill
    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: Theme.surfaceContainer
    }

    // Sliding active indicator — vertically centered in track
    Rectangle {
        id: activePill
        readonly property int idx: root.indexOfId(root.activeId)
        width: root.cellW - 2
        height: track.height - root.pad * 2
        radius: height / 2
        color: Theme.primary

        anchors.verticalCenter: track.verticalCenter
        x: layout.x + idx * root.cellW + (root.cellW - width) / 2

        Behavior on x {
            NumberAnimation {
                duration: Theme.animEmphasized
                easing.type: Easing.OutBack
                easing.overshoot: 0.6
            }
        }
    }

    Row {
        id: layout
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 0
        height: parent.height - root.pad * 2

        Repeater {
            model: root.persistent

            Item {
                id: wsItem
                required property int modelData
                width: root.cellW
                height: layout.height

                readonly property bool active: root.activeId === modelData
                readonly property bool empty: !root.occupied(modelData)

                Text {
                    anchors.centerIn: parent
                    // Optical vertical nudge — fonts sit slightly high in the pill
                    anchors.verticalCenterOffset: 0.5
                    text: root.labelFor(wsItem.modelData)
                    color: wsItem.active ? Theme.primaryInk
                         : wsItem.empty ? Theme.hairline
                         : Theme.ink
                    opacity: wsItem.active ? 1 : (wsItem.empty ? 0.55 : 0.9)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.weight: wsItem.active ? Font.DemiBold : Font.Medium
                    z: 1

                    Behavior on color {
                        ColorAnimation { duration: Theme.animFast }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Hyprland.dispatch("workspace " + wsItem.modelData)
                }
            }
        }
    }
}
