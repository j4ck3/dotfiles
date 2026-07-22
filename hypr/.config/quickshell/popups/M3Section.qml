import QtQuick
import QtQuick.Layouts

import ".."

// Section block with correct implicit height (no collapsed body).
ColumnLayout {
    id: root
    property string title: ""
    default property alias content: body.data

    Layout.fillWidth: true
    spacing: 6

    Text {
        visible: root.title.length > 0
        text: root.title
        color: Qt.rgba(1, 1, 1, 0.45)
        font.family: Theme.fontFamily
        font.pixelSize: 10
        font.weight: Font.DemiBold
        font.letterSpacing: 1.0
    }

    Rectangle {
        id: box
        Layout.fillWidth: true
        radius: 14
        color: Qt.rgba(1, 1, 1, 0.08)
        implicitHeight: body.implicitHeight + 20
        height: implicitHeight
        clip: true

        ColumnLayout {
            id: body
            x: 12
            y: 10
            width: box.width - 24
            spacing: 8
        }
    }
}
