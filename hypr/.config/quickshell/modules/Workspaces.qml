import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland

import ".."

Item {
    id: root

    property bool vertical: false

    readonly property var icons: ({
        "1": "j",
        "2": "k",
        "3": "l",
        "4": "ö",
        "10": "i",
        "11": "u",
        "12": "y",
        "13": "h",
        "14": "b",
        "15": "m"
    })
    readonly property var persistent: [1, 2, 3, 4, 5, 10, 11, 12, 13, 14, 15]
    readonly property int cellW: 26
    readonly property int activeId: Hyprland.focusedWorkspace?.id ?? 1

    implicitWidth: root.vertical ? root.cellW : layout.implicitWidth
    implicitHeight: root.vertical ? layout.implicitHeight : Theme.barInnerHeight
    Layout.preferredWidth: root.vertical ? root.cellW : implicitWidth
    Layout.preferredHeight: root.vertical ? implicitHeight : Theme.barInnerHeight
    Layout.fillHeight: false

    function labelFor(id: int): string {
        const key = String(id)
        return root.icons[key] !== undefined ? root.icons[key].toUpperCase() : (id <= 9 ? String(id) : "·")
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

    // Selected workspace only — Liquid Glass (circle)
    Item {
        id: activeLift
        readonly property int idx: root.indexOfId(root.activeId)
        width: root.cellW
        height: root.cellW
        x: root.vertical ? layout.x : (layout.x + idx * root.cellW)
        y: root.vertical ? (layout.y + idx * root.cellW) : layout.y
        z: 1

        Behavior on x {
            enabled: !root.vertical
            NumberAnimation {
                duration: Theme.animEmphasized
                easing.type: Easing.OutBack
                easing.overshoot: 0.6
            }
        }
        Behavior on y {
            enabled: root.vertical
            NumberAnimation {
                duration: Theme.animEmphasized
                easing.type: Easing.OutBack
                easing.overshoot: 0.6
            }
        }

        Rectangle {
            id: activePill
            anchors.fill: parent
            anchors.margins: 1
            radius: width / 2
            color: Theme.glassFillHover
            border.width: 1
            border.color: Theme.glassRimHover

            // Specular — circle-clipped via matching radius + contained size
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 1
                width: parent.width - 2
                height: parent.height * 0.5
                radius: width / 2
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.glassSpecular }
                    GradientStop { position: 0.55; color: Theme.glassSpecularSoft }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
        }
    }

    Grid {
        id: layout
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        columns: root.vertical ? 1 : root.persistent.length
        rows: root.vertical ? root.persistent.length : 1
        spacing: 0
        flow: root.vertical ? Grid.TopToBottom : Grid.LeftToRight
        z: 2

        Repeater {
            model: root.persistent

            Item {
                id: wsItem
                required property int modelData
                width: root.cellW
                height: root.cellW

                readonly property bool active: root.activeId === modelData
                readonly property bool empty: !root.occupied(modelData)
                readonly property bool hovered: wsMouse.containsMouse

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: width / 2
                    color: wsItem.hovered && !wsItem.active ? Theme.hover : "transparent"
                    Behavior on color {
                        ColorAnimation { duration: Theme.animFast }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: 0.5
                    text: root.labelFor(wsItem.modelData)
                    color: wsItem.active ? Theme.ink
                         : wsItem.hovered ? Theme.ink
                         : wsItem.empty ? Theme.hairline
                         : Theme.ink
                    opacity: wsItem.active ? 1 : (wsItem.hovered ? 1 : (wsItem.empty ? 0.55 : 0.9))
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.weight: wsItem.active ? Font.DemiBold : Font.Medium
                    z: 1

                    Behavior on color {
                        ColorAnimation { duration: Theme.animFast }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: Theme.animFast }
                    }
                }

                MouseArea {
                    id: wsMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Hyprland.dispatch(
                        "hl.dsp.focus({ workspace = " + wsItem.modelData + ", on_current_monitor = true })"
                    )
                }
            }
        }
    }
}
