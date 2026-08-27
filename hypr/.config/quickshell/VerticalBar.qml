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

// Left-edge vertical strip — same modules as Bar, stacked top → bottom.
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
        horizontalAlignment: Text.AlignHCenter
    }

    component BarIcon: Text {
        color: Theme.secondary
        font.family: Theme.iconFontFallback
        font.pixelSize: 15
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }

    function syncMediaAnchor(): void {
        if (!mediaCol.visible || artThumb.height <= 0) {
            Globals.mediaPopupTopMargin = Theme.widgetTopGap
            Globals.mediaPopupRightMargin = Theme.widgetTopGap
            return
        }
        const topY = artThumb.mapToItem(root, 0, 0).y
        Globals.mediaPopupTopMargin = Math.round(topY)
        Globals.mediaPopupRightMargin = Theme.widgetTopGap
    }

    function syncPopupAnchors(): void {
        // Cards sit just past left bar (reuse *RightMargin as edge gap).
        Globals.volumePopupRightMargin = Theme.widgetTopGap
        Globals.powerPopupRightMargin = Theme.widgetTopGap
        Globals.towerPopupRightMargin = Theme.widgetTopGap
        Globals.notifRightMargin = 14
        syncMediaAnchor()
    }

    Component.onCompleted: Qt.callLater(root.syncPopupAnchors)
    onWidthChanged: Qt.callLater(root.syncPopupAnchors)

    // Absolute regions: top workspaces / true-center clock / bottom stats.
    Workspaces {
        id: wsStrip
        vertical: true
        anchors.top: parent.top
        anchors.topMargin: 8
        anchors.horizontalCenter: parent.horizontalCenter
    }

    // Clock — true vertical center of bar (like top-bar center cluster).
    Column {
        id: clockCol
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        BarText {
            id: clockDay
            anchors.horizontalCenter: parent.horizontalCenter
            color: Theme.inkMuted
            font.pixelSize: 13
            font.weight: Font.Medium
        }
        BarText {
            id: clockDate
            anchors.horizontalCenter: parent.horizontalCenter
            color: Theme.inkMuted
            font.pixelSize: 13
            font.weight: Font.Medium
        }
        BarText {
            id: clockWeek
            anchors.horizontalCenter: parent.horizontalCenter
            color: Theme.inkMuted
            font.pixelSize: 13
            font.weight: Font.Medium
        }
        BarText {
            id: clockTime
            anchors.horizontalCenter: parent.horizontalCenter
            color: Theme.inkMuted
            font.pixelSize: 13
            font.weight: Font.Medium
        }

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
                clockDay.text = days[d.getDay()]
                clockDate.text = pad(d.getDate()) + " " + months[d.getMonth()]
                clockWeek.text = "W" + week
                clockTime.text = pad(d.getHours()) + ":" + pad(d.getMinutes())
            }
        }
    }

    // Media hangs under clock
    Column {
        id: mediaCol
        visible: root.spotify !== null && (root.spotify.trackTitle || "").length > 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: clockCol.bottom
        anchors.topMargin: 8
        spacing: 6

        property int spotifyUiVol: 100
        property bool spotifyVolDrag: false
        readonly property string spotifyVolumeScript: {
            const home = Quickshell.env("HOME") || ""
            return home + "/.config/hypr/scripts/spotify-volume"
        }

        function refreshSpotifyVol(): void {
            if (mediaCol.spotifyVolDrag)
                return
            mediaSpotifyVolProc.running = true
        }

        function queueSpotifyVol(pct): void {
            const v = Math.max(0, Math.min(100, Math.round(pct)))
            mediaCol.spotifyUiVol = v
            mediaVolCommit.restart()
        }

        onVisibleChanged: {
            Qt.callLater(root.syncMediaAnchor)
            if (visible)
                mediaCol.refreshSpotifyVol()
        }
        Component.onCompleted: {
            Qt.callLater(root.syncMediaAnchor)
            mediaCol.refreshSpotifyVol()
        }

        Timer {
            interval: 500
            running: mediaCol.visible
            repeat: true
            triggeredOnStart: true
            onTriggered: mediaCol.refreshSpotifyVol()
        }

        Process {
            id: mediaSpotifyVolProc
            command: [mediaCol.spotifyVolumeScript, "get"]
            stdout: StdioCollector {
                onStreamFinished: {
                    const t = text.trim()
                    if (!t.length)
                        return
                    try {
                        const d = JSON.parse(t)
                        if (d.vol === undefined || d.vol === null)
                            return
                        if (!mediaCol.spotifyVolDrag)
                            mediaCol.spotifyUiVol = d.vol
                    } catch (e) {}
                }
            }
        }

        Timer {
            id: mediaVolCommit
            interval: 40
            onTriggered: Quickshell.execDetached([
                mediaCol.spotifyVolumeScript, "set", String(mediaCol.spotifyUiVol)
            ])
        }

        Rectangle {
            id: artThumb
            anchors.horizontalCenter: parent.horizontalCenter
            width: 28
            height: 28
            radius: 6
            color: Theme.surfaceContainer

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
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: {
                    root.syncPopupAnchors()
                    Globals.setMediaHover(true)
                }
                onExited: Globals.setMediaHover(false)
                onClicked: {
                    const home = Quickshell.env("HOME") || ""
                    Quickshell.execDetached([
                        home + "/.config/hypr/scripts/spotify-workspace", "15"
                    ])
                }
            }
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 2

            Repeater {
                model: [
                    { icon: "󰒮", action: "prev" },
                    { icon: root.spotify?.isPlaying ? "󰏤" : "󰐊", action: "play" },
                    { icon: "󰒭", action: "next" }
                ]

                Item {
                    required property var modelData
                    width: 28
                    height: 28

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: btnMouse.containsMouse ? "#000000" : "transparent"
                        border.width: btnMouse.containsMouse ? 1 : 0
                        border.color: Qt.rgba(1, 1, 1, 0.12)
                    }

                    Text {
                        anchors.centerIn: parent
                        text: modelData.action === "play"
                            ? (root.spotify?.isPlaying ? "󰏤" : "󰐊")
                            : modelData.icon
                        color: modelData.action === "play" ? Theme.ink : Theme.inkMuted
                        font.family: Theme.iconFontFallback
                        font.pixelSize: modelData.action === "play" ? 14 : 16
                    }

                    MouseArea {
                        id: btnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (modelData.action === "prev")
                                root.spotify?.previous()
                            else if (modelData.action === "next")
                                root.spotify?.next()
                            else
                                root.spotify?.togglePlaying()
                        }
                    }
                }
            }
        }

        // Always-on vertical Spotify volume (same script as top bar).
        Slider {
            id: mediaVolSlider
            anchors.horizontalCenter: parent.horizontalCenter
            orientation: Qt.Vertical
            from: 0
            to: 100
            live: true
            padding: 0
            leftPadding: 6
            rightPadding: 6
            implicitWidth: 20
            implicitHeight: 120

            Binding {
                target: mediaVolSlider
                property: "value"
                value: mediaCol.spotifyUiVol
                when: !mediaVolSlider.pressed
                restoreMode: Binding.RestoreNone
            }

            // Vertical: visualPosition 0 = top (min), 1 = bottom (max) in QQC2.
            background: Item {
                x: mediaVolSlider.leftPadding + (mediaVolSlider.availableWidth - width) / 2
                y: mediaVolSlider.topPadding
                width: 3
                height: mediaVolSlider.availableHeight

                Rectangle {
                    anchors.fill: parent
                    radius: 1.5
                    color: Qt.rgba(1, 1, 1, 0.18)
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: (1 - mediaVolSlider.visualPosition) * parent.height
                    radius: 1.5
                    color: Theme.tertiary
                }
            }

            handle: Rectangle {
                x: mediaVolSlider.leftPadding + (mediaVolSlider.availableWidth - width) / 2
                y: mediaVolSlider.topPadding
                    + mediaVolSlider.visualPosition * (mediaVolSlider.availableHeight - height)
                implicitWidth: 10
                implicitHeight: 10
                radius: 5
                color: "#ffffff"
            }

            onMoved: mediaCol.queueSpotifyVol(value)
            onPressedChanged: {
                mediaCol.spotifyVolDrag = pressed
                if (!pressed) {
                    mediaVolCommit.stop()
                    Quickshell.execDetached([
                        mediaCol.spotifyVolumeScript, "set", String(Math.round(value))
                    ])
                }
            }
        }

        BarText {
            anchors.horizontalCenter: parent.horizontalCenter
            color: Theme.inkMuted
            font.pixelSize: 10
            text: Math.round(
                mediaVolSlider.pressed ? mediaVolSlider.value : mediaCol.spotifyUiVol
            ) + "%"
        }
    }

    // Bottom cluster: stats + tower at bottom (tower sits just above power)
    ColumnLayout {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 4

            Pill {
                visible: otpChip.visible
                Layout.alignment: Qt.AlignHCenter
                pillHeight: 28
                hPad: 4
                pillColor: otpChip.cssClass === "high"
                    ? Qt.rgba(1, 0.3, 0.3, 0.22)
                    : otpChip.cssClass === "active"
                        ? Qt.rgba(1, 1, 1, 0.16)
                        : Theme.surfaceContainer

                Item {
                    implicitWidth: otpChip.implicitWidth
                    implicitHeight: otpChip.implicitHeight

                    JsonScript {
                        id: otpChip
                        anchors.fill: parent
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
            }

            Item {
                id: volHit
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: volStat.implicitWidth
                Layout.preferredHeight: volStat.implicitHeight
                implicitWidth: volStat.implicitWidth
                implicitHeight: volStat.implicitHeight

                MacStat {
                    id: volStat
                    anchors.centerIn: parent
                    Layout.fillHeight: false
                    label: "VOL"
                    value: root.sinkMuted ? "MUT" : (root.sinkVol + "%")
                    muted: root.sinkMuted
                    tooltip: "Output at " + root.sinkVol + "%"
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onEntered: {
                        root.syncPopupAnchors()
                        Globals.setVolumeHover(true)
                    }
                    onExited: Globals.setVolumeHover(false)
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton)
                            Quickshell.execDetached(["pavucontrol"])
                        else {
                            root.syncPopupAnchors()
                            Globals.setVolumeHover(true)
                        }
                    }
                    onWheel: event => {
                        if (!root.sink || !root.sink.audio)
                            return
                        const step = 0.05
                        let v = root.sink.audio.volume + (event.angleDelta.y > 0 ? step : -step)
                        root.sink.audio.volume = Math.max(0, Math.min(1.5, v))
                    }
                }
            }

            JsonScript {
                scriptName: "cpu-usage.sh"
                intervalMs: 3000
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: false
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["xdg-terminal-exec", "btop"])
                }
            }

            JsonScript {
                scriptName: "gpu-usage.sh"
                intervalMs: 3000
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: false
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["xdg-terminal-exec", "btop"])
                }
            }

            MacStat {
                id: ramStat
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: false
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
                                ramStat.alert = pct >= 70
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
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: false
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
                                diskStat.alert = pct >= 70
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

            Pill {
                visible: netMod.visible
                Layout.alignment: Qt.AlignHCenter
                pillHeight: 28
                hPad: 4

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
                Layout.alignment: Qt.AlignHCenter
                pillHeight: 28
                hPad: 4

                BarText {
                    text: {
                        if (!root.battReady)
                            return ""
                        const pct = root.battPct
                        const icons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
                        const idx = Math.min(icons.length - 1, Math.max(0, Math.floor(pct / 10)))
                        return icons[idx] + "\n" + pct + "%"
                    }
                    color: root.battPct >= 0 && root.battPct <= 10 ? Theme.error
                         : root.battPct <= 20 ? Theme.high : Theme.ink
                    font.family: Theme.iconFontFallback
                    font.pixelSize: 11

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Quickshell.execDetached(["systemctl", "poweroff"])
                    }
                }
            }

            // Tower — same hover pattern as VOL
            Item {
                id: towerHit
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: towerBar.implicitWidth
                Layout.preferredHeight: towerBar.implicitHeight
                implicitWidth: towerBar.implicitWidth
                implicitHeight: towerBar.implicitHeight

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
                                    towerBar.value = d.ok ? (d.status || "online") : "--"
                                    towerBar.tooltip = d.tooltip || "tower status"
                                    towerBar.alert = !d.ok || d.class === "high"
                                        || (d.alarms_crit || 0) > 0
                                } catch (e) {
                                    towerBar.value = "--"
                                    towerBar.tooltip = "tower parse error"
                                    towerBar.alert = true
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

            Item {
                id: powerBtn
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                implicitWidth: 32
                implicitHeight: 32

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

