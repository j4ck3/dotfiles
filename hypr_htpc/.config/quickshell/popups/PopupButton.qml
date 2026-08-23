import QtQuick
import QtQuick.Controls
import ".."

Button {
    id: root
    property bool active: false
    padding: 11
    background: Rectangle {
        radius: 12
        color: root.down ? Theme.active
            : root.active ? Theme.surfaceHover
            : root.hovered ? Theme.surfaceHover : Theme.surface
        border.width: 1
        border.color: root.active ? Theme.inkMuted : Theme.border
    }
    contentItem: Text {
        text: root.text
        color: Theme.ink
        font.family: Theme.fontFamily
        font.pixelSize: Theme.bodyFont
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
}
