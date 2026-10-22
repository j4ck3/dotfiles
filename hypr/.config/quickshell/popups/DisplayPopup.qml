import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import ".."

PanelWindow {
    id: root
    visible: Globals.displayOpen
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

    WlrLayershell.namespace: "qs-display"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    property int gamma: 100
    property int temp: 6500
    property bool identity: true
    property int sliderDragCount: 0
    readonly property bool sliderDragging: sliderDragCount > 0
    property bool cardHovering: false
    property var pendingArgs: []
    property bool lightOn: false
    property int lightBrightness: 0
    property real lightHue: 0
    property real lightSat: 100
    property string lightName: "Gaming light"
    property bool lightOk: false
    // Optimistic brightness while HA/LIFX catch up (-1 = trust polls).
    property int lightPendingBrightness: -1
    property bool lightColorPending: false
    property var pendingHaArgs: []
    property bool keyOptimistic: false
    property bool awaitingKeyStatus: false
    property int pendingBrightnessDelta: 0
    property int pendingWarmthDelta: 0

    readonly property int warmthUi: {
        if (root.identity || root.temp >= 6500)
            return 0
        return Math.round(((6500 - root.temp) / (6500 - 2500)) * 100)
    }

    function beginSliderDrag(): void {
        root.sliderDragCount++
        Globals.setDisplayCardHover(true)
    }

    function endSliderDrag(): void {
        root.sliderDragCount = Math.max(0, root.sliderDragCount - 1)
        if (root.sliderDragCount === 0) {
            debounce.stop()
            haControlDebounce.stop()
            root.flushControl()
            root.flushHaControl()
            statusRefreshTimer.restart()
            if (!root.cardHovering)
                Globals.setDisplayCardHover(false)
        }
    }

    function refreshStatus(): void {
        if (root.sliderDragging)
            return
        statusProc.running = true
        if (!lightSlider.pressed && !hueWheel.pressed)
            haStatusProc.running = true
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
        debounce.restart()
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

    // Keyboard steering (Hyprland F1-F4 binds → qs ipc call display …).
    // Update slider/text immediately, then commit after the popup has rendered.
    // Ignore stale status polls until the backend has had time to settle.
    function applyOptimisticKeyStep(kind: string, delta: int): void {
        root.keyOptimistic = true
        optimisticRelease.stop()
        keyPopupClose.stop()

        if (kind === "brightness") {
            root.gamma = Math.max(10, Math.min(100, root.gamma + delta))
            brightnessKeyDelay.restart()
            return
        }

        const w = Math.max(0, Math.min(100, root.warmthUi + delta))
        if (w <= 0) {
            root.identity = true
            root.temp = 6500
        } else {
            root.identity = false
            root.temp = root.warmthToTemp(w)
        }
        warmthKeyDelay.restart()
    }

    function applyPendingKeySteps(): void {
        root.awaitingKeyStatus = false
        if (root.pendingBrightnessDelta !== 0) {
            const delta = root.pendingBrightnessDelta
            root.pendingBrightnessDelta = 0
            root.applyOptimisticKeyStep("brightness", delta)
        }
        if (root.pendingWarmthDelta !== 0) {
            const delta = root.pendingWarmthDelta
            root.pendingWarmthDelta = 0
            root.applyOptimisticKeyStep("warmth", delta)
        }
    }

    function queueKeyStep(kind: string, delta: int): void {
        const wasVisible = root.visible
        Globals.setDisplayPinned(true)

        if (!wasVisible || root.awaitingKeyStatus) {
            if (kind === "brightness")
                root.pendingBrightnessDelta += delta
            else
                root.pendingWarmthDelta += delta
            if (!root.awaitingKeyStatus) {
                root.awaitingKeyStatus = true
                root.refreshStatus()
            }
            return
        }

        root.applyOptimisticKeyStep(kind, delta)
    }

    function finishKeyCommit(): void {
        statusRefreshTimer.restart()
        optimisticRelease.restart()
        keyPopupClose.restart()
    }

    Timer {
        id: brightnessKeyDelay
        // Popup entrance animation is 160ms; wait for a fully opaque frame.
        interval: 240
        onTriggered: {
            Quickshell.execDetached([
                Globals.scriptsDir + "/display-control.sh",
                "gamma",
                String(root.gamma)
            ])
            root.finishKeyCommit()
        }
    }

    Timer {
        id: warmthKeyDelay
        interval: 240
        onTriggered: {
            const args = root.identity
                ? ["identity"]
                : ["temp", String(root.temp)]
            Quickshell.execDetached([Globals.scriptsDir + "/display-control.sh"].concat(args))
            root.finishKeyCommit()
        }
    }

    Timer {
        id: optimisticRelease
        interval: 320
        onTriggered: {
            root.keyOptimistic = false
            root.refreshStatus()
        }
    }

    Timer {
        id: keyPopupClose
        interval: 700
        onTriggered: Globals.setDisplayPinned(false)
    }

    IpcHandler {
        target: "display"

        function brightnessUp(): void { root.queueKeyStep("brightness", 5) }
        function brightnessDown(): void { root.queueKeyStep("brightness", -5) }
        // filterUp = warmer screen (more blue light filtered), filterDown = cooler.
        function filterUp(): void { root.queueKeyStep("warmth", 10) }
        function filterDown(): void { root.queueKeyStep("warmth", -10) }
    }

    Process {
        id: statusProc
        command: [Globals.scriptsDir + "/display-status.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text.trim())
                    if (!gammaSlider.pressed && !root.keyOptimistic)
                        root.gamma = data.gamma ?? 100
                    if (!warmthSlider.pressed && !root.keyOptimistic) {
                        root.temp = data.temp ?? 6500
                        root.identity = !!data.identity
                    }
                    if (root.awaitingKeyStatus)
                        root.applyPendingKeySteps()
                } catch (e) {}
            }
        }
    }

    Timer {
        id: haControlDebounce
        interval: 50
        onTriggered: root.flushHaControl()
    }

    Timer {
        id: haPollHold
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

    Timer {
        id: debounce
        interval: 50
        onTriggered: root.flushControl()
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
            root.refreshStatus()
            card.playIn()
        } else {
            card.resetOut()
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: Globals.closeAll()
    }

    PopupCard {
        id: card
        anchors.fill: parent
        title: "Display"
        cardWidth: 300
        topMargin: Theme.widgetTopGap
        bottomMargin: Theme.widgetTopGap
        rightMargin: Globals.displayPopupRightMargin
        fromBottom: Theme.barVertical
        animateIn: true
        onClosed: Globals.closeAll()
        onCardHover: inside => {
            root.cardHovering = inside
            if (!inside && root.sliderDragging)
                return
            Globals.setDisplayCardHover(inside)
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            M3Slider {
                id: gammaSlider
                Layout.fillWidth: true
                Layout.preferredHeight: 144
                orientation: Qt.Vertical
                flatFillEdge: true
                Layout.leftMargin: 0
                from: 10
                to: 100
                fillColor: "#ffffff"
                trackColor: Qt.rgba(1, 1, 1, 0.18)
                trackHeight: 56
                handleSize: 24
                hitPad: 4
                showHandle: false

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 20
                    z: 3
                    text: "󰃠"
                    color: gammaSlider.position > 0.25 ? "#303038" : "#ffffff"
                    font.family: Theme.fontFamily
                    font.pixelSize: 24
                }

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

            M3Slider {
                id: lightSlider
                Layout.fillWidth: true
                Layout.preferredHeight: 144
                orientation: Qt.Vertical
                flatFillEdge: true
                Layout.leftMargin: 0
                from: 0
                to: 100
                fillColor: root.lightOn ? "#7dd3c0" : Qt.rgba(1, 1, 1, 0.45)
                trackColor: Qt.rgba(1, 1, 1, 0.18)
                trackHeight: 56
                handleSize: 24
                hitPad: 4
                showHandle: false
                opacity: root.lightOk ? 1 : 0.45

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 20
                    z: 3
                    text: "󰛨"
                    color: lightSlider.position > 0.25 ? "#303038" : "#ffffff"
                    font.family: Theme.fontFamily
                    font.pixelSize: 24
                }

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

            M3Slider {
                id: warmthSlider
                Layout.fillWidth: true
                Layout.preferredHeight: 144
                orientation: Qt.Vertical
                flatFillEdge: true
                Layout.leftMargin: 0
                from: 0
                to: 100
                fillColor: root.identity ? Qt.rgba(1, 1, 1, 0.45) : "#ffb86c"
                trackColor: Qt.rgba(1, 1, 1, 0.18)
                trackHeight: 56
                handleSize: 24
                hitPad: 4
                showHandle: false

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 20
                    z: 3
                    text: "󰖔"
                    color: warmthSlider.position > 0.25 ? "#303038" : "#ffffff"
                    font.family: Theme.fontFamily
                    font.pixelSize: 24
                }

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
}
