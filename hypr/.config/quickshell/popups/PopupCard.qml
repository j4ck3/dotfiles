import QtQuick
import QtQuick.Layouts

import ".."

// Shared popup card chrome — solid panel, reliable height.
Item {
    id: root

    property alias title: titleLabel.text
    property bool showClose: true
    property int cardWidth: 360
    default property alias body: bodyCol.data

    signal closed

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.4)
    }

    Rectangle {
        id: card
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Theme.barHeight + 10
        anchors.rightMargin: 16
        width: root.cardWidth
        implicitHeight: inner.implicitHeight + 32
        height: implicitHeight
        radius: 18
        color: "#111111"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.14)

        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        ColumnLayout {
            id: inner
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 16
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    id: titleLabel
                    color: "#ffffff"
                    font.family: Theme.fontFamily
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                }

                Rectangle {
                    visible: root.showClose
                    width: 28
                    height: 28
                    radius: 14
                    color: Qt.rgba(1, 1, 1, 0.12)

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: Qt.rgba(1, 1, 1, 0.7)
                        font.pixelSize: 12
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closed()
                    }
                }
            }

            ColumnLayout {
                id: bodyCol
                Layout.fillWidth: true
                spacing: 12
            }
        }
    }
}
