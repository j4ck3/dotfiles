import QtQuick
import Quickshell.Hyprland
import ".."

Row {
    id: root
    spacing: 2
    readonly property var workspaces: [1, 2, 3, 4]
    readonly property var labels: ["j", "k", "l", "ö"]
    readonly property int activeId: Hyprland.focusedWorkspace?.id ?? 1

    function occupied(id: int): bool {
        const values = Hyprland.workspaces.values
        for (let i = 0; i < values.length; i++) {
            if (values[i].id === id)
                return true
        }
        return false
    }

    Repeater {
        model: root.workspaces

        Rectangle {
            id: cell
            required property int modelData
            required property int index
            width: 46
            height: 42
            radius: 12
            color: root.activeId === modelData ? Theme.active
                : mouse.containsMouse ? Theme.surfaceHover : "transparent"
            border.width: root.activeId === modelData ? 1 : 0
            border.color: Theme.border

            Text {
                anchors.centerIn: parent
                text: root.labels[cell.index]
                color: root.activeId === cell.modelData ? Theme.ink
                    : root.occupied(cell.modelData) ? Theme.inkMuted
                    : Qt.rgba(1, 1, 1, 0.32)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.barFont
                font.weight: root.activeId === cell.modelData ? Font.DemiBold : Font.Medium
            }

            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Hyprland.dispatch(
                    "hl.dsp.focus({ workspace = " + cell.modelData
                    + ", on_current_monitor = true })")
            }
        }
    }
}
