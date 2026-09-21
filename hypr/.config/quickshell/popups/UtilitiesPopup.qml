import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import ".."

PanelWindow {
    id: root
    visible: Globals.utilitiesOpen
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    anchors { top: true; left: true; right: true; bottom: true }
    margins { top: Theme.popupTopInset; left: Theme.popupLeftInset }

    WlrLayershell.namespace: "qs-utilities"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    property bool otpOk: false
    property bool otpWatching: false
    property string otpCode: ""
    property string otpError: ""
    property int otpArmedLeft: 0
    property bool otpHasChip: false
    property bool cursorOk: false
    property bool cursorNeedLogin: false
    property bool cursorStale: false
    property string cursorModels: "--"
    property string cursorOther: "--"
    property string cursorOnDemand: "--"
    property string cursorUpdated: ""
    property string cursorError: ""
    property bool codexUsageOk: false
    property real codexFiveHourRemaining: -1
    property real codexWeeklyRemaining: -1
    property string codexUsageSubtitle: ""
    property bool openrouterUsageOk: false
    property bool openrouterConfigured: false
    property string openrouterUsageDisplay: "--"
    property string openrouterUsageSubtitle: ""
    property real openrouterRemaining: -1
    property bool netbirdOk: false
    property bool netbirdConnected: false
    property string netbirdIp: ""
    property string netbirdHost: ""
    property int netbirdPeersConnected: 0
    property int netbirdPeersTotal: 0
    property string netbirdRelays: "0/0"
    property string netbirdError: ""
    property bool mouseOk: false
    property int mousePct: -1
    property int mouseMv: 0
    property bool mouseCharging: false
    property string mouseDisplay: "--"
    property string mouseError: ""

    function closeAndRun(cmd: var): void {
        Quickshell.execDetached(cmd)
        Globals.utilitiesOpen = false
    }

    function refreshStatus(): void {
        otpStatusProc.running = true
        cursorStatusProc.running = true
        aiUsageStatusProc.running = true
        netbirdStatusProc.running = true
        mouseStatusProc.running = true
    }

    function applyAiUsage(data: var): void {
        const codex = data.codex || {}
        root.codexUsageOk = !!codex.ok
        root.codexFiveHourRemaining = codex.five_hour_remaining ?? -1
        root.codexWeeklyRemaining = codex.weekly_remaining ?? -1
        root.codexUsageSubtitle = codex.subtitle || codex.display || "Unavailable"

        const router = data.openrouter || {}
        root.openrouterUsageOk = !!router.ok
        root.openrouterConfigured = !!router.configured
        root.openrouterUsageDisplay = router.display || "--"
        root.openrouterUsageSubtitle = router.subtitle || "Unavailable"
        root.openrouterRemaining = router.remaining_percent ?? -1
    }

    function remainingText(value: real): string {
        return value < 0 ? "--" : Math.round(value) + "% left"
    }

    function usageColor(value: real): color {
        if (value >= 0 && value <= 10) return "#ffb4a8"
        if (value >= 0 && value <= 25) return "#ffcf70"
        return "#ffffff"
    }

    function toggleNetbird(): void {
        Quickshell.execDetached([Globals.scriptsDir + "/netbird-status.sh", "toggle"])
        statusRefreshTimer.restart()
    }

    function toggleOtpWatch(): void {
        Quickshell.execDetached([Globals.scriptsDir + "/otp-watch.sh", "toggle"])
        statusRefreshTimer.restart()
    }

    readonly property string netbirdSubtitle: {
        if (!root.netbirdOk)
            return root.netbirdError || "Unavailable"
        if (!root.netbirdConnected)
            return root.netbirdError || "Disconnected"
        const bits = []
        if (root.netbirdIp.length) bits.push(root.netbirdIp)
        bits.push(root.netbirdPeersConnected + "/" + root.netbirdPeersTotal + " peers")
        if (root.netbirdRelays.length) bits.push("relay " + root.netbirdRelays)
        return bits.join(" · ")
    }

    readonly property string cursorSubtitle: {
        if (root.cursorNeedLogin)
            return root.cursorError || "Log in via Helium"
        const bits = []
        if (root.cursorUpdated.length) bits.push(root.cursorUpdated)
        if (root.cursorStale) bits.push("stale")
        if (root.cursorError.length && !root.cursorOk) bits.push(root.cursorError)
        return bits.length ? bits.join(" · ") : "—"
    }

    readonly property string otpSubtitle: {
        if (root.otpError.length && !root.otpWatching) return root.otpError
        if (root.otpWatching)
            return "Watching · 2s" + (root.otpArmedLeft > 0 ? " · " + root.otpArmedLeft + "s" : "")
        if (root.otpHasChip && root.otpCode.length) return "Last: " + root.otpCode
        return "Idle"
    }

    readonly property string mouseSubtitle: {
        if (!root.mouseOk) return root.mouseError && root.mouseError !== "offline" ? root.mouseError : "No dongle"
        const bits = [root.mouseDisplay]
        if (root.mouseMv > 0) bits.push((root.mouseMv / 1000).toFixed(2) + "V")
        if (root.mouseCharging) bits.push("charging")
        return bits.join(" · ")
    }

    readonly property string mouseIcon: {
        if (!root.mouseOk) return "󰂎"
        if (root.mouseCharging) return "󰂄"
        const icons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
        return icons[Math.min(icons.length - 1, Math.max(0, Math.floor(root.mousePct / 10)))]
    }

    Process {
        id: otpStatusProc
        command: [Globals.scriptsDir + "/otp-watch.sh", "status"]
        stdout: StdioCollector { onStreamFinished: { try { const d = JSON.parse(text.trim()); root.otpOk = d.ok !== false; root.otpWatching = !!d.watching || d.mode === "armed"; root.otpCode = d.code || ""; root.otpError = d.error || ""; root.otpArmedLeft = d.armed_left ?? 0; root.otpHasChip = !!d.has_chip } catch (e) {} } }
    }
    Process {
        id: cursorStatusProc
        command: [Globals.scriptsDir + "/cursor-usage.sh", "status"]
        stdout: StdioCollector { onStreamFinished: { try { const d = JSON.parse(text.trim()); root.cursorOk = !!d.ok; root.cursorNeedLogin = !!d.need_login; root.cursorStale = !!d.stale; root.cursorModels = d.models || d.display || "--"; root.cursorOther = d.other || "--"; root.cursorOnDemand = d.on_demand || "--"; root.cursorUpdated = d.updated || ""; root.cursorError = d.error || "" } catch (e) {} } }
    }
    Process {
        id: aiUsageStatusProc
        command: [Globals.scriptsDir + "/ai-usage.py", "status"]
        stdout: StdioCollector { onStreamFinished: { try { root.applyAiUsage(JSON.parse(text.trim())) } catch (e) {} } }
    }
    Process {
        id: aiUsageFetchProc
        command: [Globals.scriptsDir + "/ai-usage.py", "fetch"]
        stdout: StdioCollector { onStreamFinished: { try { root.applyAiUsage(JSON.parse(text.trim())) } catch (e) {} } }
    }
    Process {
        id: netbirdStatusProc
        command: [Globals.scriptsDir + "/netbird-status.sh", "status"]
        stdout: StdioCollector { onStreamFinished: { try { const d = JSON.parse(text.trim()); root.netbirdOk = !!d.ok; root.netbirdConnected = !!d.connected; root.netbirdIp = d.ip || ""; root.netbirdHost = d.host || ""; root.netbirdPeersConnected = d.peers_connected ?? 0; root.netbirdPeersTotal = d.peers_total ?? 0; root.netbirdRelays = d.relays || "0/0"; root.netbirdError = d.error || "" } catch (e) {} } }
    }
    Process {
        id: mouseStatusProc
        command: [Globals.scriptsDir + "/ulx-battery.py"]
        stdout: StdioCollector { onStreamFinished: { try { const d = JSON.parse(text.trim()); root.mouseOk = !!d.ok; root.mousePct = d.pct ?? -1; root.mouseMv = d.mv ?? 0; root.mouseCharging = !!d.charging; root.mouseDisplay = d.display || "--"; root.mouseError = d.error || "" } catch (e) {} } }
    }

    Timer { id: statusRefreshTimer; interval: 120; onTriggered: root.refreshStatus() }
    Timer { interval: 1000; running: root.visible; repeat: true; triggeredOnStart: true; onTriggered: root.refreshStatus() }

    onVisibleChanged: {
        if (visible) {
            Quickshell.execDetached([Globals.scriptsDir + "/cursor-usage.sh", "fetch"])
            if (!aiUsageFetchProc.running)
                aiUsageFetchProc.running = true
            root.refreshStatus()
            card.playIn()
        } else card.resetOut()
    }

    MouseArea { anchors.fill: parent; onClicked: Globals.closeAll() }

    PopupCard {
        id: card
        anchors.fill: parent
        title: "Utilities"
        cardWidth: 300
        topMargin: Theme.widgetTopGap
        bottomMargin: Theme.widgetTopGap
        rightMargin: Globals.utilitiesPopupRightMargin
        fromBottom: Theme.barVertical
        animateIn: true
        onClosed: Globals.closeAll()
        onCardHover: inside => Globals.setUtilitiesHover(inside)

        M3Section {
            title: "CURSOR"
            RowLayout {
                Layout.fillWidth: true; spacing: 10
                M3IconButton { icon: "󰊭"; active: root.cursorOk; onClicked: root.closeAndRun([Globals.scriptsDir + "/cursor-usage.sh", "login"]) }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 2
                    Text { text: root.cursorNeedLogin ? "Cursor" : "Cursor models  " + root.cursorModels; color: "#ffffff"; font.pixelSize: 13; font.family: Theme.fontFamily; Layout.fillWidth: true }
                    Text { visible: !root.cursorNeedLogin; text: "Other models  " + root.cursorOther; color: root.cursorOther === "100%" ? "#ffb4a8" : "#ffffff"; font.pixelSize: 13; font.family: Theme.fontFamily }
                    Text { visible: !root.cursorNeedLogin; text: "On-demand  " + root.cursorOnDemand; color: "#ffffff"; font.pixelSize: 13; font.family: Theme.fontFamily }
                    Text { text: root.cursorSubtitle; color: root.cursorNeedLogin || root.cursorStale ? "#ffb4a8" : Qt.rgba(1,1,1,.45); font.pixelSize: 11; font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true }
                }
                M3IconButton { icon: "󰑐"; onClicked: { Quickshell.execDetached([Globals.scriptsDir + "/cursor-usage.sh", "fetch"]); statusRefreshTimer.restart() } }
            }
        }

        M3Section {
            title: "CODEX"
            RowLayout {
                Layout.fillWidth: true; spacing: 10
                M3IconButton { icon: "󰚩"; active: root.codexUsageOk; onClicked: root.closeAndRun(["xdg-open", "https://chatgpt.com/codex/cloud/settings/analytics#usage"]) }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 2
                    Text { text: "5-hour  " + root.remainingText(root.codexFiveHourRemaining); color: root.usageColor(root.codexFiveHourRemaining); font.pixelSize: 13; font.family: Theme.fontFamily; Layout.fillWidth: true }
                    Text { text: "Weekly  " + root.remainingText(root.codexWeeklyRemaining); color: root.usageColor(root.codexWeeklyRemaining); font.pixelSize: 13; font.family: Theme.fontFamily }
                    Text { text: root.codexUsageSubtitle; color: root.codexUsageOk ? Qt.rgba(1,1,1,.45) : "#ffb4a8"; font.pixelSize: 11; font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true }
                }
                M3IconButton { icon: "󰑐"; onClicked: root.refreshStatus() }
            }
        }

        M3Section {
            title: "OPENROUTER"
            RowLayout {
                Layout.fillWidth: true; spacing: 10
                M3IconButton { icon: "󱐋"; active: root.openrouterUsageOk; onClicked: root.closeAndRun(["xdg-open", "https://openrouter.ai/workspaces/default"]) }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 2
                    Text { text: root.openrouterUsageDisplay; color: root.openrouterUsageOk ? root.usageColor(root.openrouterRemaining) : "#ffffff"; font.pixelSize: 13; font.family: Theme.fontFamily; Layout.fillWidth: true; elide: Text.ElideRight }
                    Text { text: root.openrouterUsageSubtitle; color: root.openrouterUsageOk || !root.openrouterConfigured ? Qt.rgba(1,1,1,.45) : "#ffb4a8"; font.pixelSize: 11; font.weight: Font.DemiBold; elide: Text.ElideMiddle; Layout.fillWidth: true }
                }
                M3IconButton { icon: "󰑐"; onClicked: { if (!aiUsageFetchProc.running) aiUsageFetchProc.running = true } }
            }
        }

        M3Section {
            title: "NETBIRD"
            RowLayout {
                Layout.fillWidth: true; spacing: 10
                M3IconButton { icon: root.netbirdConnected ? "󰒍" : "󰌙"; active: root.netbirdConnected; onClicked: root.toggleNetbird() }
                ColumnLayout { Layout.fillWidth: true; spacing: 2
                    Text { text: root.netbirdHost.length ? "Netbird · " + root.netbirdHost : "Netbird"; color: "#ffffff"; font.pixelSize: 13; font.family: Theme.fontFamily; elide: Text.ElideRight; Layout.fillWidth: true }
                    Text { text: root.netbirdSubtitle; color: root.netbirdConnected ? Qt.rgba(1,1,1,.55) : "#ffb4a8"; font.pixelSize: 11; font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true }
                }
            }
        }

        M3Section {
            title: "MOUSE"
            RowLayout {
                Layout.fillWidth: true; spacing: 10
                M3IconButton { icon: root.mouseIcon; active: root.mouseOk && root.mousePct > 20; danger: root.mouseOk && root.mousePct >= 0 && root.mousePct <= 20; onClicked: root.closeAndRun(["xdg-open", "https://xpanel.finalmouse.com/overview"]) }
                ColumnLayout { Layout.fillWidth: true; spacing: 2
                    Text { text: "Mouse"; color: "#ffffff"; font.pixelSize: 13; font.family: Theme.fontFamily }
                    Text { text: root.mouseSubtitle; color: !root.mouseOk || (root.mousePct >= 0 && root.mousePct <= 20) ? "#ffb4a8" : Qt.rgba(1,1,1,.55); font.pixelSize: 11; font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true }
                }
            }
        }

        M3Section {
            title: "OTP WATCH"
            RowLayout {
                Layout.fillWidth: true; spacing: 10
                M3IconButton { icon: root.otpWatching ? "󰍡" : "󰇮"; active: root.otpWatching; onClicked: root.toggleOtpWatch() }
                ColumnLayout { Layout.fillWidth: true; spacing: 2
                    Text { text: root.otpWatching ? "Watching…" : "OTP Watch"; color: "#ffffff"; font.pixelSize: 13; font.family: Theme.fontFamily }
                    Text { text: root.otpSubtitle; color: Qt.rgba(1,1,1,.55); font.pixelSize: 11; font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true }
                }
            }
        }
    }
}
