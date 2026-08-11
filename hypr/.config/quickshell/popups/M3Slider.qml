import QtQuick
import QtQuick.Controls

import ".."

// High-contrast B&W slider for volume mixer / media seek.
Slider {
    id: root

    property color fillColor: "#ffffff"
    property color trackColor: Qt.rgba(1, 1, 1, 0.15)
    property int trackHeight: 6
    property bool showHandle: true
    property int handleSize: 16
    // Extra vertical hit padding around the track (makes long drags easier).
    property int hitPad: 12
    // Visual tick marks only (same units as value). No magnetic snap —
    // that fought PipeWire / volume-guard and broke drags.
    property var tickMarks: []

    from: 0
    to: 100
    implicitHeight: showHandle
        ? Math.max(32, trackHeight + hitPad * 2, handleSize + hitPad)
        : Math.max(28, trackHeight + hitPad * 2)
    padding: 0
    topPadding: hitPad
    bottomPadding: hitPad
    live: true

    background: Item {
        x: root.leftPadding
        y: root.topPadding + (root.availableHeight - height) / 2
        implicitWidth: 200
        implicitHeight: root.trackHeight
        width: root.availableWidth
        height: root.trackHeight

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: root.trackColor
        }

        Rectangle {
            width: Math.max(0, root.visualPosition * parent.width)
            height: parent.height
            radius: height / 2
            color: root.fillColor
        }

        Repeater {
            model: root.tickMarks
            Rectangle {
                required property var modelData
                readonly property real pos: {
                    var span = root.to - root.from
                    if (span <= 0)
                        return 0
                    return (Number(modelData) - root.from) / span
                }
                visible: pos > 0.02 && pos < 0.98
                width: 2
                height: parent.height + 6
                radius: 1
                color: Qt.rgba(1, 1, 1, 0.45)
                x: pos * parent.width - width / 2
                y: (parent.height - height) / 2
            }
        }
    }

    handle: Rectangle {
        x: root.leftPadding + root.visualPosition * (root.availableWidth - width)
        y: root.topPadding + (root.availableHeight - height) / 2
        implicitWidth: root.showHandle
            ? (root.hovered || root.pressed ? root.handleSize + 2 : root.handleSize)
            : 0
        implicitHeight: implicitWidth
        radius: width / 2
        color: "#ffffff"
        border.width: 0
        visible: root.showHandle
        scale: root.pressed ? 0.92 : 1

        Behavior on implicitWidth {
            enabled: root.showHandle
            NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            enabled: root.showHandle
            NumberAnimation { duration: 80; easing.type: Easing.OutCubic }
        }
    }
}
