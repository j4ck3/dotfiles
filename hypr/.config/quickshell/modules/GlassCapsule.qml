import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

import ".."

// Liquid Glass Regular capsule — floating nav/control material.
// Layers: shadow → fill → specular highlight → rim → content.
// No nested glass inside; children use fills / vibrancy.
Item {
    id: root

    default property alias content: body.data
    property int hPad: Theme.modulePad + 2
    property int vPad: 0
    property int capsuleHeight: Theme.barInnerHeight
    property bool interactive: true
    property bool elevated: false
    property real fillBoost: 0

    readonly property bool hovered: hover.hovered

    implicitWidth: body.implicitWidth + hPad * 2
    implicitHeight: capsuleHeight
    height: capsuleHeight
    Layout.preferredHeight: capsuleHeight
    Layout.fillHeight: false

    HoverHandler {
        id: hover
        enabled: root.interactive
    }

    RectangularShadow {
        anchors.fill: glassBody
        radius: glassBody.radius
        blur: root.elevated ? 18 : 12
        spread: 0
        color: Theme.glassShadow
        offset.y: root.elevated ? 3 : 1.5
        opacity: root.hovered && root.interactive ? 0.9 : 0.7

        Behavior on opacity {
            NumberAnimation { duration: Theme.animFast }
        }
    }

    Rectangle {
        id: glassBody
        anchors.fill: parent
        radius: height / 2
        color: {
            const base = root.hovered && root.interactive ? Theme.glassFillHover : Theme.glassFill
            if (root.fillBoost <= 0)
                return base
            return Qt.rgba(
                Math.min(1, base.r + root.fillBoost * 0.08),
                Math.min(1, base.g + root.fillBoost * 0.08),
                Math.min(1, base.b + root.fillBoost * 0.08),
                Math.min(1, base.a + root.fillBoost * 0.06)
            )
        }
        border.width: 1
        border.color: root.hovered && root.interactive ? Theme.glassRimHover : Theme.glassRim
        clip: true

        Behavior on color {
            ColorAnimation { duration: Theme.animFast }
        }
        Behavior on border.color {
            ColorAnimation { duration: Theme.animFast }
        }

        // Specular / lensing highlight (top)
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 1
            anchors.rightMargin: 1
            anchors.topMargin: 1
            height: Math.max(10, parent.height * 0.48)
            radius: parent.radius
            opacity: root.hovered && root.interactive ? 1 : 0.85
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.glassSpecular }
                GradientStop { position: 0.45; color: Theme.glassSpecularSoft }
                GradientStop { position: 1.0; color: "transparent" }
            }

            Behavior on opacity {
                NumberAnimation { duration: Theme.animFast }
            }
        }

        // Thickness cue (bottom shade)
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 1
            anchors.rightMargin: 1
            anchors.bottomMargin: 1
            height: Math.max(8, parent.height * 0.38)
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: Theme.glassShade }
            }
        }

        // Interaction glow — internal illuminate on hover
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: Theme.glassGlow
            opacity: root.hovered && root.interactive ? 1 : 0

            Behavior on opacity {
                NumberAnimation { duration: Theme.animFast }
            }
        }
    }

    RowLayout {
        id: body
        anchors.centerIn: parent
        spacing: 4
        height: parent.height - root.vPad * 2
        z: 1
    }
}
