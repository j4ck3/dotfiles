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

    signal clicked

    implicitWidth: wide ? Math.max(44, row.implicitWidth + 24) : 36
    implicitHeight: wide ? 36 : 36
    Layout.fillWidth: wide
    radius: wide ? 12 : 18
    color: root.active ? "#ffffff" : Qt.rgba(1, 1, 1, 0.10)

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 8

        Text {
            text: root.icon
            color: root.active ? "#000000"
                 : root.danger ? "#ff6666"
                 : "#ffffff"
            font.family: Theme.iconFontFallback
            font.pixelSize: 15
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            visible: root.label.length > 0
            text: root.label
            color: root.active ? "#000000" : "#ffffff"
            font.family: Theme.fontFamily
            font.pixelSize: 13
            font.weight: Font.Medium
            Layout.alignment: Qt.AlignVCenter
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
