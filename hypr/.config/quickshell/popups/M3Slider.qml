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
    property bool flatFillEdge: false
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
        x: root.leftPadding + (root.availableWidth - width) / 2
        y: root.topPadding + (root.availableHeight - height) / 2
        implicitWidth: 200
        implicitHeight: root.trackHeight
        width: root.orientation === Qt.Vertical ? root.trackHeight : root.availableWidth
        height: root.orientation === Qt.Vertical ? root.availableHeight : root.trackHeight

        Rectangle {
            anchors.fill: parent
            radius: Math.min(width, height) / 2
            color: root.trackColor
        }

        Item {
            anchors.fill: parent
            visible: root.flatFillEdge
            clip: true

            Item {
                width: root.orientation === Qt.Vertical ? parent.width : root.position * parent.width
                height: root.orientation === Qt.Vertical ? root.position * parent.height : parent.height
                y: parent.height - height
                clip: true

                Rectangle {
                    width: root.background.width
                    height: root.background.height
                    y: root.orientation === Qt.Vertical ? parent.height - height : 0
                    radius: Math.min(width, height) / 2
                    color: root.fillColor
                }
            }
        }

        Rectangle {
            visible: !root.flatFillEdge
            // Pill fills share the thumb's rounded end; thin tracks meet its center.
            width: root.showHandle
                ? root.handle.x - root.leftPadding + root.handle.width * (root.trackHeight >= 16 ? 1 : 0.5)
                : Math.max(0, root.visualPosition * parent.width)
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
                height: root.trackHeight >= 16 ? 6 : parent.height + 6
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
            ? (root.trackHeight >= 16 ? root.handleSize
                : (root.hovered || root.pressed ? root.handleSize + 2 : root.handleSize))
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
