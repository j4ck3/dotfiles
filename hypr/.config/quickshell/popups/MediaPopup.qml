import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris
import ".."

PanelWindow {
    id: root
    visible: Globals.mediaOpen
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

    WlrLayershell.namespace: "qs-media"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    readonly property var player: {
        const players = Mpris.players.values
        for (let i = 0; i < players.length; i++) {
            const p = players[i]
            const id = (p.desktopEntry || p.identity || "").toLowerCase()
            if (id.includes("spotify"))
                return p
        }
        return players.length ? players[0] : null
    }

    readonly property string spotifyVolumeScript: {
        const home = Quickshell.env("HOME") || ""
        return home + "/.config/hypr/scripts/spotify-volume"
    }

    // PipeWire stream volume (what you actually hear). MPRIS fights the guard.
    property int spotifyStreamVol: -1
    property int uiVol: 100
    property bool volHold: false
    property bool volDragging: false
    property bool seekDragging: false

    function fmt(secs: real): string {
        const s = Math.max(0, Math.floor(secs))
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }

    function refreshSpotifyVol(): void {
        if (root.volDragging || root.volHold || root.seekDragging)
            return
        spotifyVolProc.running = true
    }

    function queueSpotifyVol(pct): void {
        const v = Math.max(0, Math.min(100, Math.round(pct)))
        root.uiVol = v
        root.volHold = true
        volHoldTimer.restart()
        volCommitTimer.restart()
    }

    function commitSpotifyVol(): void {
        Quickshell.execDetached([root.spotifyVolumeScript, "set", String(root.uiVol)])
    }

    function reapplySpotifyVol(): void {
        // After seek Spotify copies MPRIS→stream; force our intended level back.
        Quickshell.execDetached([root.spotifyVolumeScript, "reapply"])
    }

    Timer {
        id: reapplyDelay
        interval: 120
        onTriggered: root.reapplySpotifyVol()
    }

    function scheduleReapply(): void {
        reapplyDelay.restart()
    }

    Process {
        id: spotifyVolProc
        command: [root.spotifyVolumeScript, "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim()
                if (!t.length)
                    return
                try {
                    const d = JSON.parse(t)
                    if (d.vol === undefined || d.vol === null)
                        return
                    root.spotifyStreamVol = d.vol
                    if (!root.volDragging && !root.volHold)
                        root.uiVol = d.vol
                } catch (e) {}
            }
        }
    }

    Timer {
        id: volCommitTimer
        interval: 40
        onTriggered: root.commitSpotifyVol()
    }

    Timer {
        id: volHoldTimer
        interval: 900
        onTriggered: {
            root.volHold = false
            root.refreshSpotifyVol()
        }
    }

    Timer {
        interval: 500
        running: root.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshSpotifyVol()
    }

    // Mpris position does not emit continuously — tick it while popup open + playing.
    FrameAnimation {
        running: root.visible && !!root.player?.isPlaying
        onTriggered: root.player?.positionChanged()
    }

    onVisibleChanged: {
        if (visible) {
            root.player?.positionChanged()
            root.refreshSpotifyVol()
            card.playIn()
        } else {
            card.resetOut()
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: Globals.mediaOpen = false
    }

    PopupCard {
        id: card
        anchors.fill: parent
        title: "Now Playing"
        cardWidth: 320
        topMargin: Theme.widgetTopGap
        rightMargin: Globals.mediaPopupRightMargin
        animateIn: true
        onClosed: Globals.mediaOpen = false
        onCardHover: inside => Globals.setMediaHover(inside)

        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            spacing: 4

            Item { Layout.fillWidth: true }

            // Previous
            Item {
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40

                Text {
                    anchors.centerIn: parent
                    text: "󰒮"
                    color: prevMouse.containsMouse ? Theme.ink : Theme.inkMuted
                    font.family: Theme.iconFontFallback
                    font.pixelSize: 22
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                }

                MouseArea {
                    id: prevMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.player?.previous()
                        root.scheduleReapply()
                    }
                }
            }

            // Play / pause
            Rectangle {
                Layout.preferredWidth: 44
                Layout.preferredHeight: 44
                radius: 22
                color: playMouse.containsMouse ? "#f0f0f0" : "#ffffff"
                scale: playMouse.pressed ? 0.94 : 1

                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                Behavior on scale {
                    NumberAnimation { duration: 80; easing.type: Easing.OutCubic }
                }

                Text {
                    anchors.centerIn: parent
                    text: root.player?.isPlaying ? "󰏤" : "󰐊"
                    color: "#000000"
                    font.family: Theme.iconFontFallback
                    font.pixelSize: 20
                    // Play glyph sits optically left; nudge when paused
                    anchors.horizontalCenterOffset: root.player?.isPlaying ? 0 : 1
                }

                MouseArea {
                    id: playMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.player?.togglePlaying()
                }
            }

            // Next
            Item {
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40

                Text {
                    anchors.centerIn: parent
                    text: "󰒭"
                    color: nextMouse.containsMouse ? Theme.ink : Theme.inkMuted
                    font.family: Theme.iconFontFallback
                    font.pixelSize: 22
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                }

                MouseArea {
                    id: nextMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.player?.next()
                        root.scheduleReapply()
                    }
                }
            }

            Item { Layout.fillWidth: true }
        }

        Rectangle {
            id: artBox
            Layout.fillWidth: true
            Layout.preferredHeight: 280
            radius: 18
            color: Theme.surfaceContainer

            Image {
                id: artImg
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                source: root.player?.trackArtUrl || ""
                visible: status === Image.Ready
                asynchronous: true
                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: artMask
                }
            }

            Item {
                id: artMask
                anchors.fill: parent
                layer.enabled: true
                visible: false

                Rectangle {
                    anchors.fill: parent
                    radius: artBox.radius
                    color: "#ffffff"
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: artBox.radius
                visible: !(root.player?.trackArtUrl) || artImg.status !== Image.Ready
                color: Theme.surfaceContainerHigh

                Text {
                    anchors.centerIn: parent
                    text: "󰝚"
                    color: Theme.tertiary
                    font.family: Theme.iconFontFallback
                    font.pixelSize: 48
                }
            }
        }

        Text {
            text: root.player?.trackTitle || "Nothing Playing"
            color: Theme.ink
            font.pixelSize: 16
            font.weight: Font.DemiBold
            font.family: Theme.fontFamily
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        Text {
            text: root.player?.trackArtist || ""
            color: Theme.inkMuted
            font.pixelSize: 13
            Layout.fillWidth: true
            elide: Text.ElideRight
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Text {
                text: root.fmt(seekSlider.pressed ? seekSlider.value : (root.player?.position || 0))
                color: Theme.inkMuted
                font.pixelSize: 11
                font.family: Theme.fontFamily
                Layout.alignment: Qt.AlignVCenter
            }

            M3Slider {
                id: seekSlider
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                from: 0
                to: Math.max(1, root.player?.length || 1)
                fillColor: "#ffffff"
                trackColor: Qt.rgba(1, 1, 1, 0.18)
                trackHeight: 6
                showHandle: false
                // Keep seek hitbox from eating the volume row under it.
                hitPad: 6

                Binding {
                    target: seekSlider
                    property: "value"
                    value: root.player?.position || 0
                    when: !seekSlider.pressed
                    restoreMode: Binding.RestoreNone
                }

                onPressedChanged: {
                    root.seekDragging = pressed
                    // Seek in place — do not pause/play (Spotify blips stream volume).
                    if (!pressed && root.player) {
                        root.player.position = value
                        // Spotify reapplies MPRIS volume onto the stream after seek.
                        root.scheduleReapply()
                    }
                }

                onMoved: {
                    if (root.player && pressed)
                        root.player.position = value
                }
            }

            Text {
                text: root.fmt(root.player?.length || 0)
                color: Theme.inkMuted
                font.pixelSize: 11
                font.family: Theme.fontFamily
                Layout.alignment: Qt.AlignVCenter
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: root.spotifyStreamVol >= 0

            Item { Layout.fillWidth: true }

            M3Slider {
                id: volSlider
                Layout.preferredWidth: 120
                Layout.alignment: Qt.AlignVCenter
                from: 0
                to: 100
                fillColor: "#ffffff"
                trackColor: Qt.rgba(1, 1, 1, 0.18)
                trackHeight: 4
                showHandle: true
                enabled: !root.seekDragging

                Binding {
                    target: volSlider
                    property: "value"
                    value: root.uiVol
                    when: !volSlider.pressed
                    restoreMode: Binding.RestoreNone
                }

                onMoved: {
                    if (root.seekDragging)
                        return
                    root.queueSpotifyVol(value)
                }
                onPressedChanged: {
                    root.volDragging = pressed
                    if (!pressed) {
                        volCommitTimer.stop()
                        root.commitSpotifyVol()
                        root.volHold = true
                        volHoldTimer.restart()
                    }
                }
            }

            Text {
                text: Math.round(volSlider.pressed ? volSlider.value : root.uiVol) + "%"
                color: Theme.inkMuted
                font.pixelSize: 11
                font.family: Theme.fontFamily
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: 32
            }
        }
    }
}
