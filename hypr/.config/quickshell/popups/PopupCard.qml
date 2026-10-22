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
    property int bottomMargin: Theme.widgetTopGap
    // Left bar → card docks left (rightMargin reused as left edge gap).
    readonly property bool fromLeft: Theme.barVertical
    // Left-bar bottom triggers (power) → dock card to bottom so hover path is short.
    property bool fromBottom: false
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

        anchors.top: root.fromBottom ? undefined : parent.top
        anchors.bottom: root.fromBottom ? parent.bottom : undefined
        anchors.left: root.fromLeft ? parent.left : undefined
        anchors.right: root.fromLeft ? undefined : parent.right
        anchors.topMargin: root.fromBottom ? 0 : root.topMargin
        anchors.bottomMargin: root.fromBottom ? root.bottomMargin : 0
        anchors.leftMargin: root.fromLeft ? root.rightMargin : 0
        anchors.rightMargin: root.fromLeft ? 0 : root.rightMargin
        width: root.cardWidth
        implicitHeight: inner.implicitHeight + (root.compact ? 24 : 28)
        height: implicitHeight
        radius: 22
        color: Theme.popupSurface
        border.width: 1
        border.color: Theme.popupBorder

        // Driven by playIn() — slide in + fade
        property real slideY: 0
        property real slideX: 0
        opacity: root.animateIn ? 0 : 1
        transform: Translate {
            x: card.slideX
            y: card.slideY
        }

        ParallelAnimation {
            id: inAnim
            NumberAnimation {
                target: card
                property: root.fromLeft ? "slideX" : "slideY"
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
            anchors.margins: root.compact ? 12 : 14
            spacing: 12

            ColumnLayout {
                id: bodyCol
                Layout.fillWidth: true
                spacing: root.compact ? 8 : 12
            }
        }
    }

    function playIn(): void {
        if (!root.animateIn) {
            card.slideX = 0
            card.slideY = 0
            card.opacity = 1
            return
        }
        inAnim.stop()
        card.slideX = root.fromLeft ? -22 : 0
        card.slideY = root.fromLeft ? 0 : (root.fromBottom ? 22 : -22)
        card.opacity = 0
        inAnim.restart()
    }

    function resetOut(): void {
        inAnim.stop()
        if (root.animateIn) {
            card.slideX = root.fromLeft ? -22 : 0
            card.slideY = root.fromLeft ? 0 : (root.fromBottom ? 22 : -22)
            card.opacity = 0
        }
    }

    Component.onCompleted: {
        if (root.animateIn) {
            card.slideX = root.fromLeft ? -22 : 0
            card.slideY = root.fromLeft ? 0 : (root.fromBottom ? 22 : -22)
            card.opacity = 0
        }
    }
}
