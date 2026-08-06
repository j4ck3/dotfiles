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
    readonly property bool hovered: hover.hovered

    implicitWidth: Math.max(labelText.implicitWidth, valueText.implicitWidth) + 4
    implicitHeight: col.implicitHeight + 4
    Layout.preferredWidth: implicitWidth
    Layout.fillHeight: true

    HoverHandler { id: hover }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -2
        radius: 8
        color: root.hovered ? Theme.hover : "transparent"
        Behavior on color {
            ColorAnimation { duration: Theme.animFast }
        }
    }

    Column {
        id: col
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: -1

        Text {
            id: labelText
            text: root.label
            color: root.hovered ? Theme.ink : Theme.inkMuted
            font.family: Theme.fontFamily
            font.pixelSize: 9
            font.weight: Font.Medium
            font.letterSpacing: 0.3
            opacity: root.hovered ? 0.9 : 0.7
            horizontalAlignment: Text.AlignLeft

            Behavior on color {
                ColorAnimation { duration: Theme.animFast }
            }
            Behavior on opacity {
                NumberAnimation { duration: Theme.animFast }
            }
        }

        Text {
            id: valueText
            text: root.value
            color: root.alert ? "#ff4d4d"
                 : root.muted ? Theme.inkMuted
                 : Theme.ink
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.weight: Font.Medium
            opacity: root.muted ? 0.7 : (root.hovered ? 1 : 0.95)
            horizontalAlignment: Text.AlignLeft

            Behavior on opacity {
                NumberAnimation { duration: Theme.animFast }
            }
        }
    }
}
