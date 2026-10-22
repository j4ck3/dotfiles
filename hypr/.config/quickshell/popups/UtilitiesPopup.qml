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
    property bool netbirdOk: false
    property bool netbirdConnected: false
    property string netbirdIp: ""
    property string netbirdHost: ""
    property int netbirdPeersConnected: 0
    property int netbirdPeersTotal: 0
    property string netbirdRelays: "0/0"
    property string netbirdError: ""
    property bool cardHovering: false

    function closeAndRun(cmd: var): void {
        Quickshell.execDetached(cmd)
        Globals.utilitiesOpen = false
    }

    function refreshStatus(): void {
        otpStatusProc.running = true
        netbirdStatusProc.running = true
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

    readonly property string otpSubtitle: {
        if (root.otpError.length && !root.otpWatching) return root.otpError
        if (root.otpWatching)
            return "Watching · 2s" + (root.otpArmedLeft > 0 ? " · " + root.otpArmedLeft + "s" : "")
        if (root.otpHasChip && root.otpCode.length) return "Last: " + root.otpCode
        return "Idle"
    }

    Process {
        id: otpStatusProc
        command: [Globals.scriptsDir + "/otp-watch.sh", "status"]
        stdout: StdioCollector { onStreamFinished: { try { const d = JSON.parse(text.trim()); root.otpOk = d.ok !== false; root.otpWatching = !!d.watching || d.mode === "armed"; root.otpCode = d.code || ""; root.otpError = d.error || ""; root.otpArmedLeft = d.armed_left ?? 0; root.otpHasChip = !!d.has_chip } catch (e) {} } }
    }
    Process {
        id: netbirdStatusProc
        command: [Globals.scriptsDir + "/netbird-status.sh", "status"]
        stdout: StdioCollector { onStreamFinished: { try { const d = JSON.parse(text.trim()); root.netbirdOk = !!d.ok; root.netbirdConnected = !!d.connected; root.netbirdIp = d.ip || ""; root.netbirdHost = d.host || ""; root.netbirdPeersConnected = d.peers_connected ?? 0; root.netbirdPeersTotal = d.peers_total ?? 0; root.netbirdRelays = d.relays || "0/0"; root.netbirdError = d.error || "" } catch (e) {} } }
    }

    Timer { id: statusRefreshTimer; interval: 120; onTriggered: root.refreshStatus() }
    Timer { interval: 1000; running: root.visible; repeat: true; triggeredOnStart: true; onTriggered: root.refreshStatus() }
    onVisibleChanged: {
        if (visible) {
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
        onCardHover: inside => {
            root.cardHovering = inside
            Globals.setUtilitiesHover(inside || volumeControls.sliderDragging)
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: 26
            z: 10

            Rectangle {
                id: vpnBadge
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 36
                height: 20
                radius: 5
                color: vpnHover.containsMouse ? "#18ffffff" : "transparent"
                border.width: 1
                border.color: root.netbirdConnected ? "#ddffffff" : "#88ffffff"
                opacity: root.netbirdConnected ? 1 : 0.55
                Text {
                    anchors.centerIn: parent
                    text: "VPN"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    color: "#ffffff"
                }
                MouseArea {
                    id: vpnHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleNetbird()
                }
            }

            Rectangle {
                anchors.top: vpnBadge.bottom
                anchors.topMargin: 6
                anchors.left: parent.left
                width: parent.width
                height: vpnInfo.implicitHeight + 20
                visible: vpnHover.containsMouse
                radius: 10
                color: "#f02b2935"
                border.width: 1
                border.color: "#30ffffff"
                Text {
                    id: vpnInfo
                    anchors.fill: parent
                    anchors.margins: 10
                    text: "Netbird · " + (!root.netbirdOk ? "Unavailable" : root.netbirdConnected ? "Connected" : "Disconnected")
                        + (root.netbirdHost.length ? "\n" + root.netbirdHost : "")
                        + "\n" + root.netbirdSubtitle
                        + "\nClick to " + (root.netbirdConnected ? "disconnect" : "connect")
                    wrapMode: Text.Wrap
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: "#ffffff"
                }
            }
        }

        VolumeControls {
            id: volumeControls
            Layout.fillWidth: true
            onDragStateChanged: dragging => Globals.setUtilitiesHover(dragging || root.cardHovering)
            onSettingsOpened: Globals.utilitiesOpen = false
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
