import QtQuick
import QtQuick.Layouts

import ".."

// Section block with correct implicit height (no collapsed body).
ColumnLayout {
    id: root
    property string title: ""
    default property alias content: body.data

    property bool compact: false

    Layout.fillWidth: true
    spacing: compact ? 4 : 6

    Rectangle {
        id: box
        Layout.fillWidth: true
        radius: 16
        color: Theme.popupTile
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.06)
        implicitHeight: body.implicitHeight + (root.compact ? 14 : 20)
        height: implicitHeight
        clip: true

        ColumnLayout {
            id: body
            x: root.compact ? 10 : 12
            y: root.compact ? 7 : 10
            width: box.width - (root.compact ? 20 : 24)
            spacing: root.compact ? 4 : 8
        }
    }
}
