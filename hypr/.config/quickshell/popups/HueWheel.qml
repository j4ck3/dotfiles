import QtQuick
import Quickshell

import ".."

// HSV color disc: angle = hue (0–360), radius = saturation (0–100).
// Disc is a pre-rendered PNG — Canvas pixel loops froze QS on open.
Item {
    id: root

    property real hue: 0
    property real saturation: 100
    readonly property bool pressed: dragArea.pressed

    signal hsMoved(real hue, real saturation)
    signal pressActive(bool active)

    implicitWidth: 168
    implicitHeight: 168

    function hsvToRgb(h: real, s: real, v: real): var {
        const hh = ((h % 360) + 360) % 360 / 60
        const c = v * s
        const x = c * (1 - Math.abs(hh % 2 - 1))
        const m = v - c
        let r = 0
        let g = 0
        let b = 0
        if (hh < 1) {
            r = c; g = x
        } else if (hh < 2) {
            r = x; g = c
        } else if (hh < 3) {
            g = c; b = x
        } else if (hh < 4) {
            g = x; b = c
        } else if (hh < 5) {
            r = x; b = c
        } else {
            r = c; b = x
        }
        return {
            r: Math.round((r + m) * 255),
            g: Math.round((g + m) * 255),
            b: Math.round((b + m) * 255)
        }
    }

    function handlePos(): var {
        const cx = width / 2
        const cy = height / 2
        const r = Math.min(cx, cy) - 2
        const rad = root.hue * Math.PI / 180
        const d = r * Math.max(0, Math.min(1, root.saturation / 100))
        return {
            x: cx + Math.cos(rad) * d,
            y: cy + Math.sin(rad) * d
        }
    }

    function applyPointer(px: real, py: real): void {
        const cx = width / 2
        const cy = height / 2
        const r = Math.min(cx, cy) - 2
        const dx = px - cx
        const dy = py - cy
        let ang = Math.atan2(dy, dx) * 180 / Math.PI
        if (ang < 0)
            ang += 360
        const dist = Math.sqrt(dx * dx + dy * dy)
        const sat = Math.max(0, Math.min(100, (dist / Math.max(1, r)) * 100))
        root.hue = ang
        root.saturation = sat
        root.hsMoved(ang, sat)
    }

    Image {
        id: disc
        anchors.fill: parent
        // Module-relative Qt.resolvedUrl broke; shellPath is config-root absolute.
        source: {
            const p = Quickshell.shellPath("assets/hue-wheel.png")
            return p.startsWith("file:") ? p : ("file://" + p)
        }
        fillMode: Image.PreserveAspectFit
        asynchronous: false
        mipmap: true
        smooth: true
        opacity: root.enabled ? 1 : 0.4
        visible: status === Image.Ready
    }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.18)
        opacity: root.enabled ? 1 : 0.4
        visible: disc.status === Image.Ready
    }

    Rectangle {
        id: handle
        width: 18
        height: 18
        radius: 9
        readonly property var pos: root.handlePos()
        x: pos.x - width / 2
        y: pos.y - height / 2
        readonly property var rgb: root.hsvToRgb(root.hue, root.saturation / 100, 1)
        color: Qt.rgba(rgb.r / 255, rgb.g / 255, rgb.b / 255, 1)
        border.width: 2
        border.color: "#ffffff"
        opacity: root.enabled ? 1 : 0.4
        z: 2
        scale: dragArea.pressed ? 0.92 : 1
        Behavior on scale {
            NumberAnimation { duration: 80; easing.type: Easing.OutCubic }
        }
    }

    MouseArea {
        id: dragArea
        anchors.fill: parent
        enabled: root.enabled
        preventStealing: true
        cursorShape: Qt.PointingHandCursor

        onPressed: mouse => {
            root.pressActive(true)
            root.applyPointer(mouse.x, mouse.y)
        }
        onPositionChanged: mouse => {
            if (pressed)
                root.applyPointer(mouse.x, mouse.y)
        }
        onReleased: root.pressActive(false)
        onCanceled: root.pressActive(false)
    }

    Component.onCompleted: {
        if (disc.status === Image.Error)
            console.warn("HueWheel: failed to load", disc.source, disc.errorString)
    }
    Connections {
        target: disc
        function onStatusChanged(): void {
            if (disc.status === Image.Error)
                console.warn("HueWheel: failed to load", disc.source, disc.errorString)
        }
    }
}
