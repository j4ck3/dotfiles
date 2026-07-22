import QtQuick
import QtQuick.Layouts

import ".."

// Floating capsule / pill used for bar module groups (caelestia-style).
Rectangle {
    id: root

    default property alias content: body.data
    property int hPad: Theme.modulePad
    property int vPad: 0
    property color pillColor: Theme.surfaceContainer
    property real pillOpacity: 1

    implicitWidth: body.implicitWidth + hPad * 2
    implicitHeight: Theme.barInnerHeight
    radius: Theme.pillRadius
    color: Qt.rgba(pillColor.r, pillColor.g, pillColor.b, pillColor.a * pillOpacity)
    border.width: 0
    clip: true

    RowLayout {
        id: body
        anchors.centerIn: parent
        spacing: 8
        height: parent.height
    }
}
