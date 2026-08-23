import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import ".."

PanelWindow {
    id: root
    visible: Globals.volumeOpen
    color: "transparent"
    exclusiveZone: 0
    anchors.top: true
    anchors.right: true
    margins.top: Theme.barHeight + 8
    margins.right: 16
    implicitWidth: 470
    implicitHeight: card.implicitHeight
    WlrLayershell.namespace: "quickshell-htpc-volume"
    WlrLayershell.layer: WlrLayer.Overlay

    property var audio: ({ sink: null, source: null, streams: [] })
    readonly property var activeApp: {
        const streams = audio.streams || []
        return streams.find(s => (s.name || "").toLowerCase() === "spotify")
            || streams[0] || null
    }

    function control(args: var): void {
        Quickshell.execDetached(
            [Globals.scriptsDir + "/volume-popup-control.sh"].concat(args))
        refreshDelay.restart()
    }

    function refresh(): void {
        if (!audioData.running)
            audioData.running = true
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
                    text: "Audio Mixer"
                    color: Theme.ink
                    font.family: Theme.fontFamily
                    font.pixelSize: 22
                    font.bold: true
                }
                PopupButton { text: "Close"; onClicked: Globals.volumeOpen = false }
            }

            Text {
                text: "OUTPUT"
                color: Theme.inkMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.smallFont
                font.bold: true
            }
            ValueSlider {
                Layout.fillWidth: true
                node: root.audio.sink
                icon: "󰕾"
                fallbackLabel: "Default output"
                emptyText: "No output device found."
                onMuteRequested: node =>
                    root.control(["toggle-mute", "sink", String(node.id)])
                onValuePreviewed: (node, value) =>
                    root.control(["set", "sink", String(node.id), String(value)])
                onValueRequested: (node, value) =>
                    root.control(["set", "sink", String(node.id), String(value)])
            }

            Text {
                text: "MICROPHONE"
                color: Theme.inkMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.smallFont
                font.bold: true
            }
            ValueSlider {
                Layout.fillWidth: true
                node: root.audio.source
                icon: "󰍬"
                fallbackLabel: "Default microphone"
                emptyText: "No microphone found."
                onMuteRequested: node =>
                    root.control(["toggle-mute", "source", String(node.id)])
                onValuePreviewed: (node, value) =>
                    root.control(["set", "source", String(node.id), String(value)])
                onValueRequested: (node, value) =>
                    root.control(["set", "source", String(node.id), String(value)])
            }

            Text {
                text: "APPLICATION"
                color: Theme.inkMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.smallFont
                font.bold: true
            }
            ValueSlider {
                Layout.fillWidth: true
                node: root.activeApp
                icon: node && (node.name || "").toLowerCase() === "spotify" ? "󰓇" : "󰎆"
                fallbackLabel: "Application"
                emptyText: "No active playback stream."
                streamLabel: true
                onMuteRequested: node =>
                    root.control(["toggle-mute", "stream", String(node.id)])
                onValuePreviewed: (node, value) =>
                    root.control(["set", "stream", String(node.id), String(value)])
                onValueRequested: (node, value) =>
                    root.control(["set", "stream", String(node.id), String(value)])
            }

            PopupButton {
                Layout.fillWidth: true
                text: "Open full mixer"
                onClicked: Quickshell.execDetached(["pavucontrol"])
            }
        }
    }

    Process {
        id: audioData
        command: [Globals.scriptsDir + "/volume-popup-data.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.audio = JSON.parse(text) }
                catch (error) { console.warn("audio data:", error) }
            }
        }
    }

    Timer {
        interval: 1000
        running: root.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Timer {
        id: refreshDelay
        interval: 100
        onTriggered: root.refresh()
    }
}
