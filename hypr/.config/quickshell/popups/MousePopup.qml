import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import ".."

// UltralightX mouse: battery readout + polling-rate picker. Opens while the
// pointer is on the bar's MOUSE stat (Globals.setMouseHover).
PanelWindow {
    id: root
    visible: Globals.mouseOpen
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    anchors { top: true; left: true; right: true; bottom: true }
    margins { top: Theme.popupTopInset; left: Theme.popupLeftInset }

    WlrLayershell.namespace: "qs-mouse"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    readonly property int cardW: 280
    readonly property var batt: Globals.mouseBattery || ({ ok: false })

    property bool pollOk: false
    property int pollHz: 0
    property int pollMax: 4000
    property int pollPending: 0
    property string pollError: ""

    function applyPolling(d: var): void {
        root.pollOk = !!d.ok
        root.pollHz = d.hz ?? 0
        root.pollMax = d.max ?? 4000
        root.pollError = d.error || ""
        root.pollPending = 0
    }

    function setPolling(hz: int): void {
        if (pollSetProc.running || hz === root.pollHz) return
        root.pollPending = hz
        pollSetProc.command = [Globals.scriptsDir + "/ulx-polling.py", "set", String(hz)]
        pollSetProc.running = true
    }

    Process {
        id: pollStatusProc
        command: [Globals.scriptsDir + "/ulx-polling.py"]
        stdout: StdioCollector { onStreamFinished: { try { root.applyPolling(JSON.parse(text.trim())) } catch (e) { root.applyPolling({ ok: false, error: "Polling unavailable" }) } } }
    }

    Process {
        id: pollSetProc
        stdout: StdioCollector { onStreamFinished: { try { root.applyPolling(JSON.parse(text.trim())) } catch (e) { root.applyPolling({ ok: false, error: "Set failed" }) } } }
    }

    readonly property string battTitle: {
        if (!root.batt.ok) return "Mouse"
        return root.batt.display || (root.batt.pct >= 0 ? root.batt.pct + "%" : "--")
    }

    readonly property string battSubtitle: {
        if (!root.batt.ok)
            return root.batt.error && root.batt.error !== "offline" ? root.batt.error : "No dongle"
        const bits = ["UltralightX"]
        if (root.batt.mv > 0) bits.push((root.batt.mv / 1000).toFixed(2) + "V")
        if (root.batt.charging) bits.push("charging")
        return bits.join(" · ")
    }

    readonly property string battIcon: {
        if (!root.batt.ok || root.batt.pct < 0) return "󰍽"
        if (root.batt.charging) return "󰂄"
        const icons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
        return icons[Math.min(icons.length - 1, Math.max(0, Math.floor(root.batt.pct / 10)))]
    }

    readonly property string pollSubtitle: {
        if (root.pollPending > 0) return "Setting " + root.pollPending + " Hz…"
        if (!root.pollOk) return root.pollError === "offline" ? "No dongle" : (root.pollError || "Reading…")
        return root.pollError.length ? root.pollError : root.pollHz + " Hz"
    }

    onVisibleChanged: {
        if (visible) {
            if (!pollStatusProc.running && !pollSetProc.running) pollStatusProc.running = true
            card.playIn()
        } else card.resetOut()
    }

    MouseArea { anchors.fill: parent; onClicked: Globals.closeAll() }

    PopupCard {
        id: card
        anchors.fill: parent
        cardWidth: root.cardW
        // Vertical bar: card centered beside the MOUSE stat, kept on screen.
        topMargin: Theme.barVertical
            ? Math.max(Theme.widgetTopGap, Math.min(
                Math.round(Globals.mousePopupAnchorY - card.cardHeight / 2),
                root.height - card.cardHeight - Theme.widgetTopGap))
            : Theme.widgetTopGap
        rightMargin: Theme.barVertical ? Theme.widgetTopGap : Globals.mousePopupRightMargin
        animateIn: true
        compact: true
        onClosed: Globals.mouseOpen = false
        onCardHover: inside => Globals.setMouseHover(inside)

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            M3IconButton {
                icon: root.battIcon
                active: !!root.batt.charging
                onClicked: Quickshell.execDetached(["xdg-open", "https://xpanel.finalmouse.com/overview"])
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    text: root.battTitle
                    color: root.batt.ok && root.batt.pct >= 0 && root.batt.pct <= 15 ? Theme.error : Theme.popupText
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
                Text {
                    text: root.battSubtitle
                    color: Theme.popupMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
        }

        M3Section {
            compact: true

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    text: "Polling rate"
                    color: Theme.popupMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    Layout.fillWidth: true
                }
                Text {
                    text: root.pollSubtitle
                    color: Theme.popupText
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.Medium
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: [500, 1000, 2000, 4000, 8000]
                    Rectangle {
                        id: rateBtn
                        required property int modelData
                        readonly property bool current: root.pollOk && root.pollHz === modelData
                        readonly property bool pending: root.pollPending === modelData
                        readonly property bool usable: root.pollOk && modelData <= root.pollMax
                        Layout.fillWidth: true
                        implicitHeight: 28
                        radius: 9
                        opacity: usable ? 1 : 0.35
                        color: current ? Theme.popupAccent
                            : pending ? Qt.rgba(0.2, 0.6, 1, 0.35)
                            : rateMouse.containsMouse && usable ? Theme.hoverStrong
                            : Qt.rgba(1, 1, 1, 0.10)
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        scale: rateMouse.pressed && usable ? 0.96 : 1
                        Text {
                            anchors.centerIn: parent
                            text: rateBtn.modelData >= 1000 ? (rateBtn.modelData / 1000) + "K" : String(rateBtn.modelData)
                            color: Theme.popupText
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.Medium
                        }
                        MouseArea {
                            id: rateMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: rateBtn.usable
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setPolling(rateBtn.modelData)
                        }
                    }
                }
            }
        }
    }
}
