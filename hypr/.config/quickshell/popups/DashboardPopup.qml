import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import Quickshell.Services.Notifications
import ".."

PanelWindow {
    id: root
    visible: Globals.dashboardOpen
    color: "transparent"
    exclusiveZone: 0

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    WlrLayershell.namespace: "qs-dashboard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    property string query: ""
    property int calYear: new Date().getFullYear()
    property int calMonth: new Date().getMonth()

    readonly property var blockedIds: [
        "avahi-discover", "assistant", "designer", "linguist", "qdbusviewer",
        "bvnc", "bssh", "qt5ct", "qt6ct", "qv4l2", "qvidcap",
    ]

    readonly property var player: {
        const players = Mpris.players.values
        for (let i = 0; i < players.length; i++) {
            const p = players[i]
            const id = (p.desktopEntry || p.identity || "").toLowerCase()
            if (id.includes("spotify"))
                return p
        }
        return players.length ? players[0] : null
    }

    readonly property var daysShort: ["sön", "mån", "tis", "ons", "tor", "fre", "lör"]
    readonly property var monthsShort: [
        "jan", "feb", "mar", "apr", "maj", "jun",
        "jul", "aug", "sep", "okt", "nov", "dec",
    ]
    readonly property var monthsFull: [
        "januari", "februari", "mars", "april", "maj", "juni",
        "juli", "augusti", "september", "oktober", "november", "december",
    ]

    function close(): void {
        Globals.dashboardOpen = false
    }

    function pad(n: int): string {
        return n < 10 ? "0" + n : "" + n
    }

    function fmt(secs: real): string {
        const s = Math.max(0, Math.floor(secs))
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }

    function isoWeek(d: var): int {
        const tmp = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()))
        const yearStart = new Date(Date.UTC(tmp.getUTCFullYear(), 0, 1))
        return Math.ceil((((tmp - yearStart) / 86400000) + 1) / 7)
    }

    function isBlocked(entry: var): bool {
        const id = (entry.id || "").toLowerCase()
        const name = (entry.name || "").toLowerCase()
        if (root.blockedIds.indexOf(id) !== -1)
            return true
        if (id.includes("avahi") || id.includes("pinentry"))
            return true
        if (name.startsWith("qt ") || name.startsWith("avahi"))
            return true
        return false
    }

    function matchesEntry(entry: var, q: string): bool {
        if (root.isBlocked(entry))
            return false
        if (!q.length)
            return true
        let hay = `${entry.name ?? ""} ${entry.genericName ?? ""}`.toLowerCase()
        const kws = entry.keywords
        if (kws && kws.length) {
            for (let i = 0; i < kws.length; i++)
                hay += ` ${kws[i]}`
        }
        return hay.includes(q)
    }

    function launchSelected(): void {
        const item = appList.currentItem
        if (!item || !item.modelData)
            return
        item.modelData.execute()
        root.close()
    }

    function moveSelection(delta: int): void {
        if (appList.count <= 0)
            return
        const next = Math.max(0, Math.min(appList.count - 1, appList.currentIndex + delta))
        appList.currentIndex = next
        appList.positionViewAtIndex(next, ListView.Contain)
    }

    function shiftMonth(delta: int): void {
        let m = root.calMonth + delta
        let y = root.calYear
        while (m < 0) {
            m += 12
            y -= 1
        }
        while (m > 11) {
            m -= 12
            y += 1
        }
        root.calMonth = m
        root.calYear = y
    }

    readonly property var calendarCells: {
        const y = root.calYear
        const m = root.calMonth
        const first = new Date(y, m, 1)
        const startPad = first.getDay() // Sun=0
        const daysInMonth = new Date(y, m + 1, 0).getDate()
        const cells = []
        for (let i = 0; i < startPad; i++)
            cells.push({ day: 0, inMonth: false })
        for (let d = 1; d <= daysInMonth; d++)
            cells.push({ day: d, inMonth: true })
        while (cells.length % 7 !== 0)
            cells.push({ day: 0, inMonth: false })
        return cells
    }

    function isToday(day: int): bool {
        if (!day)
            return false
        const now = new Date()
        return now.getFullYear() === root.calYear
            && now.getMonth() === root.calMonth
            && now.getDate() === day
    }

    function relativeTime(ts: real): string {
        const sec = Math.max(0, Math.floor((Date.now() - ts) / 1000))
        if (sec < 60)
            return "nu"
        if (sec < 3600)
            return Math.floor(sec / 60) + "m"
        if (sec < 86400)
            return Math.floor(sec / 3600) + "h"
        return Math.floor(sec / 86400) + "d"
    }

    FrameAnimation {
        running: root.visible && !!root.player?.isPlaying
        onTriggered: root.player?.positionChanged()
    }

    // Close via Esc / scrim only — HyprlandFocusGrab fights Super-release open.
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            root.close()
            event.accepted = true
        }
    }

    // Scrim
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)
        opacity: root.visible ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Theme.animFast }
        }
        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(1120, parent.width - 48)
        height: Math.min(680, parent.height - 48)
        radius: 22
        color: "#000000"
        border.width: 1
        border.color: Theme.hairlineMuted
        scale: root.visible ? 1 : 0.98
        opacity: root.visible ? 1 : 0

        Behavior on scale {
            NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            NumberAnimation { duration: 60 }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 16

            // ── Left: clock + calendar + media ──
            ColumnLayout {
                Layout.preferredWidth: 300
                Layout.fillHeight: true
                spacing: 14

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        id: bigClock
                        text: "00:00"
                        color: Theme.ink
                        font.family: Theme.fontFamily
                        font.pixelSize: 56
                        font.weight: Font.Light
                        Layout.fillWidth: true
                    }

                    Text {
                        id: dateLine
                        text: ""
                        color: Theme.inkMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        Layout.fillWidth: true
                    }
                }

                Timer {
                    interval: 1000
                    running: root.visible
                    repeat: true
                    triggeredOnStart: true
                    onTriggered: {
                        const d = new Date()
                        bigClock.text = root.pad(d.getHours()) + ":" + root.pad(d.getMinutes())
                        dateLine.text = root.daysShort[d.getDay()] + " " + root.pad(d.getDate())
                            + " " + root.monthsShort[d.getMonth()]
                            + "  W" + root.isoWeek(d)
                    }
                }

                // Calendar
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: calCol.implicitHeight + 20
                    radius: 16
                    color: Theme.surfaceContainer

                    ColumnLayout {
                        id: calCol
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            margins: 12
                        }
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                text: "󰁍"
                                color: Theme.inkMuted
                                font.family: Theme.iconFontFallback
                                font.pixelSize: 16
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.shiftMonth(-1)
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: root.monthsFull[root.calMonth] + " " + root.calYear
                                color: Theme.ink
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.weight: Font.Medium
                            }

                            Text {
                                text: "󰁔"
                                color: Theme.inkMuted
                                font.family: Theme.iconFontFallback
                                font.pixelSize: 16
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.shiftMonth(1)
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Repeater {
                                model: ["s", "m", "t", "o", "t", "f", "l"]
                                Text {
                                    required property string modelData
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    text: modelData
                                    color: Theme.inkMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                }
                            }
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 7
                            rowSpacing: 2
                            columnSpacing: 2

                            Repeater {
                                model: root.calendarCells

                                Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 28
                                    radius: 8
                                    color: root.isToday(modelData.day)
                                         ? Theme.primary : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.day || ""
                                        color: root.isToday(modelData.day)
                                             ? Theme.primaryInk
                                             : (modelData.inMonth ? Theme.ink : "transparent")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        font.weight: root.isToday(modelData.day)
                                                   ? Font.DemiBold : Font.Normal
                                    }
                                }
                            }
                        }
                    }
                }

                // Media
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 16
                    color: Theme.surfaceContainer
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 10

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Rectangle {
                                Layout.preferredWidth: 56
                                Layout.preferredHeight: 56
                                radius: 12
                                color: Theme.surfaceContainerHigh

                                Image {
                                    id: dashArt
                                    anchors.fill: parent
                                    source: root.player?.trackArtUrl || ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    visible: status === Image.Ready
                                    layer.enabled: true
                                    layer.effect: MultiEffect {
                                        maskEnabled: true
                                        maskSource: dashArtMask
                                    }
                                }

                                Item {
                                    id: dashArtMask
                                    anchors.fill: parent
                                    layer.enabled: true
                                    visible: false
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 12
                                        color: "#ffffff"
                                    }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: !dashArt.visible
                                    text: "󰝚"
                                    color: Theme.tertiary
                                    font.family: Theme.iconFontFallback
                                    font.pixelSize: 22
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    Layout.fillWidth: true
                                    text: root.player?.trackTitle || "Nothing Playing"
                                    color: Theme.ink
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                    maximumLineCount: 2
                                    wrapMode: Text.Wrap
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: root.player?.trackArtist || ""
                                    color: Theme.inkMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: root.fmt(dashSeek.pressed ? dashSeek.value : (root.player?.position || 0))
                                color: Theme.inkMuted
                                font.pixelSize: 10
                                font.family: Theme.fontFamily
                            }

                            M3Slider {
                                id: dashSeek
                                Layout.fillWidth: true
                                from: 0
                                to: Math.max(1, root.player?.length || 1)
                                fillColor: "#ffffff"
                                trackColor: Qt.rgba(1, 1, 1, 0.18)
                                trackHeight: 5
                                showHandle: false

                                Binding {
                                    target: dashSeek
                                    property: "value"
                                    value: root.player?.position || 0
                                    when: !dashSeek.pressed
                                    restoreMode: Binding.RestoreNone
                                }

                                onMoved: {
                                    if (root.player && pressed)
                                        root.player.position = value
                                }
                                onPressedChanged: {
                                    if (!pressed && root.player)
                                        root.player.position = value
                                }
                            }

                            Text {
                                text: root.fmt(root.player?.length || 0)
                                color: Theme.inkMuted
                                font.pixelSize: 10
                                font.family: Theme.fontFamily
                            }
                        }

                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 12

                            M3IconButton {
                                icon: "󰒮"
                                onClicked: root.player?.previous()
                            }
                            M3IconButton {
                                icon: root.player?.isPlaying ? "󰏤" : "󰐊"
                                active: true
                                onClicked: root.player?.togglePlaying()
                            }
                            M3IconButton {
                                icon: "󰒭"
                                onClicked: root.player?.next()
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }
                }
            }

            // ── Center: app search ──
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    radius: 22
                    color: Theme.surfaceContainer

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 10
                        spacing: 8

                        Text {
                            text: "󰍉"
                            color: Theme.primary
                            font.family: Theme.iconFontFallback
                            font.pixelSize: 18
                        }

                        TextField {
                            id: search
                            Layout.fillWidth: true
                            placeholderText: "Search apps…"
                            color: Theme.ink
                            placeholderTextColor: Theme.inkMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: 15
                            background: Item {}
                            selectByMouse: true

                            onTextChanged: {
                                root.query = text.trim().toLowerCase()
                                appList.currentIndex = filtered.values.length > 0 ? 0 : -1
                            }

                            Keys.onPressed: event => {
                                const ctrl = event.modifiers & Qt.ControlModifier
                                if (event.key === Qt.Key_Escape) {
                                    root.close()
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J || (ctrl && event.key === Qt.Key_N)) {
                                    root.moveSelection(1)
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K || (ctrl && event.key === Qt.Key_P)) {
                                    root.moveSelection(-1)
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    root.launchSelected()
                                    event.accepted = true
                                }
                            }
                        }
                    }
                }

                ListView {
                    id: appList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    keyNavigationWraps: false
                    highlightMoveDuration: 80
                    currentIndex: filtered.values.length > 0 ? 0 : -1

                    model: ScriptModel {
                        id: filtered
                        values: {
                            const all = [...DesktopEntries.applications.values].filter(d => !root.isBlocked(d))
                            const q = root.query
                            const matched = q.length
                                ? all.filter(d => root.matchesEntry(d, q))
                                : all
                            return matched.sort((a, b) => (a.name || "").localeCompare(b.name || ""))
                        }
                    }

                    highlight: Rectangle {
                        radius: Theme.pillRadius
                        color: Theme.primaryContainer
                    }

                    delegate: Item {
                        id: entry
                        required property var modelData
                        required property int index
                        width: ListView.view.width
                        height: 44
                        z: 1

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.pillRadius
                            color: entryMouse.containsMouse && appList.currentIndex !== entry.index
                                 ? Theme.hover : "transparent"
                        }

                        MouseArea {
                            id: entryMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: appList.currentIndex = entry.index
                            onDoubleClicked: root.launchSelected()
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 12

                            IconImage {
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                source: {
                                    const icon = modelData.icon || ""
                                    if (!icon.length)
                                        return Quickshell.iconPath("application-x-executable", "application-x-executable")
                                    return Quickshell.iconPath(icon, "application-x-executable")
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: modelData.name || modelData.id || ""
                                color: Theme.ink
                                font.family: Theme.fontFamily
                                font.pixelSize: 14
                                elide: Text.ElideRight
                                verticalAlignment: Text.AlignVCenter
                            }

                            Text {
                                visible: !!(modelData.genericName && modelData.genericName.length)
                                text: modelData.genericName || ""
                                color: Theme.inkMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                Layout.maximumWidth: 160
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: appList.count === 0
                        text: root.query.length ? "No matching apps" : "No apps found"
                        color: Theme.inkMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                    }
                }

                Text {
                    text: "↑↓ · Enter launch · Esc / Super close"
                    color: Theme.inkMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    Layout.fillWidth: true
                }
            }

            // ── Right: notifications ──
            ColumnLayout {
                Layout.preferredWidth: 300
                Layout.fillHeight: true
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: "Notifications"
                        color: Theme.ink
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        Layout.fillWidth: true
                    }

                    Text {
                        text: "Clear"
                        color: Theme.inkMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        visible: Notifs.history.length > 0
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Notifs.dismissAllTracked()
                                Notifs.clearHistory()
                            }
                        }
                    }
                }

                ListView {
                    id: notifList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 8
                    model: Notifs.history

                    delegate: Rectangle {
                        id: nCard
                        required property var modelData
                        width: ListView.view.width
                        implicitHeight: nBody.implicitHeight + 20
                        radius: 14
                        color: Theme.surfaceContainer

                        ColumnLayout {
                            id: nBody
                            anchors {
                                left: parent.left
                                right: parent.right
                                top: parent.top
                                margins: 10
                            }
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Rectangle {
                                    Layout.preferredWidth: 32
                                    Layout.preferredHeight: 32
                                    radius: 8
                                    color: Theme.surfaceContainerHigh
                                    clip: true

                                    Image {
                                        anchors.fill: parent
                                        anchors.margins: modelData.image ? 0 : 4
                                        source: {
                                            if (modelData.image && modelData.image.length)
                                                return modelData.image
                                            const icon = modelData.appIcon || ""
                                            if (icon.length)
                                                return Quickshell.iconPath(icon, "dialog-information")
                                            return Quickshell.iconPath("dialog-information", "dialog-information")
                                        }
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text {
                                            text: modelData.appName || "Notification"
                                            color: Theme.inkMuted
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                        Text {
                                            text: root.relativeTime(modelData.time)
                                            color: Theme.inkMuted
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.summary || ""
                                        color: Theme.ink
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        font.weight: Font.Medium
                                        elide: Text.ElideRight
                                        maximumLineCount: 2
                                        wrapMode: Text.Wrap
                                        visible: text.length > 0
                                    }
                                }

                                Text {
                                    text: "󰅖"
                                    color: Theme.inkMuted
                                    font.family: Theme.iconFontFallback
                                    font.pixelSize: 13
                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -6
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            Notifs.dismissTracked(modelData.id)
                                            Notifs.removeHistory(modelData.uid)
                                        }
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: modelData.body || ""
                                color: Theme.inkMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                wrapMode: Text.Wrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                                textFormat: Text.StyledText
                                visible: text.length > 0
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: notifList.count === 0
                        text: "No notifications"
                        color: Theme.inkMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                    }
                }
            }
        }
    }

    onVisibleChanged: {
        if (visible) {
            const now = new Date()
            root.calYear = now.getFullYear()
            root.calMonth = now.getMonth()
            search.text = ""
            root.query = ""
            appList.currentIndex = filtered.values.length > 0 ? 0 : -1
            root.player?.positionChanged()
            search.forceActiveFocus()
        }
    }
}
