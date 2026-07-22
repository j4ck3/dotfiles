import QtQuick
import QtQuick.Layouts

import ".."

// Compact centered card chrome for launcher / clipboard overlays.
Item {
    id: root

    property int cardWidth: 644
    property int cardHeight: 300
    default property alias body: bodyCol.data

    signal closed
    signal scrimClicked

    // Dim scrim
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)
        opacity: root.visible ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: 40 }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.scrimClicked()
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(root.cardWidth, parent.width - 48)
        height: Math.min(root.cardHeight, parent.height - 48)
        radius: 20
        color: "#000000"
        border.width: 1
        border.color: Theme.hairlineMuted

        scale: root.visible ? 1 : 0.98
        opacity: root.visible ? 1 : 0

        Behavior on scale {
            NumberAnimation {
                duration: 55
                easing.type: Easing.OutCubic
            }
        }
        Behavior on opacity {
            NumberAnimation { duration: 40 }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        ColumnLayout {
            id: bodyCol
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10
        }
    }
}
