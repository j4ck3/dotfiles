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
        top: Theme.popupTopInset
        left: Theme.popupLeftInset
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

    property bool seekDragging: false

    function fmt(secs: real): string {
        const s = Math.max(0, Math.floor(secs))
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }

    Timer {
        id: reapplyDelay
        interval: 120
        onTriggered: Quickshell.execDetached([root.spotifyVolumeScript, "reapply"])
    }

    // Mpris position does not emit continuously — tick it while popup open + playing.
    FrameAnimation {
        running: root.visible && !!root.player?.isPlaying
        onTriggered: root.player?.positionChanged()
    }

    onVisibleChanged: {
        if (visible) {
            root.player?.positionChanged()
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
        topMargin: Theme.barVertical ? Globals.mediaPopupTopMargin : Theme.widgetTopGap
        rightMargin: Globals.mediaPopupRightMargin
        animateIn: true
        onClosed: Globals.mediaOpen = false
        onCardHover: inside => Globals.setMediaHover(inside)

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
            id: seekRow
            Layout.fillWidth: true
            spacing: 10

            property real hoverTime: -1

            Text {
                text: root.fmt(
                    seekSlider.pressed ? seekSlider.value
                        : (seekRow.hoverTime >= 0 ? seekRow.hoverTime : (root.player?.position || 0))
                )
                color: seekRow.hoverTime >= 0 && !seekSlider.pressed ? Theme.ink : Theme.inkMuted
                font.pixelSize: 11
                font.family: Theme.fontFamily
                Layout.alignment: Qt.AlignVCenter

                Behavior on color { ColorAnimation { duration: Theme.animFast } }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: seekSlider.implicitHeight

                M3Slider {
                    id: seekSlider
                    anchors.fill: parent
                    from: 0
                    to: Math.max(1, root.player?.length || 1)
                    fillColor: "#ffffff"
                    trackColor: Qt.rgba(1, 1, 1, 0.18)
                    trackHeight: 6
                    showHandle: false
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
                        if (!pressed && root.player) {
                            root.player.position = value
                            reapplyDelay.restart()
                        }
                    }

                    onMoved: {
                        if (root.player && pressed)
                            root.player.position = value
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    z: 1

                    onContainsMouseChanged: {
                        if (!containsMouse)
                            seekRow.hoverTime = -1
                    }

                    onPositionChanged: {
                        if (!containsMouse)
                            return
                        const trackX = seekSlider.leftPadding
                        const trackW = seekSlider.availableWidth
                        if (trackW <= 0)
                            return
                        const ratio = Math.max(0, Math.min(1, (mouse.x - trackX) / trackW))
                        seekRow.hoverTime = seekSlider.from + ratio * (seekSlider.to - seekSlider.from)
                    }
                }

                Text {
                    visible: seekRow.hoverTime >= 0 && !seekSlider.pressed
                    text: root.fmt(seekRow.hoverTime)
                    color: Theme.ink
                    font.pixelSize: 10
                    font.family: Theme.fontFamily
                    z: 2

                    readonly property real trackX: seekSlider.leftPadding
                    readonly property real trackW: seekSlider.availableWidth
                    readonly property real ratio: trackW > 0
                        ? Math.max(0, Math.min(1, (seekRow.hoverTime - seekSlider.from) / (seekSlider.to - seekSlider.from)))
                        : 0

                    x: trackX + ratio * trackW - implicitWidth / 2
                    y: -implicitHeight - 4
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
    }
}
