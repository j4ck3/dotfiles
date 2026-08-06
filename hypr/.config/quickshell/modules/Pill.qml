import QtQuick
import QtQuick.Layouts

import ".."

// Floating capsule / pill used for bar module groups (caelestia-style).
Rectangle {
    id: root

    default property alias content: body.data
    property int hPad: Theme.modulePad
    property int vPad: 0
    property int pillHeight: Theme.barInnerHeight
    property color pillColor: Theme.surfaceContainer
    property real pillOpacity: 1
    property bool hoverLift: true

    readonly property bool hovered: hover.hovered

    implicitWidth: body.implicitWidth + hPad * 2
    implicitHeight: pillHeight
    height: pillHeight
    radius: Theme.pillRadius
    color: {
        const base = Qt.rgba(pillColor.r, pillColor.g, pillColor.b, pillColor.a * pillOpacity)
        if (!root.hoverLift || !root.hovered)
            return base
        return Qt.rgba(
            Math.min(1, base.r + 0.08),
            Math.min(1, base.g + 0.08),
            Math.min(1, base.b + 0.08),
            Math.min(1, base.a + 0.08)
        )
    }
    border.width: 0
    clip: true

    Behavior on color {
        ColorAnimation { duration: Theme.animFast }
    }

    HoverHandler { id: hover }

    RowLayout {
        id: body
        anchors.centerIn: parent
        spacing: 4
        height: parent.height
    }
}
