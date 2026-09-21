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
    property bool fanOk: false
    property bool fanOverride: false
    property int fanDuty: 0
    property int fanRpm: 0
    // Optimistic duty while CoolerControl catches up (-1 = trust polls).
    property int fanPendingDuty: -1
    property int sliderDragCount: 0
    readonly property bool sliderDragging: sliderDragCount > 0
    property bool cardHovering: false
    property var pendingFanArgs: []

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
            fanControlDebounce.stop()
            root.flushFanControl()
            statusRefreshTimer.restart()
            if (!root.cardHovering)
                Globals.setPowerHover(false)
        }
    }

    function refreshStatus(): void {
        if (root.sliderDragging)
            return
        fanStatusProc.running = true
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

    Timer {
        id: fanControlDebounce
        interval: 50
        onTriggered: root.flushFanControl()
    }

    Timer {
        id: fanPollHold
        interval: 400
        repeat: false
    }

    Timer {
        id: fanOptimisticTimeout
        interval: 3000
        onTriggered: root.fanPendingDuty = -1
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
