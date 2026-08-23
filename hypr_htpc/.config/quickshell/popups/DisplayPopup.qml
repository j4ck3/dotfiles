import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import ".."

PanelWindow {
    id: root
    visible: Globals.displayOpen
    color: "transparent"
    exclusiveZone: 0
    anchors.top: true
    anchors.right: true
    margins.top: Theme.barHeight + 8
    margins.right: 16
    implicitWidth: 510
    implicitHeight: card.implicitHeight
    WlrLayershell.namespace: "quickshell-htpc-display"
    WlrLayershell.layer: WlrLayer.Overlay

    property var display: ({
        monitor: null, mode: "desktop", hdr: false,
        hdrBrightness: 100, bluelight: 0, presets: []
    })

    // Flat optimistic fields — nested `display.*` mutations do not notify QML bindings.
    property int brightness: 100
    property int bluelight: 0
    property int sliderUsers: 0
    readonly property bool sliderBusy: sliderUsers > 0

    function refresh(): void {
        if (sliderBusy || status.running)
            return
        status.running = true
    }

    function apply(action: string, value: var): void {
        Quickshell.execDetached([
            Globals.scriptsDir + "/display-popup-control.sh",
            action, String(value)
        ])
        if (!sliderBusy)
            refreshDelay.restart()
    }

    // Instant path while dragging — no bash, no JSON refresh.
    function previewBrightness(value: int): void {
        brightness = value
        Quickshell.execDetached([
            "hyprctl", "hyprsunset", "gamma", String(value)
        ])
    }

    function commitBrightness(value: int): void {
        brightness = value
        apply("brightness", value)
    }

    function previewBluelight(value: int): void {
        bluelight = value
        if (value <= 0) {
            Quickshell.execDetached(["hyprctl", "hyprsunset", "identity"])
            return
        }
        const kelvin = Math.max(3000, Math.min(6500, Math.round(6500 - value * 35)))
        Quickshell.execDetached([
            "hyprctl", "hyprsunset", "temperature", String(kelvin)
        ])
    }

    function commitBluelight(value: int): void {
        bluelight = value
        apply("bluelight", value)
    }

    function onSliderInteraction(active: bool): void {
        sliderUsers = Math.max(0, sliderUsers + (active ? 1 : -1))
    }

    Rectangle {
        id: card
        width: parent.width
        implicitHeight: content.implicitHeight + 36
        radius: Theme.radius
        color: Theme.panel
        border.width: 1
        border.color: Theme.border

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: 18
            spacing: 11

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: "Display"
                    color: Theme.ink
                    font.family: Theme.fontFamily
                    font.pixelSize: 22
                    font.bold: true
                }
                PopupButton { text: "Close"; onClicked: Globals.displayOpen = false }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: monitorText.implicitHeight + 28
                radius: 14
                color: Theme.surface
                border.width: 1
                border.color: Theme.border
                Text {
                    id: monitorText
                    anchors.fill: parent
                    anchors.margins: 14
                    color: Theme.ink
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.bodyFont
                    wrapMode: Text.WordWrap
                    text: root.display.monitor
                        ? root.display.monitor.width + "×" + root.display.monitor.height
                            + " @ " + Math.round(root.display.monitor.refreshRate) + " Hz\n"
                            + root.display.monitor.name + " · "
                            + String(root.display.monitor.color).toUpperCase()
                        : "No active monitor found."
                }
            }

            Text {
                text: "RESOLUTION / REFRESH RATE"
                color: Theme.inkMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.smallFont
                font.bold: true
            }

            Repeater {
                model: root.display.presets || []
                delegate: PopupButton {
                    required property var modelData
                    Layout.fillWidth: true
                    text: modelData.label + "  ·  " + modelData.detail
                    active: root.display.mode === modelData.id
                    onClicked: root.apply("mode", modelData.id)
                }
            }

            Text {
                text: "BRIGHTNESS"
                color: Theme.inkMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.smallFont
                font.bold: true
            }
            ValueSlider {
                Layout.fillWidth: true
                percent: root.brightness
                fallbackLabel: "Brightness"
                icon: "BR"
                minimum: 50
                maximum: 200
                onMuteRequested: root.commitBrightness(100)
                onValuePreviewed: (node, value) => root.previewBrightness(value)
                onValueRequested: (node, value) => root.commitBrightness(value)
                onInteractionChanged: active => root.onSliderInteraction(active)
            }

            Text {
                text: "HDR"
                color: Theme.inkMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.smallFont
                font.bold: true
            }
            PopupButton {
                Layout.fillWidth: true
                text: root.display.hdr ? "HDR enabled" : "HDR disabled"
                active: root.display.hdr
                onClicked: root.apply("hdr", "toggle")
            }

            Text {
                text: "BLUE-LIGHT FILTER"
                color: Theme.inkMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.smallFont
                font.bold: true
            }
            ValueSlider {
                Layout.fillWidth: true
                percent: root.bluelight
                fallbackLabel: "Night filter"
                icon: "N"
                minimum: 0
                maximum: 100
                onMuteRequested: root.commitBluelight(0)
                onValuePreviewed: (node, value) => root.previewBluelight(value)
                onValueRequested: (node, value) => root.commitBluelight(value)
                onInteractionChanged: active => root.onSliderInteraction(active)
            }
        }
    }

    Process {
        id: status
        command: [Globals.scriptsDir + "/display-popup-data.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    root.display = d
                    // Do not yank optimistic values while the user is dragging.
                    if (!root.sliderBusy) {
                        if (d.hdrBrightness !== undefined)
                            root.brightness = d.hdrBrightness
                        if (d.bluelight !== undefined)
                            root.bluelight = d.bluelight
                    }
                } catch (error) {
                    console.warn("display data:", error)
                }
            }
        }
    }

    Timer {
        interval: 2000
        running: root.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Timer {
        id: refreshDelay
        interval: 400
        onTriggered: root.refresh()
    }
}
