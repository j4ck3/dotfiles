import QtQuick
import QtQuick.Layouts

import ".."

// macOS / Waybar-style stacked metric: small label over value.
Item {
    id: root

    property string label: ""
    property string value: "--"
    property string tooltip: ""
    property bool alert: false
    property bool muted: false

    implicitWidth: Math.max(labelText.implicitWidth, valueText.implicitWidth) + 4
    implicitHeight: col.implicitHeight
    Layout.preferredWidth: implicitWidth
    Layout.fillHeight: true

    Column {
        id: col
        anchors.centerIn: parent
        spacing: -1

        Text {
            id: labelText
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            color: Theme.inkMuted
            font.family: Theme.fontFamily
            font.pixelSize: 9
            font.weight: Font.Medium
            font.letterSpacing: 0.3
            opacity: 0.7
        }

        Text {
            id: valueText
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.value
            color: root.alert ? "#ff4d4d"
                 : root.muted ? Theme.inkMuted
                 : Theme.ink
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.weight: Font.Medium
            opacity: root.muted ? 0.7 : 0.95
        }
    }
}
