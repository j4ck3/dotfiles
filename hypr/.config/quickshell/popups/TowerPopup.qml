import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import ".."

PanelWindow {
    id: root
    visible: Globals.towerOpen
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

    WlrLayershell.namespace: "qs-tower"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    readonly property int cardW: 340
    // NOTE: must not be named "data" — that shadows the window's default
    // content property and children never get parented into the scene.
    property var info: ({})
    property bool cardHovering: false

    function applyPayload(raw: string): void {
        const t = raw.trim()
        if (!t.length)
            return
        try {
            root.info = JSON.parse(t)
        } catch (e) {
            root.info = { ok: false, status: "offline" }
        }
    }

    function refresh(): void {
        towerProc.running = true
    }

    Process {
        id: towerProc
        command: [Globals.scriptsDir + "/tower-status.sh"]
        stdout: StdioCollector {
            onStreamFinished: root.applyPayload(text)
        }
    }

    Timer {
        interval: 3000
        running: root.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    onVisibleChanged: {
        if (visible) {
            root.refresh()
            card.playIn()
        } else {
            card.resetOut()
        }
    }


    MouseArea {
        anchors.fill: parent
        z: 0
        onClicked: Globals.towerOpen = false
    }

    Item {
        id: card
        z: 1
        anchors.top: Theme.barVertical ? undefined : parent.top
        anchors.bottom: Theme.barVertical ? parent.bottom : undefined
        anchors.left: Theme.barVertical ? parent.left : undefined
        anchors.right: Theme.barVertical ? undefined : parent.right
        anchors.topMargin: Theme.barVertical ? 0 : Theme.widgetTopGap
        anchors.bottomMargin: Theme.barVertical ? Theme.widgetTopGap : 0
        anchors.leftMargin: Theme.barVertical ? Globals.towerPopupRightMargin : 0
        anchors.rightMargin: Theme.barVertical ? 0 : Globals.towerPopupRightMargin
        width: root.cardW
        implicitHeight: inner.implicitHeight + 28
        height: implicitHeight

        property real slideY: 0
        property real slideX: 0
        opacity: 0
        transform: Translate {
            x: card.slideX
            y: card.slideY
        }

        HoverHandler {
            onHoveredChanged: {
                root.cardHovering = hovered
                Globals.setTowerHover(hovered)
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        ParallelAnimation {
            id: inAnim
            NumberAnimation {
                target: card
                property: Theme.barVertical ? "slideX" : "slideY"
                from: -20
                to: 0
                duration: 170
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: card
                property: "opacity"
                from: 0
                to: 1
                duration: 150
                easing.type: Easing.OutCubic
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: 22
            color: Theme.popupSurface
            border.width: 1
            border.color: Theme.popupBorder
        }

        ColumnLayout {
            id: inner
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: identityRows.implicitHeight + 20
                radius: 14
                color: Theme.popupTile
                border.width: 1
                border.color: Theme.popupBorder

                ColumnLayout {
                    id: identityRows
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            Layout.fillWidth: true
                            text: "Status"
                            color: Theme.popupMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                        Text {
                            text: root.info.ok ? (root.info.status || "online") : "offline"
                            color: (root.info.alarms_crit || 0) > 0 ? Theme.error : Theme.popupText
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: !!(root.info.host && root.info.host.length)
                        spacing: 8
                        Text {
                            Layout.fillWidth: true
                            text: "Host"
                            color: Theme.popupMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                        Text {
                            text: root.info.host || ""
                            color: Theme.popupText
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: metricRows.implicitHeight + 20
                radius: 14
                color: Theme.popupTile
                border.width: 1
                border.color: Theme.popupBorder

                ColumnLayout {
                    id: metricRows
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            Layout.fillWidth: true
                            text: "CPU"
                            color: Theme.popupMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                        Text {
                            text: root.info.ok
                                ? (root.info.cpu + "% · " + (root.info.cores || "?") + " cores")
                                : "--"
                            color: (root.info.cpu || 0) > 90 ? Theme.alert : Theme.popupText
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            Layout.fillWidth: true
                            text: "RAM"
                            color: Theme.popupMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                        Text {
                            text: root.info.ok
                                ? (root.info.ram_used_g + " / " + root.info.ram_total_g + " G · " + root.info.ram_pct + "%")
                                : "--"
                            color: (root.info.ram_pct || 0) > 90 ? Theme.alert : Theme.popupText
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            Layout.fillWidth: true
                            text: "Storage"
                            color: Theme.popupMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                        Text {
                            text: root.info.ok && root.info.storage_total !== "--"
                                ? (root.info.storage_used + " / " + root.info.storage_total + " · " + root.info.storage_pct + "%")
                                : "--"
                            color: (root.info.storage_pct || 0) > 90 ? Theme.alert : Theme.popupText
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            Layout.fillWidth: true
                            text: "Load"
                            color: Theme.popupMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                        Text {
                            text: root.info.ok
                                ? (root.info.load1 + " · " + root.info.load5 + " · " + root.info.load15)
                                : "--"
                            color: Theme.popupText
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            Layout.fillWidth: true
                            text: "Net ↓"
                            color: Theme.popupMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                        Text {
                            text: root.info.ok ? (root.info.net_rx || "--") : "--"
                            color: Theme.popupText
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            Layout.fillWidth: true
                            text: "Net ↑"
                            color: Theme.popupMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                        Text {
                            text: root.info.ok ? (root.info.net_tx || "--") : "--"
                            color: Theme.popupText
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            Layout.fillWidth: true
                            text: "Uptime"
                            color: Theme.popupMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                        Text {
                            text: root.info.ok ? (root.info.uptime || "--") : "--"
                            color: Theme.popupText
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: processRows.implicitHeight + 20
                visible: !!(root.info.ok && (root.info.top_ram || []).length > 0)
                radius: 14
                color: Theme.popupTile
                border.width: 1
                border.color: Theme.popupBorder

                ColumnLayout {
                    id: processRows
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8
                    Repeater {
                        model: root.info.ok ? (root.info.top_ram || []) : []

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            required property var modelData
                            Text {
                                Layout.fillWidth: true
                                text: modelData.name || "?"
                                color: Theme.popupMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                            Text {
                                text: modelData.ram || "--"
                                color: Theme.popupText
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.Medium
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: alarmRows.implicitHeight + 20
                visible: !!(root.info.ok && ((root.info.alarms_warn || 0) + (root.info.alarms_crit || 0) > 0))
                radius: 14
                color: Theme.popupTile
                border.width: 1
                border.color: Theme.popupBorder

                ColumnLayout {
                    id: alarmRows
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8
                    RowLayout {
                        Layout.fillWidth: true
                        visible: !!(root.info.ok && ((root.info.alarms_warn || 0) + (root.info.alarms_crit || 0) > 0))
                        spacing: 8
                        Text {
                            Layout.fillWidth: true
                            text: "Alarms"
                            color: Theme.popupMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                        Text {
                            text: (root.info.alarms_crit || 0) + " crit · " + (root.info.alarms_warn || 0) + " warn"
                            color: (root.info.alarms_crit || 0) > 0 ? Theme.error : Theme.popupText
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                    }
                }
            }
        }

        function playIn(): void {
            inAnim.stop()
            card.slideX = Theme.barVertical ? -20 : 0
            card.slideY = Theme.barVertical ? 0 : -20
            card.opacity = 0
            inAnim.restart()
        }

        function resetOut(): void {
            inAnim.stop()
            card.slideX = Theme.barVertical ? -20 : 0
            card.slideY = Theme.barVertical ? 0 : -20
            card.opacity = 0
        }

        Component.onCompleted: {
            card.slideX = Theme.barVertical ? -20 : 0
            card.slideY = Theme.barVertical ? 0 : -20
            card.opacity = 0
        }
    }
}
