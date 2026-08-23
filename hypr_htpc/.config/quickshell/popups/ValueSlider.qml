import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

ColumnLayout {
    id: root

    // Volume popup passes a node object; display popup can pass `percent` directly.
    property var node: null
    property real percent: {
        if (node && node.percent !== undefined && node.percent !== null)
            return node.percent
        return minimum
    }
    property string icon: ""
    property string fallbackLabel: ""
    property string emptyText: ""
    property bool streamLabel: false
    property int minimum: 0
    property int maximum: 150

    property bool interacting: false
    property bool hasNode: node !== null && node !== undefined
    readonly property int shownValue: Math.round(slider.value)

    // Live drag updates (optimistic / lightweight).
    signal valuePreviewed(var node, int value)
    // Final value on release / icon reset.
    signal valueRequested(var node, int value)
    signal muteRequested(var node)
    signal interactionChanged(bool active)

    spacing: 7

    Component.onCompleted: slider.value = percent

    onPercentChanged: {
        if (!interacting && !slider.pressed)
            slider.value = percent
    }

    onMinimumChanged: slider.from = minimum
    onMaximumChanged: slider.to = maximum

    function beginInteract(): void {
        if (interacting)
            return
        interacting = true
        interactionChanged(true)
    }

    function endInteract(): void {
        releaseGuard.restart()
    }

    Timer {
        id: releaseGuard
        interval: 500
        onTriggered: {
            root.interacting = false
            root.interactionChanged(false)
            if (!slider.pressed
                    && Math.round(slider.value) !== Math.round(root.percent))
                slider.value = root.percent
        }
    }

    Text {
        visible: !root.hasNode && root.emptyText.length > 0
        text: root.emptyText
        color: Theme.inkMuted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.bodyFont
    }

    RowLayout {
        visible: root.hasNode || root.emptyText.length === 0
        Layout.fillWidth: true

        PopupButton {
            implicitWidth: 48
            text: root.hasNode && root.node.muted ? "󰝟" : root.icon
            onClicked: root.muteRequested(root.node)
        }
        Text {
            Layout.fillWidth: true
            color: Theme.ink
            font.family: Theme.fontFamily
            font.pixelSize: Theme.bodyFont
            elide: Text.ElideRight
            text: {
                if (!root.hasNode)
                    return root.fallbackLabel
                const name = root.node.description || root.node.name || root.fallbackLabel
                if (root.streamLabel && root.node.title
                        && root.node.title !== root.node.name)
                    return name + " — " + root.node.title
                return name
            }
        }
        Text {
            color: Theme.ink
            font.family: Theme.fontFamily
            font.pixelSize: Theme.bodyFont
            text: root.shownValue + "%"
            Layout.minimumWidth: 58
            horizontalAlignment: Text.AlignRight
        }
    }

    Slider {
        id: slider
        visible: root.hasNode || root.emptyText.length === 0
        Layout.fillWidth: true
        Layout.preferredHeight: 40
        from: root.minimum
        to: root.maximum
        live: true
        wheelEnabled: true
        touchDragThreshold: 0
        // Intentionally NOT bound to percent — owned value avoids grip loss.

        onMoved: {
            root.beginInteract()
            previewDebounce.restart()
        }

        onPressedChanged: {
            if (pressed) {
                root.beginInteract()
                previewDebounce.stop()
            } else {
                previewDebounce.stop()
                root.valueRequested(root.node, Math.round(value))
                root.endInteract()
            }
        }

        Timer {
            id: previewDebounce
            interval: 50
            onTriggered: root.valuePreviewed(root.node, Math.round(slider.value))
        }

        background: Item {
            x: slider.leftPadding
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            width: slider.availableWidth
            height: 16

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 10
                radius: 5
                color: Theme.surface
                Rectangle {
                    width: slider.visualPosition * parent.width
                    height: parent.height
                    radius: 5
                    color: Theme.ink
                }
            }
        }

        handle: Rectangle {
            x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            width: 30
            height: 30
            radius: 15
            color: Theme.ink
            border.width: slider.pressed ? 2 : 0
            border.color: Theme.active
            scale: slider.pressed ? 1.1 : 1.0
            Behavior on scale { NumberAnimation { duration: 70 } }
        }
    }
}
