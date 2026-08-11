import QtQuick
import QtQuick.Layouts

import ".."

// Shared popup card chrome — solid panel under the bar (top-right).
Item {
    id: root

    property string title: ""
    property bool showClose: false
    property int cardWidth: 360
    property int topMargin: Theme.widgetTopGap
    property int rightMargin: 16
    property bool animateIn: false
    property bool compact: false
    default property alias body: bodyCol.data

    signal closed
    signal cardHover(bool inside)

    Rectangle {
        anchors.fill: parent
        color: "transparent"
    }

    Rectangle {
        id: card

        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: root.topMargin
        anchors.rightMargin: root.rightMargin
        width: root.cardWidth
        implicitHeight: inner.implicitHeight + (root.compact ? 22 : 32)
        height: implicitHeight
        radius: root.compact ? 14 : 18
        color: "#111111"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.14)

        // Driven by playIn() — slide down + fade
        property real slideY: 0
        opacity: root.animateIn ? 0 : 1
        transform: Translate { y: card.slideY }

        ParallelAnimation {
            id: inAnim
            NumberAnimation {
                target: card
                property: "slideY"
                from: -22
                to: 0
                duration: 160
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: card
                property: "opacity"
                from: 0
                to: 1
                duration: 140
                easing.type: Easing.OutCubic
            }
        }

        HoverHandler {
            onHoveredChanged: root.cardHover(hovered)
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        ColumnLayout {
            id: inner
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: root.compact ? 12 : 16
            spacing: root.compact ? 10 : 14

            ColumnLayout {
                id: bodyCol
                Layout.fillWidth: true
                spacing: root.compact ? 8 : 12
            }
        }
    }

    function playIn(): void {
        if (!root.animateIn) {
            card.slideY = 0
            card.opacity = 1
            return
        }
        inAnim.stop()
        card.slideY = -22
        card.opacity = 0
        inAnim.restart()
    }

    function resetOut(): void {
        inAnim.stop()
        if (root.animateIn) {
            card.slideY = -22
            card.opacity = 0
        }
    }

    Component.onCompleted: {
        if (root.animateIn) {
            card.slideY = -22
            card.opacity = 0
        }
    }
}
