import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import ".."

PanelWindow {
    id: root
    visible: Globals.volumeOpen
    color: "transparent"
    exclusiveZone: 0

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    WlrLayershell.namespace: "qs-volume"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    property var audio: ({ sink: null, source: null, streams: [] })

    function refresh(): void {
        dataProc.running = true
    }

    function runControl(args: var): void {
        Quickshell.execDetached([Globals.scriptsDir + "/volume-popup-control.sh"].concat(args))
        refreshTimer.restart()
    }

    HyprlandFocusGrab {
        active: root.visible
        windows: [root]
        onCleared: Globals.volumeOpen = false
    }

    Process {
        id: dataProc
        command: [Globals.scriptsDir + "/volume-popup-data.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.audio = JSON.parse(text.trim())
                } catch (e) {
                    root.audio = ({ sink: null, source: null, streams: [] })
                }
            }
        }
    }

    Timer {
        id: refreshTimer
        interval: 200
        onTriggered: root.refresh()
    }

    Timer {
        interval: 1000
        running: root.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    MouseArea {
        anchors.fill: parent
        onClicked: Globals.volumeOpen = false
    }

    PopupCard {
        anchors.fill: parent
        title: "Volume"
        cardWidth: 360
        onClosed: Globals.volumeOpen = false

        M3Section {
            title: "OUTPUT"
            visible: root.audio.sink !== null

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                M3IconButton {
                    icon: root.audio.sink?.muted ? "󰝟" : "󰕾"
                    active: !(root.audio.sink?.muted ?? false)
                    onClicked: root.runControl(["toggle-mute", "sink", String(root.audio.sink.id)])
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: root.audio.sink?.description || "Output"
                        color: "#ffffff"
                        font.pixelSize: 13
                        font.family: Theme.fontFamily
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        text: (root.audio.sink?.percent ?? 0) + "%"
                        color: Qt.rgba(1, 1, 1, 0.55)
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }
            }

            M3Slider {
                Layout.fillWidth: true
                from: 0
                to: 150
                value: root.audio.sink?.percent ?? 0
                onMoved: root.runControl(["set", "sink", String(root.audio.sink.id), String(Math.round(value))])
            }
        }

        M3Section {
            title: "MICROPHONE"
            visible: root.audio.source !== null

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                M3IconButton {
                    icon: root.audio.source?.muted ? "󰍭" : "󰍬"
                    active: !(root.audio.source?.muted ?? false)
                    onClicked: root.runControl(["toggle-mute", "source", String(root.audio.source.id)])
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: root.audio.source?.description || "Microphone"
                        color: "#ffffff"
                        font.pixelSize: 13
                        font.family: Theme.fontFamily
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        text: (root.audio.source?.percent ?? 0) + "%"
                        color: Qt.rgba(1, 1, 1, 0.55)
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }
            }

            M3Slider {
                Layout.fillWidth: true
                from: 0
                to: 150
                value: root.audio.source?.percent ?? 0
                onMoved: root.runControl(["set", "source", String(root.audio.source.id), String(Math.round(value))])
            }
        }

        M3Section {
            title: "APPS"
            visible: (root.audio.streams || []).length > 0

            Repeater {
                model: root.audio.streams || []

                ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        M3IconButton {
                            icon: modelData.muted ? "󰝟" : "󰎆"
                            onClicked: root.runControl(["toggle-mute", "stream", String(modelData.id)])
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
                            text: modelData.percent + "%"
                            color: Qt.rgba(1, 1, 1, 0.5)
                            font.pixelSize: 11
                        }
                    }

                    M3Slider {
                        Layout.fillWidth: true
                        from: 0
                        to: 150
                        value: modelData.percent
                        onMoved: root.runControl(["set", "stream", String(modelData.id), String(Math.round(value))])
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
