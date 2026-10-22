import QtQuick
import QtQuick.Layouts
import Quickshell

import ".."

// macOS / Waybar-style stacked metric: small label over value.
Item {
    id: root

    property string label: ""
    property string value: "--"
    property string tooltip: ""
    property bool alert: false
    property bool muted: false
    property bool centerText: false
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
        anchors.left: root.centerText ? undefined : parent.left
        anchors.horizontalCenter: root.centerText ? parent.horizontalCenter : undefined
        width: Math.max(labelText.implicitWidth, valueText.implicitWidth)
        anchors.verticalCenter: parent.verticalCenter
        spacing: -1

        Text {
            id: labelText
            anchors.horizontalCenter: root.centerText ? parent.horizontalCenter : undefined
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
            anchors.horizontalCenter: root.centerText ? parent.horizontalCenter : undefined
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

    PopupWindow {
        id: tip
        color: "transparent"
        visible: root.hovered && root.tooltip.length > 0
        implicitWidth: tipBox.implicitWidth
        implicitHeight: tipBox.implicitHeight

        anchor {
            window: root.QsWindow?.window
            adjustment: PopupAdjustment.None
            gravity: Theme.barVertical ? (Edges.Right | Edges.Bottom) : (Edges.Bottom | Edges.Right)

            onAnchoring: {
                const win = root.QsWindow
                if (!win?.contentItem)
                    return
                const gap = 8
                if (Theme.barVertical) {
                    const pos = win.contentItem.mapFromItem(
                        root,
                        root.width + gap,
                        (root.height - tip.height) / 2
                    )
                    tip.anchor.rect.x = pos.x
                    tip.anchor.rect.y = pos.y
                } else {
                    const pos = win.contentItem.mapFromItem(
                        root,
                        (root.width - tip.width) / 2,
                        root.height + gap
                    )
                    tip.anchor.rect.x = pos.x
                    tip.anchor.rect.y = pos.y
                }
            }
        }

        Rectangle {
            id: tipBox
            implicitWidth: tipText.implicitWidth + 16
            implicitHeight: tipText.implicitHeight + 10
            radius: 8
            color: "#111111"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.14)

            Text {
                id: tipText
                anchors.centerIn: parent
                text: root.tooltip
                color: Theme.ink
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.weight: Font.Medium
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
