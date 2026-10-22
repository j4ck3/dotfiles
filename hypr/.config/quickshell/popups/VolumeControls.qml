import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import ".."

ColumnLayout {
    id: root
    spacing: 10
    signal dragStateChanged(bool dragging)
    signal settingsOpened

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

    PwObjectTracker {
        objects: [root.sink, root.source].filter(n => !!n)
    }

    function beginSliderDrag(): void {
        root.sliderDragCount++
        root.dragStateChanged(true)
    }

    function endSliderDrag(): void {
        root.sliderDragCount = Math.max(0, root.sliderDragCount - 1)
        if (root.sliderDragCount === 0) {
            streamRefreshTimer.restart()
            root.dragStateChanged(false)
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

    Process {
        id: streamProc
        command: [Globals.scriptsDir + "/volume-popup-data.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text.trim())
                    if (!root.sliderDragging) root.streams = data.streams || []
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

    component AudioSlider: M3Slider {
        id: control
        property string glyph: ""
        property string appIcon: ""
        signal muteRequested()
        Layout.fillWidth: true
        Layout.preferredHeight: 144
        implicitWidth: 64
        Layout.minimumWidth: 64
        Layout.preferredWidth: 64
        orientation: Qt.Vertical
        flatFillEdge: true
        trackHeight: 56
        showHandle: false
        hitPad: 4
        trackColor: Qt.rgba(1, 1, 1, 0.18)
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 16
            width: 32
            height: 32
            z: 3
            Image {
                id: appImage
                anchors.centerIn: parent
                width: 24
                height: 24
                source: control.appIcon.length ? Quickshell.iconPath(control.appIcon, true) : ""
                visible: status === Image.Ready
                fillMode: Image.PreserveAspectFit
            }
            Text {
                anchors.centerIn: parent
                visible: appImage.status !== Image.Ready
                text: control.glyph
                color: control.position > 0.25 ? "#303038" : "#ffffff"
                font.family: Theme.iconFont
                font.pixelSize: 24
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: control.muteRequested()
            }
        }
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 3
        columnSpacing: 12
        rowSpacing: 12
AudioSlider {
                            id: sinkSlider
                            glyph: root.sinkMuted ? "󰝟" : "󰕾"
                            onMuteRequested: { if (root.sink?.audio) root.sink.audio.muted = !root.sink.audio.muted }
                            Layout.fillWidth: true
                            from: 0
                            to: 150
                            fillColor: root.sinkMuted ? Qt.rgba(1, 1, 1, 0.3) : Theme.popupText

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
AudioSlider {
                            id: sourceSlider
                            visible: !!root.source?.audio
                            glyph: root.sourceMuted ? "󰍭" : "󰍬"
                            onMuteRequested: { if (root.source?.audio) root.source.audio.muted = !root.source.audio.muted }
                            Layout.fillWidth: true
                            from: 0
                            to: 150
                            fillColor: root.sourceMuted ? Qt.rgba(1, 1, 1, 0.3) : Theme.popupText

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
        Repeater {
            model: root.streams
            Item {
                id: streamRow
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: 144
                implicitWidth: 64
                Layout.minimumWidth: 64
                Layout.preferredWidth: 64
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

AudioSlider {
                        id: streamSlider
                        anchors.fill: parent
                        appIcon: streamRow.modelData.icon || ""
                        glyph: streamRow.modelData.muted ? "󰝟" : "󰎆"
                        onMuteRequested: root.runStreamControl(["toggle-mute", "stream", String(streamRow.modelData.id)])
                        Layout.fillWidth: true
                        from: 0
                        to: 150
                        fillColor: streamRow.modelData.muted ? Qt.rgba(1, 1, 1, 0.3) : Theme.popupText

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
                                "set", "stream", String(streamRow.modelData.id), String(v)
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

    // ── Footer ──────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true

        Item { Layout.fillWidth: true }

        Item {
            id: mixerBtn
            implicitWidth: mixerRow.implicitWidth + 20
            implicitHeight: 30

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: mixerMouse.containsMouse ? "#30ffffff" : Theme.popupTile
                border.width: 1
                border.color: Theme.popupBorder
                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                Behavior on border.color { ColorAnimation { duration: Theme.animFast } }
            }

            scale: mixerMouse.pressed ? 0.96 : 1
            Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

            RowLayout {
                id: mixerRow
                anchors.centerIn: parent
                spacing: 6

                Text {
                    text: "󰒓"
                    color: Theme.popupText
                    font.family: Theme.iconFontFallback
                    font.pixelSize: 12
                }
                Text {
                    text: "Sound Settings"
                    color: Theme.popupMuted
                    font.pixelSize: 11
                    font.family: Theme.fontFamily
                }
            }

            MouseArea {
                id: mixerMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    Quickshell.execDetached(["pavucontrol"])
                    root.settingsOpened()
                }
            }
        }
    }
}
