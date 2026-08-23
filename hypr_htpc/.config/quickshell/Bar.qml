import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

import "."
import "modules"

Item {
    id: root
    required property var modelData

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property int sinkVolume: sink?.audio ? Math.round(sink.audio.volume * 100) : 0
    readonly property bool sinkMuted: sink?.audio?.muted ?? false
    readonly property var battery: UPower.displayDevice
    readonly property bool batteryReady: !!(battery && battery.ready && battery.isLaptopBattery)
    readonly property int batteryPercent: batteryReady ? Math.round(battery.percentage) : -1
    property string displayText: "DISPLAY"

    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }

    component BarButton: Rectangle {
        id: button
        property string text: ""
        property color textColor: Theme.ink
        signal clicked
        implicitWidth: label.implicitWidth + 24
        implicitHeight: 42
        radius: 12
        color: mouse.containsMouse ? Theme.surfaceHover : "transparent"

        Text {
            id: label
            anchors.centerIn: parent
            text: button.text
            color: button.textColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.barFont
            font.weight: Font.Medium
        }
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }

    component Stat: Item {
        id: stat
        property string label: ""
        property string value: "--"
        property bool alert: false
        implicitWidth: Math.max(top.implicitWidth, bottom.implicitWidth) + 12
        implicitHeight: 46

        Column {
            anchors.centerIn: parent
            spacing: -2
            Text {
                id: top
                text: stat.label
                color: Theme.inkMuted
                font.family: Theme.fontFamily
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
            }
            Text {
                id: bottom
                text: stat.value
                color: stat.alert ? Theme.alert : Theme.ink
                font.family: Theme.fontFamily
                font.pixelSize: 16
                font.weight: Font.Medium
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    Workspaces {
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
    }

    RowLayout {
        anchors.centerIn: parent
        spacing: 3

        Text {
            id: clock
            color: Theme.ink
            font.family: Theme.fontFamily
            font.pixelSize: Theme.barFont
            font.weight: Font.Medium

            Timer {
                interval: 1000
                running: true
                repeat: true
                triggeredOnStart: true
                onTriggered: {
                    const d = new Date()
                    const days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
                    const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
                    const pad = n => String(n).padStart(2, "0")
                    const tmp = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()))
                    tmp.setUTCDate(tmp.getUTCDate() + 4 - (tmp.getUTCDay() || 7))
                    const start = new Date(Date.UTC(tmp.getUTCFullYear(), 0, 1))
                    const week = Math.ceil((((tmp - start) / 86400000) + 1) / 7)
                    clock.text = days[d.getDay()] + " " + pad(d.getDate()) + " "
                        + months[d.getMonth()] + " W" + week + " "
                        + pad(d.getHours()) + ":" + pad(d.getMinutes())
                }
            }
        }

        Text {
            text: root.sinkMuted ? "󰝟" : "󰕾"
            color: root.sinkMuted ? Theme.inkMuted : Theme.ink
            font.family: Theme.iconFont
            font.pixelSize: 22
            Layout.leftMargin: 10
            Layout.bottomMargin: 3

            MouseArea {
                anchors.fill: parent
                anchors.margins: -8
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.sink && root.sink.audio)
                        root.sink.audio.muted = !root.sink.audio.muted
                }
            }
        }

        Slider {
            id: centerVolume
            Layout.preferredWidth: 160
            leftPadding: 3
            rightPadding: 3
            from: 0
            to: 1.5
            value: root.sink?.audio?.volume ?? 0
            onMoved: {
                if (root.sink && root.sink.audio)
                    root.sink.audio.volume = value
            }

            background: Rectangle {
                x: centerVolume.leftPadding
                y: centerVolume.topPadding + centerVolume.availableHeight / 2 - height / 2
                width: centerVolume.availableWidth
                height: 6
                radius: 3
                color: Theme.surface
                Rectangle {
                    width: centerVolume.visualPosition * parent.width
                    height: parent.height
                    radius: 3
                    color: Theme.ink
                }
            }
            handle: Rectangle {
                x: centerVolume.leftPadding
                    + centerVolume.visualPosition * (centerVolume.availableWidth - width)
                y: centerVolume.topPadding
                    + centerVolume.availableHeight / 2 - height / 2
                width: 14
                height: 14
                radius: 7
                color: Theme.ink
            }
        }

        Text {
            text: root.sinkMuted ? "MUT" : root.sinkVolume + "%"
            color: root.sinkMuted ? Theme.inkMuted : Theme.ink
            font.family: Theme.fontFamily
            font.pixelSize: 13
            Layout.minimumWidth: 40
            horizontalAlignment: Text.AlignRight
        }
    }

    RowLayout {
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        spacing: 8

        BarButton {
            text: root.displayText
            onClicked: Globals.toggle("display")
        }

        BarButton {
            text: "SPK"
            onClicked: Quickshell.execDetached([Globals.scriptsDir + "/wake-speakers.sh"])
        }

        Item {
            Layout.preferredWidth: volumeStat.implicitWidth + 12
            Layout.fillHeight: true

            Rectangle {
                anchors.fill: parent
                anchors.topMargin: 7
                anchors.bottomMargin: 7
                radius: 12
                color: volumeMouse.containsMouse ? Theme.surfaceHover : "transparent"
            }

            Stat {
                id: volumeStat
                anchors.centerIn: parent
                label: "VOL"
                value: root.sinkMuted ? "MUT" : root.sinkVolume + "%"
            }

            MouseArea {
                id: volumeMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton)
                        Quickshell.execDetached(["pavucontrol"])
                    else
                        Globals.toggle("volume")
                }
                onWheel: event => {
                    if (!root.sink || !root.sink.audio)
                        return
                    const delta = event.angleDelta.y > 0 ? 0.05 : -0.05
                    root.sink.audio.volume = Math.max(0, Math.min(1.5,
                                                                  root.sink.audio.volume + delta))
                }
            }
        }

        Stat { id: cpu; label: "CPU" }
        Stat { id: ram; label: "RAM" }
        Stat { id: disk; label: "SSD" }

        BarButton {
            visible: root.batteryReady
            text: "BAT " + root.batteryPercent + "%"
            textColor: root.batteryPercent <= 10 ? Theme.alert : Theme.ink
            onClicked: Globals.toggle("power")
        }

        BarButton {
            text: "󰐥"
            textColor: Theme.alert
            onClicked: Globals.toggle("power")
        }
    }

    Process {
        id: displayProcess
        command: [Globals.scriptsDir + "/display-popup-data.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    if (d.monitor)
                        root.displayText = d.monitor.width + "×" + d.monitor.height
                            + " " + Math.round(d.monitor.refreshRate) + "HZ"
                } catch (e) {
                    root.displayText = "DISPLAY"
                }
            }
        }
    }

    Process {
        id: cpuProcess
        command: [Globals.scriptsDir + "/cpu-usage.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                const value = parseInt(text.trim())
                if (!isNaN(value)) {
                    cpu.value = value + "%"
                    cpu.alert = value >= 70
                }
            }
        }
    }

    Process {
        id: memoryProcess
        command: ["sh", "-c", "LC_ALL=C free | awk '/^Mem:/{printf \"%d\", ($2-$7)*100/$2}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const value = parseInt(text.trim())
                if (!isNaN(value)) {
                    ram.value = value + "%"
                    ram.alert = value >= 70
                }
            }
        }
    }

    Process {
        id: diskProcess
        command: ["sh", "-c", "df -P / | awk 'NR==2{gsub(/%/,\"\",$5); print $5}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const value = parseInt(text.trim())
                if (!isNaN(value)) {
                    disk.value = value + "%"
                    disk.alert = value >= 70
                }
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!displayProcess.running) displayProcess.running = true
            if (!cpuProcess.running) cpuProcess.running = true
            if (!memoryProcess.running) memoryProcess.running = true
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!diskProcess.running) diskProcess.running = true
    }
}
