import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import ".."

PanelWindow {
    id: root
    visible: Globals.volumeOpen
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    margins {
        top: Theme.popupTopInset
        left: Theme.popupLeftInset
    }

    WlrLayershell.namespace: "qs-volume"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    readonly property int cardW: 300
    property bool cardHovering: false

    onVisibleChanged: {
        if (visible) {
            card.playIn()
        } else {
            card.resetOut()
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: Globals.volumeOpen = false
    }

    // ── Liquid-glass card ───────────────────────────────────────
    Item {
        id: card
        anchors.top: Theme.barVertical ? undefined : parent.top
        anchors.bottom: Theme.barVertical ? parent.bottom : undefined
        anchors.left: Theme.barVertical ? parent.left : undefined
        anchors.right: Theme.barVertical ? undefined : parent.right
        anchors.topMargin: Theme.barVertical ? 0 : Theme.widgetTopGap
        anchors.bottomMargin: Theme.barVertical ? Theme.widgetTopGap : 0
        anchors.leftMargin: Theme.barVertical ? Globals.volumePopupRightMargin : 0
        anchors.rightMargin: Theme.barVertical ? 0 : Globals.volumePopupRightMargin
        width: root.cardW
        implicitHeight: inner.implicitHeight + 28
        height: implicitHeight

        property real slideY: 0
        property real slideX: 0
        opacity: 0
        transform: Translate {
            x: card.slideX
            y: card.slideY
        }

        HoverHandler {
            id: cardHover
            onHoveredChanged: {
                root.cardHovering = hovered
                if (!hovered && inner.sliderDragging)
                    return
                Globals.setVolumeHover(hovered)
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        ParallelAnimation {
            id: inAnim
            NumberAnimation {
                target: card
                property: Theme.barVertical ? "slideX" : "slideY"
                from: -20
                to: 0
                duration: 170
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: card; property: "opacity"
                from: 0; to: 1; duration: 150; easing.type: Easing.OutCubic
            }
        }

        RectangularShadow {
            anchors.fill: glassBody
            radius: glassBody.radius
            blur: 26
            spread: 0
            color: Theme.glassShadow
            offset.y: 6
        }

        Rectangle {
            id: glassBody
            anchors.fill: parent
            radius: 22
            color: Theme.popupSurface
            border.width: 1
            border.color: Theme.popupBorder
            clip: true

            // Specular sheen — top lensing highlight
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 1
                anchors.rightMargin: 1
                anchors.topMargin: 1
                height: parent.height * 0.42
                radius: parent.radius
                opacity: 0.25
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.glassSpecularSoft }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            // Thickness cue — bottom shade
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: 1
                anchors.rightMargin: 1
                anchors.bottomMargin: 1
                height: parent.height * 0.3
                radius: parent.radius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: "#12000000" }
                }
            }
        }

        VolumeControls {
            id: inner
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 14
            onDragStateChanged: dragging => Globals.setVolumeHover(dragging || root.cardHovering)
            onSettingsOpened: Globals.volumeOpen = false
        }

        function playIn(): void {
            inAnim.stop()
            card.slideX = Theme.barVertical ? -20 : 0
            card.slideY = Theme.barVertical ? 0 : -20
            card.opacity = 0
            inAnim.restart()
        }

        function resetOut(): void {
            inAnim.stop()
            card.slideX = Theme.barVertical ? -20 : 0
            card.slideY = Theme.barVertical ? 0 : -20
            card.opacity = 0
        }

        Component.onCompleted: {
            card.slideX = Theme.barVertical ? -20 : 0
            card.slideY = Theme.barVertical ? 0 : -20
            card.opacity = 0
        }
    }
}
