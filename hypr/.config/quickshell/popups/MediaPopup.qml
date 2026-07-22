import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import ".."

PanelWindow {
    id: root
    visible: Globals.mediaOpen
    color: "transparent"
    exclusiveZone: 0

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    WlrLayershell.namespace: "qs-media"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

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

    function fmt(secs: real): string {
        const s = Math.max(0, Math.floor(secs))
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }

    HyprlandFocusGrab {
        active: root.visible
        windows: [root]
        onCleared: Globals.mediaOpen = false
    }

    MouseArea {
        anchors.fill: parent
        onClicked: Globals.mediaOpen = false
    }

    PopupCard {
        anchors.fill: parent
        title: "Now Playing"
        cardWidth: 320
        onClosed: Globals.mediaOpen = false

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 280
            radius: 18
            color: Theme.surfaceContainer
            clip: true

            Image {
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                source: root.player?.trackArtUrl || ""
                visible: status === Image.Ready
            }

            Rectangle {
                anchors.fill: parent
                visible: !(root.player?.trackArtUrl)
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

        M3Slider {
            Layout.fillWidth: true
            from: 0
            to: Math.max(1, root.player?.length || 1)
            value: root.player?.position || 0
            fillColor: Theme.tertiary
            onMoved: {
                if (root.player)
                    root.player.position = value
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: root.fmt(root.player?.position || 0)
                color: Theme.inkMuted
                font.pixelSize: 11
                Layout.fillWidth: true
            }
            Text {
                text: "-" + root.fmt(Math.max(0, (root.player?.length || 0) - (root.player?.position || 0)))
                color: Theme.inkMuted
                font.pixelSize: 11
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 14

            M3IconButton {
                icon: "󰒮"
                onClicked: root.player?.previous()
            }

            M3IconButton {
                icon: root.player?.isPlaying ? "󰏤" : "󰐊"
                active: true
                onClicked: root.player?.togglePlaying()
            }

            M3IconButton {
                icon: "󰒭"
                onClicked: root.player?.next()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "󰕿"
                color: Theme.inkMuted
                font.family: Theme.iconFontFallback
            }

            M3Slider {
                Layout.fillWidth: true
                from: 0
                to: 1
                value: root.player?.volume ?? 0.5
                fillColor: Theme.secondary
                onMoved: {
                    if (root.player)
                        root.player.volume = value
                }
            }

            Text {
                text: "󰕾"
                color: Theme.inkMuted
                font.family: Theme.iconFontFallback
            }
        }
    }
}
