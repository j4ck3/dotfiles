import QtQuick
import Quickshell
import Quickshell.Io
import ".."

// Bar MOUSE stat. Hover opens MousePopup (battery details + polling rate);
// the popup replaces the plain MacStat tooltip.
MacStat {
    id: root
    label: "MOUSE"
    centerText: true
    value: "--"
    tooltip: ""

    function applyStatus(data: var): void {
        value = data.ok ? (data.display || (data.pct >= 0 ? data.pct + "%" : "--")) : "--"
        Globals.mouseBattery = data
    }

    // Record where the popup should dock before it opens.
    function syncAnchor(): void {
        const win = root.QsWindow
        if (!win?.contentItem)
            return
        const center = root.mapToItem(win.contentItem, root.width / 2, root.height / 2)
        Globals.mousePopupAnchorY = Math.round(center.y)
        const cardW = 280
        Globals.mousePopupRightMargin = Globals.clampPopupMargin(
            Math.round(win.contentItem.width - center.x - cardW / 2),
            cardW,
            win.contentItem.width
        )
    }

    onHoveredChanged: {
        if (hovered)
            root.syncAnchor()
        Globals.setMouseHover(hovered)
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
