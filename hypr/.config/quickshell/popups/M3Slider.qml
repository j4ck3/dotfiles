import QtQuick
import QtQuick.Controls

import ".."

// High-contrast B&W slider for volume mixer.
Slider {
    id: root

    property color fillColor: "#ffffff"
    property color trackColor: Qt.rgba(1, 1, 1, 0.15)

    from: 0
    to: 100
    implicitHeight: 24
    padding: 0
    live: true

    background: Item {
        x: root.leftPadding
        y: root.topPadding + (root.availableHeight - height) / 2
        implicitWidth: 200
        implicitHeight: 6
        width: root.availableWidth
        height: 6

        Rectangle {
            anchors.fill: parent
            radius: 3
            color: root.trackColor
        }

        Rectangle {
            width: Math.max(0, root.visualPosition * parent.width)
            height: parent.height
            radius: 3
            color: root.fillColor
        }
    }

    handle: Rectangle {
        x: root.leftPadding + root.visualPosition * (root.availableWidth - width)
        y: root.topPadding + (root.availableHeight - height) / 2
        implicitWidth: 14
        implicitHeight: 14
        radius: 7
        color: "#ffffff"
        border.width: 0
    }
}
