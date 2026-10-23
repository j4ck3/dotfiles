import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Io
import ".."

PanelWindow {
    id: root
    visible: Globals.launcherOpen
    color: "transparent"
    exclusiveZone: 0

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    WlrLayershell.namespace: "qs-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    property string query: ""
    property var appVersions: ({})
    property bool versionsRefreshing: false
    property var detailEntry: null

    function showDetails(): void {
        if (!list.currentItem)
            return
        detailEntry = list.currentItem.modelData
        pages.currentIndex = 1
        details.focusUpdate()
        refreshVersions(false)
    }

    function showApps(): void {
        pages.currentIndex = 0
        detailEntry = null
        search.forceActiveFocus()
    }

    function refreshVersions(force: bool): void {
        if (versionProcess.running)
            return
        versionsRefreshing = true
        versionProcess.command = ["/usr/bin/python3", Globals.scriptsDir + "/launcher-versions.py"]
        if (force)
            versionProcess.command = versionProcess.command.concat(["--refresh"])
        versionProcess.running = true
    }

    Process {
        id: versionProcess
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                try {
                    const result = JSON.parse(line)
                    if (result.apps && (Object.keys(result.apps).length || !result.refreshing))
                        root.appVersions = result.apps
                    root.versionsRefreshing = !!result.refreshing
                } catch (error) {
                    console.warn("Launcher version data:", error)
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.versionsRefreshing = false
            if (exitCode !== 0)
                root.appVersions = ({})
        }
    }

    // Allow list: data/launcher-apps.txt, one desktop entry ID per line.
    // A missing or empty file shows every application.
    property var allowedIds: null

    FileView {
        id: allowFile
        path: Qt.resolvedUrl("../data/launcher-apps.txt")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const ids = text().split("\n").map(line => line.trim()).filter(line => line.length && !line.startsWith("#"))
            root.allowedIds = ids.length ? new Set(ids) : null
        }
        onLoadFailed: root.allowedIds = null
    }

    function close(): void {
        Globals.launcherOpen = false
    }

    function isBlocked(entry: var): bool {
        if (!root.allowedIds)
            return false
        const id = (entry.id || "").replace(/\.desktop$/, "")
        return !root.allowedIds.has(id) && !root.allowedIds.has(entry.id)
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
        const item = list.currentItem
        if (!item || !item.modelData)
            return
        item.modelData.execute()
        root.close()
    }

    function moveSelection(delta: int): void {
        if (list.count <= 0)
            return
        const next = Math.max(0, Math.min(list.count - 1, list.currentIndex + delta))
        list.currentIndex = next
        list.positionViewAtIndex(next, ListView.Contain)
    }

    HyprlandFocusGrab {
        active: root.visible
        windows: [root]
        onCleared: root.close()
    }

    LauncherCard {
        anchors.fill: parent
        visible: root.visible
        cardHeight: 480
        onScrimClicked: root.close()

        StackLayout {
            id: pages
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: 0

            ColumnLayout {
                spacing: 10
                // Search
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    radius: 20
                    color: Theme.surfaceContainer

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 8
                        spacing: 8

                        Text {
                            text: "󰍉"
                            color: Theme.primary
                            font.family: Theme.iconFontFallback
                            font.pixelSize: 17
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
                                list.currentIndex = filtered.values.length > 0 ? 0 : -1
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
                                    if (event.modifiers & Qt.ShiftModifier)
                                        root.showDetails()
                                    else
                                        root.launchSelected()
                                    event.accepted = true
                                }
                            }
                        }
                    }
                }

                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    keyNavigationWraps: false
                    highlightMoveDuration: 80
                    preferredHighlightBegin: 0
                    preferredHighlightEnd: height
                    highlightRangeMode: ListView.ApplyRange
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
                            color: entryMouse.containsMouse && list.currentIndex !== entry.index
                                 ? Theme.hover : "transparent"
                            Behavior on color {
                                ColorAnimation { duration: Theme.animFast }
                            }
                        }

                        MouseArea {
                            id: entryMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: list.currentIndex = entry.index
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
                                font.pixelSize: 15
                                elide: Text.ElideRight
                                verticalAlignment: Text.AlignVCenter
                            }

                            Text {
                                visible: list.currentIndex === entry.index
                                text: "Shift+Enter · Details"
                                color: Theme.inkMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                Layout.maximumWidth: 180
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: list.count === 0
                        text: root.query.length ? "No matching apps" : "No apps found"
                        color: Theme.inkMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                    }
                }

                Text {
                    text: "↑↓ / j·k · Enter launch · Shift+Enter details · Esc close"
                    color: Theme.inkMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    Layout.fillWidth: true
                }
            }

            AppDetails {
                id: details
                application: root.detailEntry
                info: root.detailEntry ? (root.appVersions[root.detailEntry.id] || root.appVersions[root.detailEntry.id.replace(/\.desktop$/, "")] || {}) : ({})
                refreshing: root.versionsRefreshing
                onBackRequested: root.showApps()
                onRefreshRequested: root.refreshVersions(true)
                onUpdateRequested: command => {
                    Quickshell.execDetached(["ghostty", "-e", "/usr/bin/python3", Globals.scriptsDir + "/launcher-update.py", root.detailEntry.id, JSON.stringify(command)])
                    root.close()
                }
            }
        }
    }

    onVisibleChanged: {
        if (visible) {
            root.showApps()
            search.text = ""
            root.query = ""
            list.currentIndex = filtered.values.length > 0 ? 0 : -1
            search.forceActiveFocus()
        }
    }
}
