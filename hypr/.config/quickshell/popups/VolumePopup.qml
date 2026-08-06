import QtQuick
import QtQuick.Layouts
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
        top: Theme.barHeight
    }

    WlrLayershell.namespace: "qs-volume"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource
    readonly property real sinkVol: sink?.audio ? sink.audio.volume * 100 : 0
    readonly property real sourceVol: source?.audio ? source.audio.volume * 100 : 0
    readonly property bool sinkMuted: sink?.audio?.muted ?? false
    readonly property bool sourceMuted: source?.audio?.muted ?? false

    property var streams: []
    // While >0, skip stream polls (they recreate delegates and drop the drag).
    property int sliderDragCount: 0
    readonly property bool sliderDragging: sliderDragCount > 0
    property bool cardHovering: false

    PwObjectTracker {
        objects: [root.sink, root.source].filter(n => !!n)
    }

    function beginSliderDrag(): void {
        root.sliderDragCount++
        Globals.setVolumeHover(true)
    }

    function endSliderDrag(): void {
        root.sliderDragCount = Math.max(0, root.sliderDragCount - 1)
        if (root.sliderDragCount === 0) {
            streamRefreshTimer.restart()
            if (!root.cardHovering)
                Globals.setVolumeHover(false)
        }
    }

    function refreshStreams(): void {
        if (root.sliderDragging)
            return
        streamProc.running = true
    }

    function runStreamControl(args: var): void {
        Quickshell.execDetached([Globals.scriptsDir + "/volume-popup-control.sh"].concat(args))
        streamRefreshTimer.restart()
    }

    onVisibleChanged: {
        if (visible) {
            root.refreshStreams()
            card.playIn()
        } else {
            card.resetOut()
        }
    }

    Process {
        id: streamProc
        command: [Globals.scriptsDir + "/volume-popup-data.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text.trim())
                    root.streams = data.streams || []
                } catch (e) {
                    root.streams = []
                }
            }
        }
    }

    Timer {
        id: streamRefreshTimer
        interval: 180
        onTriggered: root.refreshStreams()
    }

    Timer {
        interval: 1000
        running: root.visible && !root.sliderDragging
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshStreams()
    }

    MouseArea {
        anchors.fill: parent
        onClicked: Globals.volumeOpen = false
    }

    PopupCard {
        id: card
        anchors.fill: parent
        title: "Volume"
        cardWidth: 320
        topMargin: Theme.widgetTopGap
        rightMargin: Globals.volumePopupRightMargin
        animateIn: true
        onClosed: Globals.volumeOpen = false
        onCardHover: inside => {
            root.cardHovering = inside
            // Keep open while dragging even if pointer leaves the card.
            if (!inside && root.sliderDragging)
                return
            Globals.setVolumeHover(inside)
        }

        M3Section {
            title: "OUTPUT"
            visible: root.sink && root.sink.audio

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                M3IconButton {
                    icon: root.sinkMuted ? "󰝟" : "󰕾"
                    active: !root.sinkMuted
                    onClicked: {
                        if (root.sink?.audio)
                            root.sink.audio.muted = !root.sink.audio.muted
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: root.sink?.description || root.sink?.nickname || root.sink?.name || "Output"
                        color: "#ffffff"
                        font.pixelSize: 13
                        font.family: Theme.fontFamily
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        text: Math.round(sinkSlider.pressed ? sinkSlider.value : root.sinkVol) + "%"
                        color: Qt.rgba(1, 1, 1, 0.55)
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }
            }

            M3Slider {
                id: sinkSlider
                Layout.fillWidth: true
                Layout.leftMargin: 46
                from: 0
                to: 150
                tickMarks: [100]
                fillColor: "#ffffff"
                trackColor: Qt.rgba(1, 1, 1, 0.18)
                trackHeight: 4
                showHandle: true

                Binding {
                    target: sinkSlider
                    property: "value"
                    value: root.sinkVol
                    when: !sinkSlider.pressed
                    restoreMode: Binding.RestoreNone
                }

                onMoved: {
                    if (root.sink?.audio)
                        root.sink.audio.volume = Math.max(0, Math.min(1.5, value / 100))
                }
                onPressedChanged: {
                    if (pressed)
                        root.beginSliderDrag()
                    else
                        root.endSliderDrag()
                }
            }
        }

        M3Section {
            title: "MICROPHONE"
            visible: root.source && root.source.audio

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                M3IconButton {
                    icon: root.sourceMuted ? "󰍭" : "󰍬"
                    active: !root.sourceMuted
                    onClicked: {
                        if (root.source?.audio)
                            root.source.audio.muted = !root.source.audio.muted
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: root.source?.description || root.source?.nickname || root.source?.name || "Microphone"
                        color: "#ffffff"
                        font.pixelSize: 13
                        font.family: Theme.fontFamily
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        text: Math.round(sourceSlider.pressed ? sourceSlider.value : root.sourceVol) + "%"
                        color: Qt.rgba(1, 1, 1, 0.55)
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }
            }

            M3Slider {
                id: sourceSlider
                Layout.fillWidth: true
                Layout.leftMargin: 46
                from: 0
                to: 150
                tickMarks: [100]
                fillColor: "#ffffff"
                trackColor: Qt.rgba(1, 1, 1, 0.18)
                trackHeight: 4
                showHandle: true

                Binding {
                    target: sourceSlider
                    property: "value"
                    value: root.sourceVol
                    when: !sourceSlider.pressed
                    restoreMode: Binding.RestoreNone
                }

                onMoved: {
                    if (root.source?.audio)
                        root.source.audio.volume = Math.max(0, Math.min(1.5, value / 100))
                }
                onPressedChanged: {
                    if (pressed)
                        root.beginSliderDrag()
                    else
                        root.endSliderDrag()
                }
            }
        }

        M3Section {
            title: "APPS"
            visible: root.streams.length > 0

            Repeater {
                model: root.streams

                ColumnLayout {
                    id: streamRow
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 6

                    property real uiPercent: modelData.percent
                    property bool hold: false

                    onModelDataChanged: {
                        if (streamSlider.pressed || streamRow.hold)
                            return
                        streamRow.uiPercent = modelData.percent
                    }

                    Timer {
                        id: streamHoldTimer
                        interval: 900
                        onTriggered: {
                            streamRow.hold = false
                            streamRow.uiPercent = streamRow.modelData.percent
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        M3IconButton {
                            icon: modelData.muted ? "󰝟" : "󰎆"
                            onClicked: root.runStreamControl(["toggle-mute", "stream", String(modelData.id)])
                        }

                        Text {
                            text: {
                                if (modelData.title && modelData.title !== modelData.name)
                                    return (modelData.name || "App") + " — " + modelData.title
                                return modelData.name || modelData.title || "App"
                            }
                            color: "#ffffff"
                            font.pixelSize: 12
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Text {
                            text: Math.round(streamSlider.pressed ? streamSlider.value : streamRow.uiPercent) + "%"
                            color: Qt.rgba(1, 1, 1, 0.5)
                            font.pixelSize: 11
                        }
                    }

                    M3Slider {
                        id: streamSlider
                        Layout.fillWidth: true
                        Layout.leftMargin: 46
                        from: 0
                        to: 150
                        tickMarks: [100]
                        fillColor: "#ffffff"
                        trackColor: Qt.rgba(1, 1, 1, 0.18)
                        trackHeight: 4
                        showHandle: true

                        Binding {
                            target: streamSlider
                            property: "value"
                            value: streamRow.uiPercent
                            when: !streamSlider.pressed
                            restoreMode: Binding.RestoreNone
                        }

                        onMoved: {
                            const v = Math.round(value)
                            streamRow.uiPercent = v
                            streamRow.hold = true
                            streamHoldTimer.restart()
                            Quickshell.execDetached([
                                Globals.scriptsDir + "/volume-popup-control.sh",
                                "set", "stream", String(modelData.id), String(v)
                            ])
                        }
                        onPressedChanged: {
                            if (pressed)
                                root.beginSliderDrag()
                            else {
                                root.endSliderDrag()
                                streamRefreshTimer.restart()
                            }
                        }
                    }
                }
            }
        }

        M3IconButton {
            Layout.fillWidth: true
            wide: true
            icon: "󰒓"
            label: "Open Mixer"
            onClicked: {
                Quickshell.execDetached(["pavucontrol"])
                Globals.volumeOpen = false
            }
        }
    }
}
