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
            root.refreshStatus()
            card.playIn()
        } else {
            card.resetOut()
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: Globals.powerOpen = false
    }

    component SlideAction: Rectangle {
        id: action
        property string icon
        property string label
        property bool danger: false
        signal confirmed()
        Layout.fillWidth: true
        implicitHeight: 46
        radius: height / 2
        color: "#22ffffff"
        readonly property real travel: Math.max(1, width - thumb.width - 8)

        Text {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: 18
            text: action.label
            font.family: Theme.fontFamily
            font.pixelSize: 13
            color: "#ddffffff"
            opacity: 1 - thumb.x / action.travel
        }

        Rectangle {
            id: thumb
            x: 4
            y: 4
            width: 38
            height: 38
            radius: 19
            color: action.danger ? "#ff453a" : "#e6ffffff"
            Text {
                anchors.centerIn: parent
                text: action.icon
                font.family: Theme.fontFamily
                font.pixelSize: 20
                color: action.danger ? "white" : "#303038"
            }
            MouseArea {
                id: swipe
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                drag.target: thumb
                drag.axis: Drag.XAxis
                drag.minimumX: 4
                drag.maximumX: 4 + action.travel
                property bool holding: false
                onPressed: {
                    reset.stop()
                    holding = true
                    root.beginSliderDrag()
                }
                function finish(commit) {
                    if (!holding)
                        return
                    holding = false
                    const complete = commit && thumb.x >= 4 + action.travel * 0.95
                    reset.restart()
                    root.endSliderDrag()
                    if (complete)
                        action.confirmed()
                }
                onReleased: finish(true)
                onCanceled: finish(false)
            }
        }
        NumberAnimation {
            id: reset
            target: thumb
            property: "x"
            to: 4
            duration: 180
            easing.type: Easing.OutCubic
        }
        Connections {
            target: root
            function onVisibleChanged() {
                if (!root.visible) {
                    swipe.finish(false)
                    reset.stop()
                    thumb.x = 4
                }
            }
        }
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

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 42
                radius: 12
                color: "#22000000"
                enabled: root.fanOk
                opacity: enabled ? 1 : 0.45

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 4
                    spacing: 3
                    Repeater {
                        model: ["Auto", "Quiet", "Max"]
                        Rectangle {
                            id: segment
                            required property int index
                            required property string modelData
                            readonly property bool selected: root.fanOk && (
                                index === 0 ? !root.fanOverride :
                                root.fanOverride && (index === 1 ? root.fanDuty <= 25 : root.fanDuty >= 95))
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 9
                            color: selected ? "#e6ffffff" : presetMouse.containsMouse ? "#18ffffff" : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Text {
                                anchors.centerIn: parent
                                text: segment.modelData
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                color: segment.selected ? "#303038" : "#ddffffff"
                            }
                            MouseArea {
                                id: presetMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (segment.index === 0) root.restoreFanAuto()
                                    else if (segment.index === 1) root.setFanQuiet()
                                    else root.setFanMax()
                                }
                            }
                        }
                    }
                }
            }
        }

        M3Section {
            title: "VIRTUAL MACHINES"

            SlideAction {
                Layout.fillWidth: true
                icon: "󰖳"
                label: "Windows 11"
                // Direct exec — xdg-terminal-exec + setsid race kills start when PTY closes.
                onConfirmed: root.run(["/usr/local/bin/windows11-start", "--yes"])
            }

            SlideAction {
                Layout.fillWidth: true
                icon: "󰖳"
                label: "Windows 11 Stealth"
                onConfirmed: root.run(["/usr/local/bin/windows11-stealth-start", "--yes"])
            }
        }

        M3Section {
            title: "SESSION"

            SlideAction {
                Layout.fillWidth: true
                icon: "󰌾"
                label: "Lock Screen"
                onConfirmed: {
                    Globals.powerOpen = false
                    Globals.lockSession()
                }
            }

            SlideAction {
                Layout.fillWidth: true
                icon: "󰤄"
                label: "Suspend"
                onConfirmed: root.run([Globals.sessionActionScript, "suspend"])
            }

            SlideAction {
                Layout.fillWidth: true
                icon: "󰜉"
                label: "Reboot"
                onConfirmed: root.run([Globals.sessionActionScript, "reboot"])
            }

            SlideAction {
                Layout.fillWidth: true
                icon: "󰐥"
                label: "Shut Down"
                danger: true
                onConfirmed: root.run([Globals.sessionActionScript, "poweroff"])
            }

            SlideAction {
                Layout.fillWidth: true
                icon: "󰍃"
                label: "Log Out"
                onConfirmed: root.run([Globals.sessionActionScript, "logout"])
            }
        }
    }
}
