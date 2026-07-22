import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Bluetooth
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
        color: Theme.secondary
        font.family: Theme.iconFontFallback
        font.pixelSize: 15
        verticalAlignment: Text.AlignVCenter
    }

    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.barMargin + 4
        anchors.rightMargin: Theme.barMargin + 4
        anchors.topMargin: Theme.barMargin
        anchors.bottomMargin: Theme.barMargin
        spacing: 6

        // Left: OS / kernel pill
        Pill {
            Layout.alignment: Qt.AlignVCenter

            BarIcon {
                id: kernelLabel
                color: Theme.primary
                text: "󰣇"
                font.pixelSize: 16

                Process {
                    command: ["uname", "-r"]
                    running: true
                    stdout: StdioCollector {
                        onStreamFinished: {}
                    }
                }
            }
        }

        Item { Layout.fillWidth: true }

        // Center: workspaces pill
        Workspaces {
            Layout.alignment: Qt.AlignVCenter
        }

        Item { Layout.fillWidth: true }

        // Right cluster
        RowLayout {
            Layout.alignment: Qt.AlignVCenter
            spacing: 6

            Pill {
                visible: root.spotify !== null && (root.spotify.trackTitle || "").length > 0
                Layout.alignment: Qt.AlignVCenter

                BarText {
                    color: Theme.tertiary
                    text: {
                        if (!root.spotify)
                            return ""
                        const icon = root.spotify.isPlaying ? "󰏤" : "󰐊"
                        const artist = root.spotify.trackArtist || ""
                        const title = root.spotify.trackTitle || ""
                        const full = artist ? (icon + "  " + artist + " — " + title) : (icon + "  " + title)
                        return full.length > 40 ? full.slice(0, 39) + "…" : full
                    }
                    font.pixelSize: 12

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton)
                                Quickshell.execDetached(["playerctl", "--player=spotify", "play-pause"])
                            else
                                Globals.toggleMedia()
                        }
                        onWheel: event => {
                            const dir = event.angleDelta.y > 0 ? "0.02+" : "0.02-"
                            Quickshell.execDetached(["playerctl", "--player=spotify", "volume", dir])
                        }
                    }
                }
            }

            Pill {
                visible: dictation.visible
                Layout.alignment: Qt.AlignVCenter

                JsonScript {
                    id: dictation
                    scriptName: "dictation-status.sh"
                    intervalMs: 1000
                }
            }

            Pill {
                Layout.alignment: Qt.AlignVCenter

                RowLayout {
                    spacing: 6

                    BarIcon {
                        visible: {
                            const adapter = Bluetooth.defaultAdapter
                            return !!(adapter && (!adapter.enabled || Bluetooth.devices.values.length === 0))
                        }
                        text: Bluetooth.defaultAdapter && !Bluetooth.defaultAdapter.enabled ? "󰂲" : "󰂯"
                        color: Theme.inkMuted
                        opacity: Bluetooth.defaultAdapter?.enabled ? 0.5 : 1

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Quickshell.execDetached(["blueberry"])
                        }
                    }

                    BarIcon {
                        visible: {
                            const adapter = Bluetooth.defaultAdapter
                            return !!(adapter && adapter.enabled && Bluetooth.devices.values.length > 0)
                        }
                        text: "󰂯"
                        color: Theme.ink

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Quickshell.execDetached(["blueberry"])
                        }
                    }
                }
            }

            // System stats — macOS stacked label / value (old Waybar style)
            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                spacing: 4

                MacStat {
                    label: "VOL"
                    value: root.sinkMuted ? "MUT" : (root.sinkVol + "%")
                    muted: root.sinkMuted
                    tooltip: "Output at " + root.sinkVol + "%"

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton)
                                Quickshell.execDetached(["pavucontrol"])
                            else
                                Globals.toggleVolume()
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
                        onClicked: Quickshell.execDetached(["systemctl", "poweroff"])
                    }
                }
            }

            Pill {
                Layout.alignment: Qt.AlignVCenter
                pillColor: Theme.surfaceContainerHigh

                RowLayout {
                    spacing: 6

                    BarText {
                        id: clockLabel
                        color: Theme.tertiary
                        font.pixelSize: 13
                        font.weight: Font.DemiBold

                        Timer {
                            interval: 1000
                            running: true
                            repeat: true
                            triggeredOnStart: true
                            onTriggered: {
                                const d = new Date()
                                const days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
                                const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
                                const pad = n => String(n).padStart(2, "0")
                                const tmp = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()))
                                tmp.setUTCDate(tmp.getUTCDate() + 4 - (tmp.getUTCDay() || 7))
                                const yearStart = new Date(Date.UTC(tmp.getUTCFullYear(), 0, 1))
                                const week = Math.ceil((((tmp - yearStart) / 86400000) + 1) / 7)
                                clockLabel.text = days[d.getDay()] + " " + pad(d.getDate()) + " " + months[d.getMonth()]
                                    + "  ·  " + pad(d.getHours()) + ":" + pad(d.getMinutes())
                            }
                        }
                    }

                    Rectangle {
                        width: 1
                        height: 14
                        color: Theme.hairlineMuted
                        radius: 1
                    }

                    BarIcon {
                        text: "󰐥"
                        color: Theme.error
                        font.pixelSize: 15

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Globals.togglePower()
                        }
                    }
                }
            }
        }
    }
}
