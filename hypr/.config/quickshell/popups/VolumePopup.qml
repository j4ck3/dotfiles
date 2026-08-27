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

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource
    readonly property real sinkVol: sink?.audio ? sink.audio.volume * 100 : 0
    readonly property real sourceVol: source?.audio ? source.audio.volume * 100 : 0
    readonly property bool sinkMuted: sink?.audio?.muted ?? false
    readonly property bool sourceMuted: source?.audio?.muted ?? false
    readonly property int cardW: 262

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

    // Mute / action glyph — white icon, no chrome.
    component GlyphBtn: Item {
        id: gbtn
        property string icon: ""
        property bool active: false
        property bool soft: false
        signal clicked

        implicitWidth: 26
        implicitHeight: 26

        scale: mouse.pressed ? 0.92 : 1
        opacity: mouse.containsMouse ? 1 : 0.85
        Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }

        Text {
            anchors.centerIn: parent
            text: gbtn.icon
            color: "#ffffff"
            font.family: Theme.iconFontFallback
            font.pixelSize: 15
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: gbtn.clicked()
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
                if (!hovered && root.sliderDragging)
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
            color: "#0d0d0d"
            border.width: 1
            border.color: Theme.glassRim
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
                opacity: 0.7
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
                    GradientStop { position: 1.0; color: Theme.glassShade }
                }
            }
        }

        ColumnLayout {
            id: inner
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 16
            spacing: 12
            z: 1

            // ── Output ──────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    GlyphBtn {
                        icon: root.sinkMuted ? "󰝟" : (root.sinkVol >= 66 ? "󰕾" : root.sinkVol >= 1 ? "󰖀" : "󰕿")
                        active: !root.sinkMuted
                        onClicked: {
                            if (root.sink?.audio)
                                root.sink.audio.muted = !root.sink.audio.muted
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            M3Slider {
                                id: sinkSlider
                                Layout.fillWidth: true
                                from: 0
                                to: 150
                                tickMarks: [100]
                                fillColor: root.sinkMuted ? Qt.rgba(1, 1, 1, 0.3) : "#ffffff"
                                trackColor: Qt.rgba(1, 1, 1, 0.14)
                                trackHeight: 3
                                showHandle: true
                                handleSize: 10
                                hitPad: 6

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

                            Text {
                                text: Math.round(sinkSlider.pressed ? sinkSlider.value : root.sinkVol) + "%"
                                color: root.sinkMuted ? Qt.rgba(1, 1, 1, 0.32) : Qt.rgba(1, 1, 1, 0.7)
                                font.pixelSize: 11
                                font.weight: Font.Light
                                font.family: Theme.fontFamily
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: 34
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }
                }
            }

            // ── Mic ─────────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: root.source && root.source.audio

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    GlyphBtn {
                        icon: root.sourceMuted ? "󰍭" : "󰍬"
                        active: !root.sourceMuted
                        onClicked: {
                            if (root.source?.audio)
                                root.source.audio.muted = !root.source.audio.muted
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            M3Slider {
                                id: sourceSlider
                                Layout.fillWidth: true
                                from: 0
                                to: 150
                                tickMarks: [100]
                                fillColor: root.sourceMuted ? Qt.rgba(1, 1, 1, 0.3) : "#ffffff"
                                trackColor: Qt.rgba(1, 1, 1, 0.14)
                                trackHeight: 3
                                showHandle: true
                                handleSize: 10
                                hitPad: 6

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

                            Text {
                                text: Math.round(sourceSlider.pressed ? sourceSlider.value : root.sourceVol) + "%"
                                color: root.sourceMuted ? Qt.rgba(1, 1, 1, 0.32) : Qt.rgba(1, 1, 1, 0.7)
                                font.pixelSize: 11
                                font.weight: Font.Light
                                font.family: Theme.fontFamily
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: 34
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }
                }
            }

            // ── Apps ────────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: root.streams.length > 0

                Repeater {
                    model: root.streams

                    RowLayout {
                        id: streamRow
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 8

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

                        GlyphBtn {
                            icon: modelData.muted ? "󰝟" : "󰎆"
                            soft: true
                            onClicked: root.runStreamControl(["toggle-mute", "stream", String(modelData.id)])
                        }

                        Text {
                            text: modelData.name || modelData.title || "App"
                            color: Qt.rgba(1, 1, 1, 0.7)
                            font.pixelSize: 11
                            font.family: Theme.fontFamily
                            elide: Text.ElideRight
                            Layout.preferredWidth: 58
                            Layout.maximumWidth: 70
                        }

                        M3Slider {
                            id: streamSlider
                            Layout.fillWidth: true
                            from: 0
                            to: 150
                            tickMarks: [100]
                            fillColor: modelData.muted ? Qt.rgba(1, 1, 1, 0.3) : "#ffffff"
                            trackColor: Qt.rgba(1, 1, 1, 0.14)
                            trackHeight: 3
                            showHandle: true
                            handleSize: 10
                            hitPad: 5

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

                        Text {
                            text: Math.round(streamSlider.pressed ? streamSlider.value : streamRow.uiPercent) + "%"
                            color: Qt.rgba(1, 1, 1, 0.45)
                            font.pixelSize: 11
                            font.family: Theme.fontFamily
                            horizontalAlignment: Text.AlignRight
                            Layout.preferredWidth: 30
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
                    implicitHeight: 28

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: mixerMouse.containsMouse ? Theme.glassFillHover : Theme.glassFill
                        border.width: 1
                        border.color: mixerMouse.containsMouse ? Theme.glassRimHover : Theme.glassRim
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
                            color: Qt.rgba(1, 1, 1, 0.75)
                            font.family: Theme.iconFontFallback
                            font.pixelSize: 12
                        }
                        Text {
                            text: "Sound Settings"
                            color: Qt.rgba(1, 1, 1, 0.7)
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
                            Globals.volumeOpen = false
                        }
                    }
                }
            }
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
