import QtQuick
import Quickshell
import Quickshell.Io
import ".."

MacStat {
    id: root
    label: "MOUSE"
    centerText: true
    value: "--"
    tooltip: "Mouse battery unavailable"

    function applyStatus(data: var): void {
        value = data.ok ? (data.display || (data.pct >= 0 ? data.pct + "%" : "--")) : "--"
        if (!data.ok) {
            tooltip = data.error && data.error !== "offline" ? data.error : "Mouse: no dongle"
            return
        }
        const bits = ["Mouse: " + value]
        if (data.mv > 0) bits.push((data.mv / 1000).toFixed(2) + "V")
        if (data.charging) bits.push("charging")
        tooltip = bits.join(" · ")
    }

    Process {
        id: statusProc
        command: [Globals.scriptsDir + "/ulx-battery.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.applyStatus(JSON.parse(text.trim()))
                } catch (e) {
                    root.applyStatus({ok: false, error: "Mouse battery unavailable"})
                }
            }
        }
    }

    Timer {
        interval: 10000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: { if (!statusProc.running) statusProc.running = true }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: Quickshell.execDetached(["xdg-open", "https://xpanel.finalmouse.com/overview"])
    }
}
