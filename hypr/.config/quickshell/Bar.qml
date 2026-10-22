import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Services.Mpris

import "."
import "modules"

Item {
    id: root
    required property var modelData

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property real sinkVol: sink?.audio ? Math.round(sink.audio.volume * 100) : 0
    readonly property bool sinkMuted: sink?.audio?.muted ?? false

    readonly property var batt: UPower.displayDevice
    readonly property bool battReady: !!(batt && batt.ready && batt.isLaptopBattery)
    readonly property int battPct: battReady ? Math.round(batt.percentage) : -1
    readonly property bool battPlugged: battReady && (
        batt.state === UPowerDeviceState.Charging
        || batt.state === UPowerDeviceState.FullyCharged
        || batt.state === UPowerDeviceState.PendingCharge
    )

    readonly property var spotify: {
        const players = Mpris.players.values
        for (let i = 0; i < players.length; i++) {
            const p = players[i]
            const id = (p.desktopEntry || p.identity || "").toLowerCase()
            if (id.includes("spotify"))
                return p
        }
        return null
    }

    component BarText: Text {
        color: Theme.ink
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.weight: Font.Medium
        verticalAlignment: Text.AlignVCenter
    }

    component BarIcon: Text {
        id: barIcon
        color: Theme.secondary
        font.family: Theme.iconFontFallback
        font.pixelSize: 15
        verticalAlignment: Text.AlignVCenter
        opacity: iconHover.hovered ? 1 : 0.92

        Behavior on opacity {
            NumberAnimation { duration: Theme.animFast }
        }
        Behavior on color {
            ColorAnimation { duration: Theme.animFast }
        }

        HoverHandler { id: iconHover }
    }

    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }

    function popupMarginUnder(item: var, cardW: int): int {
        if (!item || root.width <= 0 || item.width <= 0)
            return 16
        const centerX = item.mapToItem(root, item.width / 2, 0).x
        return Globals.clampPopupMargin(
            Math.round(root.width - centerX - cardW / 2),
            cardW,
            root.width
        )
    }

    function syncPopupAnchors(): void {
        if (utilitiesHit.width > 0)
            Globals.volumePopupRightMargin = root.popupMarginUnder(utilitiesHit, 300)
        if (displayHit.width > 0)
            Globals.displayPopupRightMargin = root.popupMarginUnder(displayHit, 300)
        if (utilitiesHit.width > 0)
            Globals.utilitiesPopupRightMargin = root.popupMarginUnder(utilitiesHit, 300)
        if (powerBtn.width > 0)
            Globals.powerPopupRightMargin = root.popupMarginUnder(powerBtn, 300)
        if (towerHit.width > 0)
            Globals.towerPopupRightMargin = root.popupMarginUnder(towerHit, 320)
        // Toasts sit at content-strip right edge (same inset as 16:9 window).
        const inset = Math.max(0, Math.round((root.width - contentStrip.width) / 2))
        Globals.notifRightMargin = inset + 14
        mediaPill.syncMediaAnchor()
    }

    Item {
        anchors.fill: parent

        // Modules sit in centered 16:9 column (same math as hypr 16-9-lib).
        // Bar itself stays full monitor width.
        Item {
            id: contentStrip
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: Theme.barMargin
            anchors.bottomMargin: Theme.barMargin
            width: {
                // Match hypr 16-9-lib.sh: work area minus gaps_out, then h*16*1.08/9
                const screenW = root.modelData?.width || parent.width
                const screenH = root.modelData?.height || 1440
                const gap = 4 // general:gaps_out
                const workH = Math.max(1, screenH - Theme.barHeight - gap * 2)
                const sixteen = Math.round(workH * 16 * 108 / 9 / 100)
                return Math.min(screenW - gap * 2, sixteen)
            }

            onWidthChanged: Qt.callLater(root.syncPopupAnchors)
            Component.onCompleted: Qt.callLater(root.syncPopupAnchors)

            // Left: workspaces
            Workspaces {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
            }

            // Center: clock + media
            RowLayout {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                spacing: 6

            Pill {
                Layout.alignment: Qt.AlignVCenter
                pillColor: "transparent"
                hoverLift: false

                BarText {
                    id: clockLabel
                    color: Theme.tertiary
                    font.pixelSize: 13
                    font.weight: Font.Medium

                    Timer {
                        interval: 1000
                        running: true
                        repeat: true
                        triggeredOnStart: true
                        onTriggered: {
                            const d = new Date()
                            const days = ["sön", "mån", "tis", "ons", "tor", "fre", "lör"]
                            const months = ["jan", "feb", "mar", "apr", "maj", "jun", "jul", "aug", "sep", "okt", "nov", "dec"]
                            const pad = n => String(n).padStart(2, "0")
                            const tmp = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()))
                            tmp.setUTCDate(tmp.getUTCDate() + 4 - (tmp.getUTCDay() || 7))
                            const yearStart = new Date(Date.UTC(tmp.getUTCFullYear(), 0, 1))
                            const week = Math.ceil((((tmp - yearStart) / 86400000) + 1) / 7)
                            clockLabel.text = days[d.getDay()] + " " + pad(d.getDate()) + " " + months[d.getMonth()]
                                + "  W" + week
                                + "  " + pad(d.getHours()) + ":" + pad(d.getMinutes())
                        }
                    }
                }
            }

            Pill {
                id: mediaPill
                visible: root.spotify !== null && (root.spotify.trackTitle || "").length > 0
                Layout.alignment: Qt.AlignVCenter
                Layout.fillHeight: true
                pillHeight: Theme.barHeight
                pillColor: "transparent"
                hoverLift: false

                property int spotifyUiVol: 100
                property bool spotifyVolDrag: false
                property bool spotifySeekDrag: false
                readonly property bool showTimeline: mediaPill.hovered || mediaPill.spotifySeekDrag

                readonly property string spotifyVolumeScript: {
                    const home = Quickshell.env("HOME") || ""
                    return home + "/.config/hypr/scripts/spotify-volume"
                }

                function syncMediaAnchor(): void {
                    if (!visible || width <= 0 || root.width <= 0)
                        return
                    Globals.mediaPopupRightMargin = root.popupMarginUnder(mediaPill, 320)
                }

                function refreshSpotifyVol(): void {
                    if (mediaPill.spotifyVolDrag || mediaPill.spotifySeekDrag)
                        return
                    mediaSpotifyVolProc.running = true
                }

                function queueSpotifyVol(pct): void {
                    const v = Math.max(0, Math.min(100, Math.round(pct)))
                    mediaPill.spotifyUiVol = v
                    mediaVolCommit.restart()
                }

                function reapplySpotifyVol(): void {
                    Quickshell.execDetached([mediaPill.spotifyVolumeScript, "reapply"])
                }

                function fmtTime(secs: real): string {
                    const s = Math.max(0, Math.floor(secs))
                    return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
                }

                onVisibleChanged: {
                    Qt.callLater(root.syncPopupAnchors)
                    if (visible)
                        mediaPill.refreshSpotifyVol()
                }
                onWidthChanged: Qt.callLater(root.syncPopupAnchors)
                Component.onCompleted: {
                    Qt.callLater(root.syncPopupAnchors)
                    mediaPill.refreshSpotifyVol()
                }

                // MPRIS position does not emit continuously — tick while timeline shown + playing.
                FrameAnimation {
                    running: mediaPill.showTimeline && !!root.spotify?.isPlaying
                    onTriggered: root.spotify?.positionChanged()
                }

                Timer {
                    interval: 500
                    running: mediaPill.visible
                    repeat: true
                    triggeredOnStart: true
                    onTriggered: mediaPill.refreshSpotifyVol()
                }

                Timer {
                    id: mediaSeekReapply
                    interval: 120
                    onTriggered: mediaPill.reapplySpotifyVol()
                }

                Connections {
                    target: root
                    function onWidthChanged(): void { root.syncPopupAnchors() }
                }

                Process {
                    id: mediaSpotifyVolProc
                    command: [mediaPill.spotifyVolumeScript, "get"]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            const t = text.trim()
                            if (!t.length)
                                return
                            try {
                                const d = JSON.parse(t)
                                if (d.vol === undefined || d.vol === null)
                                    return
                                if (!mediaPill.spotifyVolDrag)
                                    mediaPill.spotifyUiVol = d.vol
                            } catch (e) {}
                        }
                    }
                }

                Timer {
                    id: mediaVolCommit
                    interval: 40
                    onTriggered: Quickshell.execDetached([
                        mediaPill.spotifyVolumeScript, "set", String(mediaPill.spotifyUiVol)
                    ])
                }

                Item {
                    id: mediaContent
                    Layout.fillHeight: true
                    implicitWidth: mediaRow.implicitWidth
                    implicitHeight: Theme.barHeight

                    RowLayout {
                        id: mediaRow
                        anchors.centerIn: parent
                        spacing: 6

                        Rectangle {
                            id: artThumb
                            Layout.preferredWidth: 20
                            Layout.preferredHeight: 20
                            Layout.alignment: Qt.AlignVCenter
                            radius: 5
                            color: Theme.surfaceContainer
                            z: 1

                            Image {
                                id: artThumbImg
                                anchors.fill: parent
                                source: root.spotify?.trackArtUrl || ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                visible: status === Image.Ready
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    maskEnabled: true
                                    maskSource: artThumbMask
                                }
                            }

                            Item {
                                id: artThumbMask
                                anchors.fill: parent
                                layer.enabled: true
                                visible: false

                                Rectangle {
                                    anchors.fill: parent
                                    radius: artThumb.radius
                                    color: "#ffffff"
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: !(root.spotify?.trackArtUrl) || artThumbImg.status !== Image.Ready
                                text: "󰝚"
                                color: Theme.tertiary
                                font.family: Theme.iconFontFallback
                                font.pixelSize: 12
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const home = Quickshell.env("HOME") || ""
                                    Quickshell.execDetached([
                                        home + "/.config/hypr/scripts/spotify-workspace", "15"
                                    ])
                                }
                            }
                        }

                        // Fixed slot: title idle, timeline on hover — same width, no layout jump.
                        Item {
                            id: mediaSwapSlot
                            Layout.preferredWidth: 180
                            Layout.preferredHeight: Theme.barHeight
                            Layout.alignment: Qt.AlignVCenter
                            clip: true

                            BarText {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                color: Theme.tertiary
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                opacity: mediaPill.showTimeline ? 0 : 1
                                text: {
                                    if (!root.spotify)
                                        return ""
                                    const artist = root.spotify.trackArtist || ""
                                    const title = root.spotify.trackTitle || ""
                                    return artist ? (artist + " — " + title) : title
                                }

                                Behavior on opacity {
                                    NumberAnimation { duration: Theme.animFast }
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                spacing: 8
                                opacity: mediaPill.showTimeline ? 1 : 0
                                enabled: mediaPill.showTimeline

                                Behavior on opacity {
                                    NumberAnimation { duration: Theme.animFast }
                                }

                                BarText {
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.preferredWidth: 30
                                    color: Theme.inkMuted
                                    font.pixelSize: 10
                                    horizontalAlignment: Text.AlignRight
                                    text: mediaPill.fmtTime(
                                        mediaSeekSlider.pressed
                                            ? mediaSeekSlider.value
                                            : (root.spotify?.position || 0)
                                    )
                                }

                                Slider {
                                    id: mediaSeekSlider
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 16
                                    Layout.alignment: Qt.AlignVCenter
                                    from: 0
                                    to: Math.max(1, root.spotify?.length || 1)
                                    live: true
                                    padding: 0
                                    topPadding: 4
                                    bottomPadding: 4

                                    Binding {
                                        target: mediaSeekSlider
                                        property: "value"
                                        value: root.spotify?.position || 0
                                        when: !mediaSeekSlider.pressed
                                        restoreMode: Binding.RestoreNone
                                    }

                                    background: Item {
                                        x: mediaSeekSlider.leftPadding
                                        y: mediaSeekSlider.topPadding + (mediaSeekSlider.availableHeight - height) / 2
                                        width: mediaSeekSlider.availableWidth
                                        height: 3

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 1.5
                                            color: Qt.rgba(1, 1, 1, 0.18)
                                        }
                                        Rectangle {
                                            width: mediaSeekSlider.visualPosition * parent.width
                                            height: parent.height
                                            radius: 1.5
                                            color: "#ffffff"
                                        }
                                    }

                                    handle: Rectangle {
                                        x: mediaSeekSlider.leftPadding + mediaSeekSlider.visualPosition * (mediaSeekSlider.availableWidth - width)
                                        y: mediaSeekSlider.topPadding + (mediaSeekSlider.availableHeight - height) / 2
                                        implicitWidth: 10
                                        implicitHeight: 10
                                        radius: 5
                                        color: "#ffffff"
                                    }

                                    onMoved: {
                                        if (root.spotify && pressed)
                                            root.spotify.position = value
                                    }
                                    onPressedChanged: {
                                        mediaPill.spotifySeekDrag = pressed
                                        // Seek in place — do not pause/play (Spotify blips stream volume).
                                        if (!pressed && root.spotify) {
                                            root.spotify.position = value
                                            // Spotify reapplies MPRIS volume onto the stream after seek.
                                            mediaSeekReapply.restart()
                                        }
                                    }
                                }

                                BarText {
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.preferredWidth: 30
                                    color: Theme.inkMuted
                                    font.pixelSize: 10
                                    text: mediaPill.fmtTime(root.spotify?.length || 0)
                                }
                            }
                        }

                        // Transport + volume — always shown
                        RowLayout {
                            id: mediaExtras
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 10

                            Item {
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                Layout.alignment: Qt.AlignVCenter

                                Rectangle {
                                    anchors.fill: parent
                                    radius: width / 2
                                    color: prevBtn.containsMouse ? "#000000" : "transparent"
                                    border.width: prevBtn.containsMouse ? 1 : 0
                                    border.color: Qt.rgba(1, 1, 1, 0.12)
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰒮"
                                    color: Theme.inkMuted
                                    font.family: Theme.iconFontFallback
                                    font.pixelSize: 18
                                }

                                MouseArea {
                                    id: prevBtn
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.spotify?.previous()
                                }
                            }

                            Item {
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                Layout.alignment: Qt.AlignVCenter

                                Rectangle {
                                    anchors.fill: parent
                                    radius: width / 2
                                    color: playBtn.containsMouse ? "#000000" : "transparent"
                                    border.width: playBtn.containsMouse ? 1 : 0
                                    border.color: Qt.rgba(1, 1, 1, 0.12)
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: root.spotify?.isPlaying ? "󰏤" : "󰐊"
                                    color: Theme.ink
                                    font.family: Theme.iconFontFallback
                                    font.pixelSize: 15
                                    anchors.horizontalCenterOffset: root.spotify?.isPlaying ? 0 : 0.5
                                }

                                MouseArea {
                                    id: playBtn
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.spotify?.togglePlaying()
                                }
                            }

                            Item {
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                Layout.alignment: Qt.AlignVCenter

                                Rectangle {
                                    anchors.fill: parent
                                    radius: width / 2
                                    color: nextBtn.containsMouse ? "#000000" : "transparent"
                                    border.width: nextBtn.containsMouse ? 1 : 0
                                    border.color: Qt.rgba(1, 1, 1, 0.12)
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰒭"
                                    color: Theme.inkMuted
                                    font.family: Theme.iconFontFallback
                                    font.pixelSize: 18
                                }

                                MouseArea {
                                    id: nextBtn
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.spotify?.next()
                                }
                            }

                            Slider {
                                id: mediaVolSlider
                                Layout.preferredWidth: 72
                                Layout.preferredHeight: 16
                                Layout.alignment: Qt.AlignVCenter
                                from: 0
                                to: 100
                                live: true
                                padding: 0
                                topPadding: 4
                                bottomPadding: 4
                                enabled: !mediaPill.spotifySeekDrag

                                Binding {
                                    target: mediaVolSlider
                                    property: "value"
                                    value: mediaPill.spotifyUiVol
                                    when: !mediaVolSlider.pressed
                                    restoreMode: Binding.RestoreNone
                                }

                                background: Item {
                                    x: mediaVolSlider.leftPadding
                                    y: mediaVolSlider.topPadding + (mediaVolSlider.availableHeight - height) / 2
                                    width: mediaVolSlider.availableWidth
                                    height: 3

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 1.5
                                        color: Qt.rgba(1, 1, 1, 0.18)
                                    }
                                    Rectangle {
                                        width: mediaVolSlider.visualPosition * parent.width
                                        height: parent.height
                                        radius: 1.5
                                        color: Theme.tertiary
                                    }
                                }

                                handle: Rectangle {
                                    x: mediaVolSlider.leftPadding + mediaVolSlider.visualPosition * (mediaVolSlider.availableWidth - width)
                                    y: mediaVolSlider.topPadding + (mediaVolSlider.availableHeight - height) / 2
                                    implicitWidth: 10
                                    implicitHeight: 10
                                    radius: 5
                                    color: "#ffffff"
                                }

                                onMoved: mediaPill.queueSpotifyVol(value)
                                onPressedChanged: {
                                    mediaPill.spotifyVolDrag = pressed
                                    if (!pressed) {
                                        mediaVolCommit.stop()
                                        Quickshell.execDetached([
                                            mediaPill.spotifyVolumeScript, "set", String(Math.round(value))
                                        ])
                                    }
                                }
                            }

                            BarText {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: 28
                                color: Theme.inkMuted
                                font.pixelSize: 10
                                horizontalAlignment: Text.AlignRight
                                text: Math.round(
                                    mediaVolSlider.pressed
                                        ? mediaVolSlider.value
                                        : mediaPill.spotifyUiVol
                                ) + "%"
                            }
                        }
                    }

                    // Click play-pause. Extras sit above this via z so their MouseAreas win.
                    MouseArea {
                        anchors.fill: parent
                        z: -1
                        hoverEnabled: false
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Quickshell.execDetached(["playerctl", "--player=spotify", "play-pause"])
                        }
                        onWheel: event => {
                            if (!root.sink || !root.sink.audio)
                                return
                            const step = 0.02
                            let v = root.sink.audio.volume + (event.angleDelta.y > 0 ? step : -step)
                            root.sink.audio.volume = Math.max(0, Math.min(1.5, v))
                        }
                    }
                }
            }
        }

        // Right cluster — data always visible; popups open on hover
        RowLayout {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            spacing: 4

            // OTP chip (armed … or last code)
            Pill {
                visible: otpChip.visible
                Layout.alignment: Qt.AlignVCenter
                pillColor: otpChip.cssClass === "high"
                    ? Qt.rgba(1, 0.3, 0.3, 0.22)
                    : otpChip.cssClass === "active"
                        ? Qt.rgba(1, 1, 1, 0.16)
                        : Theme.surfaceContainer

                JsonScript {
                    id: otpChip
                    scriptName: "otp-status.sh"
                    intervalMs: 400
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached([
                        Globals.scriptsDir + "/otp-watch.sh", "copy"
                    ])
                }
            }

            // System stats — always shown
            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                Layout.fillHeight: true
                spacing: 2

                // Display (brightness + night light) — before volume
                Item {
                    id: displayHit
                    Layout.fillHeight: true
                    Layout.preferredWidth: 36
                    implicitWidth: 36
                    onWidthChanged: Qt.callLater(root.syncPopupAnchors)

                    Rectangle {
                        anchors.centerIn: parent
                        width: 26
                        height: 26
                        radius: 13
                        color: displayMouse.containsMouse ? Theme.hover : "transparent"

                        Behavior on color {
                            ColorAnimation { duration: Theme.animFast }
                        }

                        BarIcon {
                            anchors.centerIn: parent
                            text: "󰛨"
                            color: displayMouse.containsMouse ? "#ffcc66" : Theme.secondary
                            font.pixelSize: 13
                        }
                    }

                    MouseArea {
                        id: displayMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: {
                            root.syncPopupAnchors()
                            Globals.setDisplayBarHover(true)
                        }
                        onExited: Globals.setDisplayBarHover(false)
                        onClicked: {
                            root.syncPopupAnchors()
                            Globals.setDisplayBarHover(true)
                        }
                    }
                }

                // Settings — NetBird, audio, OTP Watch
                Item {
                    id: utilitiesHit
                    Layout.fillHeight: true
                    Layout.preferredWidth: 36
                    implicitWidth: 36
                    onWidthChanged: Qt.callLater(root.syncPopupAnchors)

                    Rectangle {
                        anchors.centerIn: parent
                        width: 26
                        height: 26
                        radius: 13
                        color: utilitiesMouse.containsMouse ? Theme.hover : "transparent"

                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                        BarIcon {
                            anchors.centerIn: parent
                            text: "󰒓"
                            color: utilitiesMouse.containsMouse ? "#7dd3c0" : Theme.secondary
                            font.pixelSize: 13
                        }
                    }

                    MouseArea {
                        id: utilitiesMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: {
                            root.syncPopupAnchors()
                            Globals.setUtilitiesHover(true)
                        }
                        onExited: Globals.setUtilitiesHover(false)
                        onClicked: {
                            root.syncPopupAnchors()
                            Globals.toggleUtilities()
                        }
                    }
                }

                MouseBattery {
                    Layout.fillHeight: true
                }

                JsonScript {
                    scriptName: "cpu-usage.sh"
                    intervalMs: 3000
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Quickshell.execDetached(["xdg-terminal-exec", "btop"])
                    }
                }

                JsonScript {
                    scriptName: "gpu-usage.sh"
                    intervalMs: 3000
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Quickshell.execDetached(["xdg-terminal-exec", "btop"])
                    }
                }

                MacStat {
                    id: ramStat
                    label: "RAM"
                    value: "--"

                    Process {
                        id: ramProc
                        command: ["sh", "-c", "LC_ALL=C free -b | awk '/^Mem:/{printf \"%d %.1f %.1f\", ($2-$7)*100/$2, ($2-$7)/1073741824, $2/1073741824}'"]
                        stdout: StdioCollector {
                            onStreamFinished: {
                                const parts = text.trim().split(/\s+/).filter(p => p.length)
                                if (parts.length >= 3) {
                                    const pct = parseInt(parts[0])
                                    ramStat.value = pct + "%"
                                    ramStat.alert = pct > 90
                                    ramStat.tooltip = parts[1] + "G / " + parts[2] + "G used"
                                }
                            }
                        }
                    }

                    Timer {
                        interval: 5000
                        running: true
                        repeat: true
                        triggeredOnStart: true
                        onTriggered: ramProc.running = true
                    }
                }

                MacStat {
                    id: diskStat
                    label: "SSD"
                    value: "--"

                    Process {
                        id: diskProc
                        command: ["sh", "-c", "df -B1 / | awk 'NR==2{printf \"%d %s %s\", $5, $3, $2}'"]
                        stdout: StdioCollector {
                            onStreamFinished: {
                                const parts = text.trim().split(/\s+/)
                                if (parts.length >= 3) {
                                    const pct = parseInt(parts[0])
                                    diskStat.value = pct + "%"
                                    diskStat.alert = pct > 90
                                    const used = (parseFloat(parts[1]) / 1073741824).toFixed(1)
                                    const total = (parseFloat(parts[2]) / 1073741824).toFixed(1)
                                    diskStat.tooltip = used + "G / " + total + "G used on /"
                                }
                            }
                        }
                    }

                    Timer {
                        interval: 30000
                        running: true
                        repeat: true
                        triggeredOnStart: true
                        onTriggered: diskProc.running = true
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Quickshell.execDetached(["ghostty", "-e", "ncdu", "/"])
                    }
                }
            }

            Pill {
                visible: netMod.visible
                Layout.alignment: Qt.AlignVCenter

                JsonScript {
                    id: netMod
                    scriptName: "network-usage.sh"
                    continuous: true
                    intervalMs: 1000
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Quickshell.execDetached(["nm-connection-editor"])
                    }
                }
            }

            Pill {
                visible: root.battReady && !root.battPlugged
                Layout.alignment: Qt.AlignVCenter

                BarText {
                    text: {
                        if (!root.battReady)
                            return ""
                        const pct = root.battPct
                        const icons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
                        const idx = Math.min(icons.length - 1, Math.max(0, Math.floor(pct / 10)))
                        return icons[idx] + " " + pct + "%"
                    }
                    color: root.battPct >= 0 && root.battPct <= 10 ? Theme.error
                         : root.battPct <= 20 ? Theme.high : Theme.ink
                    font.family: Theme.iconFontFallback

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Quickshell.execDetached([Globals.sessionActionScript, "poweroff"])
                    }
                }
            }

            // Tower — next to power so clock/media cannot cover it
            Item {
                id: towerHit
                Layout.fillHeight: true
                Layout.minimumWidth: 44
                implicitWidth: Math.max(44, towerBar.implicitWidth + 8)
                Layout.preferredWidth: implicitWidth
                onWidthChanged: Qt.callLater(root.syncPopupAnchors)

                MacStat {
                    id: towerBar
                    anchors.centerIn: parent
                    Layout.fillHeight: false
                    label: "TOWER"
                    value: "···"
                    tooltip: "tower status"

                    Process {
                        id: towerBarProc
                        command: [Globals.scriptsDir + "/tower-status.sh"]
                        stdout: StdioCollector {
                            onStreamFinished: {
                                const t = text.trim()
                                if (!t.length)
                                    return
                                try {
                                    const d = JSON.parse(t)
                                    towerBar.value = d.ok && typeof d.ram_pct === "number" ? (d.ram_pct + "%") : "--"
                                    towerBar.tooltip = d.tooltip || "tower status"
                                    towerBar.alert = !!d.ok && typeof d.ram_pct === "number" && d.ram_pct > 90
                                } catch (e) {
                                    towerBar.value = "--"
                                    towerBar.tooltip = "tower parse error"
                                    towerBar.alert = false
                                }
                            }
                        }
                    }

                    Timer {
                        interval: 5000
                        running: true
                        repeat: true
                        triggeredOnStart: true
                        onTriggered: towerBarProc.running = true
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onEntered: {
                        root.syncPopupAnchors()
                        Globals.setTowerHover(true)
                    }
                    onExited: Globals.setTowerHover(false)
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) {
                            Quickshell.execDetached(["xdg-open", "https://netdata.hjacke.com"])
                            return
                        }
                        root.syncPopupAnchors()
                        Globals.toggleTower()
                    }
                }
            }

            // Full-bar-height hit target for power widget
            Item {
                id: powerBtn
                Layout.fillHeight: true
                Layout.preferredWidth: 32
                implicitWidth: 32
                onWidthChanged: Qt.callLater(root.syncPopupAnchors)

                Rectangle {
                    anchors.centerIn: parent
                    width: 26
                    height: 26
                    radius: 13
                    color: powerMouse.containsMouse ? Theme.hover : "transparent"

                    Behavior on color {
                        ColorAnimation { duration: Theme.animFast }
                    }

                    BarIcon {
                        anchors.centerIn: parent
                        text: "󰐥"
                        color: powerMouse.containsMouse ? "#ff8888" : Theme.error
                        font.pixelSize: 15
                    }
                }

                MouseArea {
                    id: powerMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: {
                        root.syncPopupAnchors()
                        Globals.setPowerHover(true)
                    }
                    onExited: Globals.setPowerHover(false)
                    onClicked: {
                        root.syncPopupAnchors()
                        Globals.setPowerHover(true)
                    }
                }
            }
        }
        }
    }
}
