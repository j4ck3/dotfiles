import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import ".."

// Centered 600×150 Handy dictation overlay — voice-gated waveform (REC) / pulse (TX).
PanelWindow {
    id: root
    visible: Globals.dictationOpen
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    screen: Globals.focusedScreen()

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    WlrLayershell.namespace: "qs-dictation"
    WlrLayershell.layer: WlrLayer.Overlay
    // NEVER take keyboard focus: focus churn on show/hide crashed Chromium
    // (Helium SIGTRAP, Wayland text-input). Esc handled by global Hypr bind.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    mask: Region {
        item: card
    }

    readonly property int cardW: 600
    readonly property int cardH: 150
    readonly property int barCount: 48
    readonly property bool isRec: Globals.dictationPhase === "rec"
    readonly property bool isTx: Globals.dictationPhase === "tx"

    property real txPhase: 0

    Timer {
        interval: 16
        running: root.isTx
        repeat: true
        onTriggered: root.txPhase = (root.txPhase + 0.045) % 1
    }

    function barLevel(index: int): real {
        if (root.isTx)
            return root.txLevel(index)
        return Globals.waveLevels[index] || 0.06
    }

    function barHeight(index: int): real {
        return Math.max(6, root.barLevel(index) * (waveRow.height - 8))
    }

    function barColor(index: int): color {
        if (root.isTx) {
            const lv = root.txLevel(index)
            return Qt.rgba(1, 1, 1, 0.28 + lv * 0.55)
        }
        const lv = root.barLevel(index)
        if (lv > 0.78)
            return Qt.rgba(1, 0.38, 0.38, 1)
        if (lv > 0.48)
            return Qt.rgba(1, 0.68, 0.52, 0.96)
        if (lv > 0.28)
            return Qt.rgba(1, 0.92, 0.82, 0.88)
        return Qt.rgba(1, 1, 1, 0.38 + lv * 0.5)
    }

    function txLevel(index: int): real {
        const t = root.txPhase * Math.PI * 2
        const x = index / Math.max(1, root.barCount - 1)
        const wave = Math.sin(x * Math.PI * 5 - t) * 0.5 + 0.5
        const ripple = Math.sin(x * Math.PI * 2 + t * 0.7) * 0.18 + 0.82
        return 0.14 + wave * ripple * 0.42
    }

    Item {
        anchors.fill: parent

        Rectangle {
            id: card
            width: root.cardW
            height: root.cardH
            anchors.centerIn: parent
            radius: 18
            color: "#111111"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.14)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        width: 7
                        height: 7
                        radius: 3.5
                        color: root.isTx ? Theme.primary : "#ff6b6b"
                        opacity: root.isRec ? recPulse.opacity : 1

                        SequentialAnimation on opacity {
                            id: recPulse
                            running: root.isRec
                            loops: Animation.Infinite
                            NumberAnimation { from: 1; to: 0.35; duration: 700; easing.type: Easing.InOutSine }
                            NumberAnimation { from: 0.35; to: 1; duration: 700; easing.type: Easing.InOutSine }
                        }
                    }

                    Text {
                        text: root.isTx ? "TRANSCRIBING" : "RECORDING"
                        color: root.isTx ? Theme.primary : "#ff6b6b"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1.2
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: "Super+V · Esc"
                        color: Theme.inkMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        opacity: 0.7
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Row {
                        id: waveRow
                        anchors.fill: parent
                        spacing: 3

                        Repeater {
                            model: root.barCount

                            Rectangle {
                                required property int index
                                width: Math.max(3, (waveRow.width - (root.barCount - 1) * waveRow.spacing) / root.barCount)
                                anchors.bottom: parent.bottom
                                height: root.barHeight(index)
                                radius: width / 2
                                gradient: Gradient {
                                    orientation: Gradient.Vertical
                                    GradientStop { position: 0; color: root.barColor(index) }
                                    GradientStop {
                                        position: 1
                                        color: {
                                            const c = root.barColor(index)
                                            return Qt.rgba(c.r, c.g, c.b, c.a * 0.55)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
