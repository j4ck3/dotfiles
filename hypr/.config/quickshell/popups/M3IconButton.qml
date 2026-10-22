import QtQuick
import QtQuick.Layouts

import ".."

Rectangle {
    id: root

    property string icon: ""
    property string label: ""
    property bool active: false
    property bool danger: false
    property bool wide: false

    readonly property bool hovered: mouse.containsMouse

    signal clicked

    implicitWidth: wide ? Math.max(44, row.implicitWidth + 24) : 36
    implicitHeight: wide ? 36 : 36
    Layout.fillWidth: wide
    radius: wide ? 12 : 18
    color: {
        if (root.active)
            return root.hovered ? "#339aff" : Theme.popupAccent
        if (root.hovered)
            return root.danger ? Qt.rgba(1, 0.35, 0.35, 0.22) : Theme.hoverStrong
        return Qt.rgba(1, 1, 1, 0.10)
    }

    Behavior on color {
        ColorAnimation { duration: Theme.animFast }
    }

    scale: mouse.pressed ? 0.96 : 1
    Behavior on scale {
        NumberAnimation { duration: 80; easing.type: Easing.OutCubic }
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 8

        Text {
            text: root.icon
            color: root.danger && !root.active ? (root.hovered ? "#ff8888" : "#ff6666")
                 : Theme.popupText
            font.family: Theme.iconFontFallback
            font.pixelSize: 15
            Layout.alignment: Qt.AlignVCenter

            Behavior on color {
                ColorAnimation { duration: Theme.animFast }
            }
        }

        Text {
            visible: root.label.length > 0
            text: root.label
            color: Theme.popupText
            opacity: root.hovered && !root.active ? 1 : (root.active ? 1 : 0.92)
            font.family: Theme.fontFamily
            font.pixelSize: 13
            font.weight: Font.Medium
            Layout.alignment: Qt.AlignVCenter
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
