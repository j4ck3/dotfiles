import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import ".."

PanelWindow {
    id: root
    visible: Globals.powerOpen
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

    WlrLayershell.namespace: "qs-power"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    property bool shutDownArmed: false
    property int gamma: 100
    property int temp: 6500
    property bool identity: true
    property bool lightOn: false
    property int lightBrightness: 0
    property real lightHue: 0
    property real lightSat: 100
    property string lightName: "Gaming light"
    property bool lightOk: false
    // Optimistic brightness while HA/LIFX catch up (-1 = trust polls).
    property int lightPendingBrightness: -1
    property bool lightColorPending: false
    property bool fanOk: false
    property bool fanOverride: false
    property int fanDuty: 0
    property int fanRpm: 0
    // Optimistic duty while CoolerControl catches up (-1 = trust polls).
    property int fanPendingDuty: -1
    property bool otpOk: false
    property bool otpWatching: false
    property string otpCode: ""
    property string otpFrom: ""
    property string otpError: ""
    property int otpArmedLeft: 0
    property bool otpHasChip: false
    property bool cursorOk: false
    property bool cursorNeedLogin: false
    property bool cursorStale: false
    property string cursorDisplay: "--"
    property string cursorModels: "--"
    property string cursorOther: "--"
    property string cursorOnDemand: "--"
    property string cursorUpdated: ""
    property string cursorError: ""
    property bool netbirdOk: false
    property bool netbirdConnected: false
    property string netbirdDisplay: "Offline"
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
    property int sliderDragCount: 0
    readonly property bool sliderDragging: sliderDragCount > 0
    property bool cardHovering: false
    property var pendingArgs: []
    property var pendingHaArgs: []
    property var pendingFanArgs: []

    readonly property int warmthUi: {
        if (root.identity || root.temp >= 6500)
            return 0
        return Math.round(((6500 - root.temp) / (6500 - 2500)) * 100)
    }

    function run(cmd: var): void {
        Quickshell.execDetached(cmd)
        Globals.powerOpen = false
    }

    function beginSliderDrag(): void {
        root.sliderDragCount++
        Globals.setPowerHover(true)
    }

    function endSliderDrag(): void {
        root.sliderDragCount = Math.max(0, root.sliderDragCount - 1)
        if (root.sliderDragCount === 0) {
            controlDebounce.stop()
            haControlDebounce.stop()
            fanControlDebounce.stop()
            root.flushControl()
            root.flushHaControl()
            root.flushFanControl()
            statusRefreshTimer.restart()
            if (!root.cardHovering)
                Globals.setPowerHover(false)
        }
    }

    function refreshStatus(): void {
        if (root.sliderDragging)
            return
        statusProc.running = true
        if (!lightSlider.pressed && !hueWheel.pressed)
            haStatusProc.running = true
        fanStatusProc.running = true
        otpStatusProc.running = true
        cursorStatusProc.running = true
        netbirdStatusProc.running = true
    }

    function applyNetbirdStatus(data: var): void {
        root.netbirdOk = !!data.ok
        root.netbirdConnected = !!data.connected
        root.netbirdDisplay = data.display || (root.netbirdConnected ? "Connected" : "Disconnected")
        root.netbirdIp = data.ip || ""
        root.netbirdHost = data.host || ""
        root.netbirdPeersConnected = data.peers_connected ?? 0
        root.netbirdPeersTotal = data.peers_total ?? 0
        root.netbirdRelays = data.relays || "0/0"
        root.netbirdError = data.error || ""
    }

    function toggleNetbird(): void {
        Quickshell.execDetached([Globals.scriptsDir + "/netbird-status.sh", "toggle"])
        statusRefreshTimer.restart()
    }

    readonly property string netbirdSubtitle: {
        if (!root.netbirdOk) {
            if (root.netbirdError.length > 0)
                return root.netbirdError
            return "Unavailable"
        }
        if (!root.netbirdConnected) {
            if (root.netbirdError.length > 0)
                return root.netbirdError
            return "Disconnected"
        }
        const bits = []
        if (root.netbirdIp.length > 0)
            bits.push(root.netbirdIp)
        bits.push(root.netbirdPeersConnected + "/" + root.netbirdPeersTotal + " peers")
        if (root.netbirdRelays.length > 0)
            bits.push("relay " + root.netbirdRelays)
        return bits.join(" · ")
    }

    function applyOtpStatus(data: var): void {
        root.otpOk = data.ok !== false
        root.otpWatching = !!data.watching || data.mode === "armed"
        root.otpCode = data.code || ""
        root.otpFrom = data["from"] || ""
        root.otpError = data.error || ""
        root.otpArmedLeft = data.armed_left ?? 0
        root.otpHasChip = !!data.has_chip
    }

    function applyCursorStatus(data: var): void {
        root.cursorOk = !!data.ok
        root.cursorNeedLogin = !!data.need_login
        root.cursorStale = !!data.stale
        root.cursorDisplay = data.display || "--"
        root.cursorModels = data.models || data.display || "--"
        root.cursorOther = data.other || "--"
        root.cursorOnDemand = data.on_demand || "--"
        root.cursorUpdated = data.updated || ""
        root.cursorError = data.error || ""
    }

    function openCursorUsage(): void {
        root.run([Globals.scriptsDir + "/cursor-usage.sh", "login"])
    }

    function refreshCursorUsage(): void {
        Quickshell.execDetached([Globals.scriptsDir + "/cursor-usage.sh", "fetch"])
        statusRefreshTimer.restart()
    }

    readonly property string cursorSubtitle: {
        if (root.cursorNeedLogin)
            return root.cursorError.length > 0 ? root.cursorError : "Log in via Helium"
        const bits = []
        if (root.cursorUpdated.length > 0)
            bits.push(root.cursorUpdated)
        if (root.cursorStale)
            bits.push("stale")
        if (root.cursorError.length > 0 && !root.cursorOk)
            bits.push(root.cursorError)
        return bits.length ? bits.join(" · ") : "—"
    }

    function applyMouseStatus(data: var): void {
        root.mouseOk = !!data.ok
        root.mousePct = data.pct ?? -1
        root.mouseMv = data.mv ?? 0
        root.mouseCharging = !!data.charging
        root.mouseDisplay = data.display || "--"
        root.mouseError = data.error || ""
    }

    function openMouseXpanel(): void {
        root.run(["xdg-open", "https://xpanel.finalmouse.com/overview"])
    }

    readonly property string mouseSubtitle: {
        if (!root.mouseOk) {
            if (root.mouseError.length > 0 && root.mouseError !== "offline")
                return root.mouseError
            return "No dongle"
        }
        const bits = []
        bits.push(root.mouseDisplay)
        if (root.mouseMv > 0)
            bits.push((root.mouseMv / 1000).toFixed(2) + "V")
        if (root.mouseCharging)
            bits.push("charging")
        return bits.join(" · ")
    }

    readonly property string mouseIcon: {
        if (!root.mouseOk)
            return "󰂎"
        if (root.mouseCharging)
            return "󰂄"
        const pct = root.mousePct
        const icons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
        const idx = Math.min(icons.length - 1, Math.max(0, Math.floor(pct / 10)))
        return icons[idx]
    }

    function toggleOtpWatch(): void {
        Quickshell.execDetached([Globals.scriptsDir + "/otp-watch.sh", "toggle"])
        statusRefreshTimer.restart()
    }

    readonly property string otpSubtitle: {
        if (root.otpError.length > 0 && !root.otpWatching)
            return root.otpError
        if (root.otpWatching) {
            const left = root.otpArmedLeft > 0 ? (" · " + root.otpArmedLeft + "s") : ""
            return "Watching · 2s" + left
        }
        if (root.otpHasChip && root.otpCode.length > 0)
            return "Last: " + root.otpCode
        if (!root.otpOk && root.otpError.length > 0)
            return root.otpError
        return "Idle"
    }

    function flushControl(): void {
        if (!root.pendingArgs || root.pendingArgs.length === 0)
            return
        const args = root.pendingArgs
        root.pendingArgs = []
        Quickshell.execDetached([Globals.scriptsDir + "/display-control.sh"].concat(args))
        statusRefreshTimer.restart()
    }

    function runControl(args: var): void {
        root.pendingArgs = args
        controlDebounce.restart()
    }

    function flushHaControl(): void {
        if (!root.pendingHaArgs || root.pendingHaArgs.length === 0)
            return
        const args = root.pendingHaArgs
        root.pendingHaArgs = []
        Quickshell.execDetached([Globals.scriptsDir + "/ha-light-control.sh"].concat(args))
        // Delay poll so optimistic UI not stomped by stale HA state.
        haPollHold.restart()
        statusRefreshTimer.restart()
    }

    function runHaControl(args: var): void {
        root.pendingHaArgs = args
        haControlDebounce.restart()
    }

    function flushFanControl(): void {
        if (!root.pendingFanArgs || root.pendingFanArgs.length === 0)
            return
        const args = root.pendingFanArgs
        root.pendingFanArgs = []
        Quickshell.execDetached([Globals.scriptsDir + "/fan-control.sh"].concat(args))
        fanPollHold.restart()
        statusRefreshTimer.restart()
    }

    function runFanControl(args: var): void {
        root.pendingFanArgs = args
        fanControlDebounce.restart()
    }

    function setFanOptimistic(duty: int, override: bool): void {
        const v = Math.max(0, Math.min(100, duty))
        root.fanDuty = v
        root.fanOverride = override
        root.fanPendingDuty = override ? v : -1
        if (override)
            fanOptimisticTimeout.restart()
        else
            fanOptimisticTimeout.stop()
    }

    function restoreFanAuto(): void {
        root.setFanOptimistic(root.fanDuty, false)
        Quickshell.execDetached([Globals.scriptsDir + "/fan-control.sh", "auto"])
        fanPollHold.restart()
        statusRefreshTimer.restart()
    }

    function setFanMax(): void {
        root.setFanOptimistic(100, true)
        root.runFanControl(["set", "100"])
    }

    function setFanQuiet(): void {
        root.setFanOptimistic(20, true)
        root.runFanControl(["set", "20"])
    }

    function applyFanStatus(data: var): void {
        root.fanOk = !!data.ok
        if (fanPollHold.running)
            return

        const override = !!data.override
        const duty = data.duty ?? 0
        const rpm = data.rpm ?? 0
        root.fanRpm = rpm

        if (root.fanPendingDuty >= 0) {
            const want = root.fanPendingDuty
            const match = override && Math.abs(duty - want) <= 2
            if (match) {
                root.fanPendingDuty = -1
                root.fanOverride = override
                root.fanDuty = duty
                fanOptimisticTimeout.stop()
            }
            return
        }

        root.fanOverride = override
        root.fanDuty = duty
    }

    function setLightOptimistic(brightness: int): void {
        const v = Math.max(0, Math.min(100, brightness))
        root.lightBrightness = v
        root.lightOn = v > 0
        root.lightPendingBrightness = v
        lightOptimisticTimeout.restart()
    }

    function setLightColorOptimistic(hue: real, sat: real): void {
        root.lightHue = ((hue % 360) + 360) % 360
        root.lightSat = Math.max(0, Math.min(100, sat))
        root.lightColorPending = true
        if (!root.lightOn) {
            const v = root.lightBrightness > 0 ? root.lightBrightness : 100
            root.setLightOptimistic(v)
        }
        lightOptimisticTimeout.restart()
    }

    function toggleLight(): void {
        const nextOn = !root.lightOn
        if (nextOn) {
            const v = root.lightBrightness > 0 ? root.lightBrightness : 100
            root.setLightOptimistic(v)
        } else {
            root.setLightOptimistic(0)
        }
        Quickshell.execDetached([Globals.scriptsDir + "/ha-light-control.sh", "toggle"])
        haPollHold.restart()
        statusRefreshTimer.restart()
    }

    function applyHaStatus(data: var): void {
        root.lightOk = !!data.ok
        if (data.name)
            root.lightName = data.name
        if (lightSlider.pressed || hueWheel.pressed || haPollHold.running)
            return

        const on = !!data.on
        const bri = data.brightness ?? 0
        const hue = data.hue ?? 0
        const sat = data.sat ?? 0

        if (root.lightPendingBrightness >= 0) {
            const want = root.lightPendingBrightness
            const match = want === 0
                ? !on
                : (on && Math.abs(bri - want) <= 3)
            if (match) {
                root.lightPendingBrightness = -1
                root.lightOn = on
                root.lightBrightness = bri
            }
        } else {
            root.lightOn = on
            root.lightBrightness = bri
        }

        if (root.lightColorPending) {
            const hueMatch = Math.abs((((hue - root.lightHue) + 540) % 360) - 180) <= 6
            const satMatch = Math.abs(sat - root.lightSat) <= 4
            if (hueMatch && satMatch)
                root.lightColorPending = false
            else
                return
        }

        if (!root.lightColorPending) {
            root.lightHue = hue
            root.lightSat = sat
        }

        if (root.lightPendingBrightness < 0 && !root.lightColorPending)
            lightOptimisticTimeout.stop()
    }

    function warmthToTemp(warmth: int): int {
        if (warmth <= 0)
            return 6500
        const t = Math.round(6500 - (warmth / 100) * (6500 - 2500))
        return Math.max(2500, Math.min(6500, t))
    }

    Timer {
        id: controlDebounce
        interval: 50
        onTriggered: root.flushControl()
    }

    Timer {
        id: haControlDebounce
        interval: 50
        onTriggered: root.flushHaControl()
    }

    Timer {
        id: fanControlDebounce
        interval: 50
        onTriggered: root.flushFanControl()
    }

    Timer {
        id: haPollHold
        interval: 400
        repeat: false
    }

    Timer {
        id: fanPollHold
        interval: 400
        repeat: false
    }

    Timer {
        id: lightOptimisticTimeout
        interval: 3000
        onTriggered: {
            root.lightPendingBrightness = -1
            root.lightColorPending = false
        }
    }

    Timer {
        id: fanOptimisticTimeout
        interval: 3000
        onTriggered: root.fanPendingDuty = -1
    }

    Process {
        id: statusProc
        command: [Globals.scriptsDir + "/display-status.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text.trim())
                    if (!gammaSlider.pressed)
                        root.gamma = data.gamma ?? 100
                    if (!warmthSlider.pressed) {
                        root.temp = data.temp ?? 6500
                        root.identity = !!data.identity
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: haStatusProc
        command: [Globals.scriptsDir + "/ha-light-status.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.applyHaStatus(JSON.parse(text.trim()))
                } catch (e) {}
            }
        }
    }

    Process {
        id: fanStatusProc
        command: [Globals.scriptsDir + "/fan-status.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.applyFanStatus(JSON.parse(text.trim()))
                } catch (e) {}
            }
        }
    }

    Process {
        id: otpStatusProc
        command: [Globals.scriptsDir + "/otp-watch.sh", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.applyOtpStatus(JSON.parse(text.trim()))
                } catch (e) {}
            }
        }
    }

    Process {
        id: cursorStatusProc
        command: [Globals.scriptsDir + "/cursor-usage.sh", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.applyCursorStatus(JSON.parse(text.trim()))
                } catch (e) {}
            }
        }
    }

    Process {
        id: netbirdStatusProc
        command: [Globals.scriptsDir + "/netbird-status.sh", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.applyNetbirdStatus(JSON.parse(text.trim()))
                } catch (e) {}
            }
        }
    }

    Process {
        id: mouseStatusProc
        command: [Globals.scriptsDir + "/ulx-battery.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.applyMouseStatus(JSON.parse(text.trim()))
                } catch (e) {}
            }
        }
    }

    Timer {
        id: statusRefreshTimer
        interval: 120
        onTriggered: root.refreshStatus()
    }

    Timer {
        interval: 1000
        running: root.visible && !root.sliderDragging
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshStatus()
    }

    onVisibleChanged: {
        if (visible) {
            shutDownArmed = false
            Quickshell.execDetached([Globals.scriptsDir + "/cursor-usage.sh", "fetch"])
            mouseStatusProc.running = true
            root.refreshStatus()
            card.playIn()
        } else {
            shutDownArmed = false
            card.resetOut()
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: Globals.powerOpen = false
    }

    PopupCard {
        id: card
        anchors.fill: parent
        title: "Power"
        cardWidth: 300
        topMargin: Theme.widgetTopGap
        bottomMargin: Theme.widgetTopGap
        rightMargin: Globals.powerPopupRightMargin
        fromBottom: Theme.barVertical
        animateIn: true
        onClosed: Globals.powerOpen = false
        onCardHover: inside => {
            root.cardHovering = inside
            if (!inside && root.sliderDragging)
                return
            Globals.setPowerHover(inside)
        }

        M3Section {
            title: "DISPLAY"

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                M3IconButton {
                    icon: "󰃠"
                    active: root.gamma > 10
                    onClicked: root.runControl(["gamma", "100"])
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: "Brightness"
                        color: "#ffffff"
                        font.pixelSize: 13
                        font.family: Theme.fontFamily
                        Layout.fillWidth: true
                    }

                    Text {
                        text: Math.round(gammaSlider.pressed ? gammaSlider.value : root.gamma) + "%"
                        color: Qt.rgba(1, 1, 1, 0.55)
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }
            }

            M3Slider {
                id: gammaSlider
                Layout.fillWidth: true
                Layout.leftMargin: 46
                from: 10
                to: 100
                fillColor: "#ffffff"
                trackColor: Qt.rgba(1, 1, 1, 0.18)
                trackHeight: 4
                showHandle: true

                Binding {
                    target: gammaSlider
                    property: "value"
                    value: root.gamma
                    when: !gammaSlider.pressed
                    restoreMode: Binding.RestoreNone
                }

                onMoved: {
                    const v = Math.round(value)
                    root.gamma = v
                    root.runControl(["gamma", String(v)])
                }
                onPressedChanged: {
                    if (pressed)
                        root.beginSliderDrag()
                    else
                        root.endSliderDrag()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Layout.topMargin: 4

                M3IconButton {
                    icon: root.identity ? "󰖨" : "󰖔"
                    active: !root.identity
                    onClicked: root.runControl(["toggle-night"])
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: root.identity ? "Night light off" : "Night light"
                        color: "#ffffff"
                        font.pixelSize: 13
                        font.family: Theme.fontFamily
                        Layout.fillWidth: true
                    }

                    Text {
                        text: {
                            if (warmthSlider.pressed) {
                                const t = root.warmthToTemp(Math.round(warmthSlider.value))
                                return t >= 6500 ? "Off" : (t + "K")
                            }
                            return root.identity ? "Off" : (root.temp + "K")
                        }
                        color: Qt.rgba(1, 1, 1, 0.55)
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }
            }

            M3Slider {
                id: warmthSlider
                Layout.fillWidth: true
                Layout.leftMargin: 46
                from: 0
                to: 100
                fillColor: root.identity ? Qt.rgba(1, 1, 1, 0.45) : "#ffb86c"
                trackColor: Qt.rgba(1, 1, 1, 0.18)
                trackHeight: 4
                showHandle: true

                Binding {
                    target: warmthSlider
                    property: "value"
                    value: root.warmthUi
                    when: !warmthSlider.pressed
                    restoreMode: Binding.RestoreNone
                }

                onMoved: {
                    const w = Math.round(value)
                    const t = root.warmthToTemp(w)
                    if (t >= 6500) {
                        root.identity = true
                        root.temp = 6500
                        root.runControl(["identity"])
                    } else {
                        root.identity = false
                        root.temp = t
                        root.runControl(["temp", String(t)])
                    }
                }
                onPressedChanged: {
                    if (pressed)
                        root.beginSliderDrag()
                    else
                        root.endSliderDrag()
                }
            }
        }

        M3Section {
            title: "LIGHTS"

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                M3IconButton {
                    icon: "󰐥"
                    active: root.lightOn
                    onClicked: root.toggleLight()
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: root.lightName
                        color: "#ffffff"
                        font.pixelSize: 13
                        font.family: Theme.fontFamily
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        text: {
                            if (!root.lightOk)
                                return "Offline"
                            const v = lightSlider.pressed
                                ? Math.round(lightSlider.value)
                                : root.lightBrightness
                            if (!root.lightOn || v <= 0)
                                return "Off"
                            return v + "%"
                        }
                        color: Qt.rgba(1, 1, 1, 0.55)
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }
            }

            M3Slider {
                id: lightSlider
                Layout.fillWidth: true
                Layout.leftMargin: 46
                from: 0
                to: 100
                fillColor: root.lightOn ? "#7dd3c0" : Qt.rgba(1, 1, 1, 0.45)
                trackColor: Qt.rgba(1, 1, 1, 0.18)
                trackHeight: 4
                showHandle: true
                opacity: root.lightOk ? 1 : 0.45

                Binding {
                    target: lightSlider
                    property: "value"
                    value: root.lightOn ? root.lightBrightness : 0
                    when: !lightSlider.pressed
                    restoreMode: Binding.RestoreNone
                }

                onMoved: {
                    const v = Math.round(value)
                    root.setLightOptimistic(v)
                    root.runHaControl(["set", String(v)])
                }
                onPressedChanged: {
                    if (pressed)
                        root.beginSliderDrag()
                    else
                        root.endSliderDrag()
                }
            }

            HueWheel {
                id: hueWheel
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 8
                Layout.preferredWidth: 168
                Layout.preferredHeight: 168
                enabled: root.lightOk
                opacity: root.lightOk ? 1 : 0.45

                Binding {
                    target: hueWheel
                    property: "hue"
                    value: root.lightHue
                    when: !hueWheel.pressed
                    restoreMode: Binding.RestoreNone
                }
                Binding {
                    target: hueWheel
                    property: "saturation"
                    value: root.lightSat
                    when: !hueWheel.pressed
                    restoreMode: Binding.RestoreNone
                }

                onHsMoved: (h, s) => {
                    root.setLightColorOptimistic(h, s)
                    root.runHaControl([
                        "hs",
                        h.toFixed(3),
                        s.toFixed(3)
                    ])
                }
                onPressActive: active => {
                    if (active)
                        root.beginSliderDrag()
                    else
                        root.endSliderDrag()
                }
            }
        }

        M3Section {
            title: "CASE FANS"

            Text {
                Layout.fillWidth: true
                text: {
                    if (!root.fanOk)
                        return "Offline"
                    let mode = "Auto"
                    if (root.fanOverride) {
                        if (root.fanDuty >= 95)
                            mode = "Max"
                        else if (root.fanDuty <= 25)
                            mode = "Quiet"
                        else
                            mode = "Fixed"
                    }
                    return mode + " · " + root.fanDuty + "% · " + root.fanRpm + " RPM"
                }
                color: Qt.rgba(1, 1, 1, 0.55)
                font.pixelSize: 11
                font.weight: Font.DemiBold
                font.family: Theme.fontFamily
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                M3IconButton {
                    Layout.fillWidth: true
                    wide: true
                    icon: "󰈐"
                    label: "Auto"
                    active: root.fanOk && !root.fanOverride
                    opacity: root.fanOk ? 1 : 0.45
                    onClicked: root.restoreFanAuto()
                }

                M3IconButton {
                    Layout.fillWidth: true
                    wide: true
                    icon: "󰒙"
                    label: "Quiet"
                    active: root.fanOk && root.fanOverride && root.fanDuty <= 25
                    opacity: root.fanOk ? 1 : 0.45
                    onClicked: root.setFanQuiet()
                }

                M3IconButton {
                    Layout.fillWidth: true
                    wide: true
                    icon: "󰓅"
                    label: "Max"
                    active: root.fanOk && root.fanOverride && root.fanDuty >= 95
                    opacity: root.fanOk ? 1 : 0.45
                    onClicked: root.setFanMax()
                }
            }
        }

        M3Section {
            title: "NETBIRD"

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                M3IconButton {
                    icon: root.netbirdConnected ? "󰒍" : "󰌙"
                    active: root.netbirdConnected
                    onClicked: root.toggleNetbird()
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: {
                            if (root.netbirdHost.length > 0)
                                return "Netbird · " + root.netbirdHost
                            return "Netbird · " + root.netbirdDisplay
                        }
                        color: "#ffffff"
                        font.pixelSize: 13
                        font.family: Theme.fontFamily
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        text: root.netbirdSubtitle
                        color: root.netbirdConnected
                            ? Qt.rgba(1, 1, 1, 0.55)
                            : "#ffb4a8"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        font.family: Theme.fontFamily
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }
        }

        M3Section {
            title: "CURSOR"

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                M3IconButton {
                    icon: "󰊭"
                    active: root.cursorOk
                    onClicked: root.openCursorUsage()
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: root.cursorNeedLogin ? "Cursor" : ("Cursor models  " + root.cursorModels)
                        color: "#ffffff"
                        font.pixelSize: 13
                        font.family: Theme.fontFamily
                        Layout.fillWidth: true
                    }

                    Text {
                        visible: !root.cursorNeedLogin
                        text: "Other models  " + root.cursorOther
                        color: root.cursorOther === "100%"
                            ? "#ffb4a8"
                            : "#ffffff"
                        font.pixelSize: 13
                        font.family: Theme.fontFamily
                        Layout.fillWidth: true
                    }

                    Text {
                        visible: !root.cursorNeedLogin
                        text: "On-demand  " + root.cursorOnDemand
                        color: "#ffffff"
                        font.pixelSize: 13
                        font.family: Theme.fontFamily
                        Layout.fillWidth: true
                    }

                    Text {
                        text: root.cursorSubtitle
                        color: (root.cursorNeedLogin || root.cursorStale)
                            ? "#ffb4a8"
                            : Qt.rgba(1, 1, 1, 0.45)
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        font.family: Theme.fontFamily
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                M3IconButton {
                    icon: "󰑐"
                    active: false
                    onClicked: root.refreshCursorUsage()
                }
            }
        }

        M3Section {
            title: "OTP"

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                M3IconButton {
                    icon: root.otpWatching ? "󰍡" : "󰇮"
                    active: root.otpWatching
                    onClicked: root.toggleOtpWatch()
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: root.otpWatching ? "Watching…" : "OTP Watch"
                        color: "#ffffff"
                        font.pixelSize: 13
                        font.family: Theme.fontFamily
                        Layout.fillWidth: true
                    }

                    Text {
                        text: root.otpSubtitle
                        color: Qt.rgba(1, 1, 1, 0.55)
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        font.family: Theme.fontFamily
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }
        }

        M3Section {
            title: "VIRTUAL MACHINES"

            M3IconButton {
                Layout.fillWidth: true
                wide: true
                icon: "󰖳"
                label: "Windows 11"
                // Direct exec — xdg-terminal-exec + setsid race kills start when PTY closes.
                onClicked: root.run(["/usr/local/bin/windows11-start", "--yes"])
            }

            M3IconButton {
                Layout.fillWidth: true
                wide: true
                icon: "󰖳"
                label: "Windows 11 Stealth"
                onClicked: root.run(["/usr/local/bin/windows11-stealth-start", "--yes"])
            }
        }

        M3Section {
            title: "MOUSE"

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                M3IconButton {
                    icon: root.mouseIcon
                    active: root.mouseOk && root.mousePct > 20
                    danger: root.mouseOk && root.mousePct >= 0 && root.mousePct <= 20
                    onClicked: root.openMouseXpanel()
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: "Mouse"
                        color: "#ffffff"
                        font.pixelSize: 13
                        font.family: Theme.fontFamily
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        text: root.mouseSubtitle
                        color: (!root.mouseOk || (root.mousePct >= 0 && root.mousePct <= 20))
                            ? "#ffb4a8"
                            : Qt.rgba(1, 1, 1, 0.55)
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        font.family: Theme.fontFamily
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }
        }

        M3Section {
            title: "SESSION"

            M3IconButton {
                Layout.fillWidth: true
                wide: true
                icon: "󰌾"
                label: "Lock Screen"
                onClicked: {
                    Globals.powerOpen = false
                    Globals.lockSession()
                }
            }

            M3IconButton {
                Layout.fillWidth: true
                wide: true
                icon: "󰤄"
                label: "Suspend"
                onClicked: root.run(["systemctl", "suspend"])
            }

            M3IconButton {
                Layout.fillWidth: true
                wide: true
                icon: "󰜉"
                label: "Reboot"
                onClicked: root.run(["systemctl", "reboot"])
            }

            M3IconButton {
                Layout.fillWidth: true
                wide: true
                icon: "󰐥"
                label: root.shutDownArmed ? "Confirm Shut Down?" : "Shut Down"
                danger: true
                onClicked: {
                    if (root.shutDownArmed)
                        root.run(["systemctl", "poweroff"])
                    else
                        root.shutDownArmed = true
                }
            }

            M3IconButton {
                Layout.fillWidth: true
                wide: true
                icon: "󰍃"
                label: "Log Out"
                onClicked: root.run(["hyprctl", "dispatch", "exit"])
            }
        }
    }
}
