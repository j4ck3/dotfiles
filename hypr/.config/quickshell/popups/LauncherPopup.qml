import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
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

    // Hide common junk / toolkit utilities from the launcher.
    readonly property var blockedIds: [
        "avahi-discover",
        "assistant",
        "designer",
        "linguist",
        "qdbusviewer",
        "bvnc",
        "bssh",
        "qt5ct",
        "qt6ct",
        "qv4l2",
        "qvidcap",
    ]

    function close(): void {
        Globals.launcherOpen = false
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

                MouseArea {
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
                        visible: !!(modelData.genericName && modelData.genericName.length)
                        text: modelData.genericName || ""
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
            text: "↑↓ / j·k · Enter launch · Esc close"
            color: Theme.inkMuted
            font.family: Theme.fontFamily
            font.pixelSize: 11
            Layout.fillWidth: true
        }
    }

    onVisibleChanged: {
        if (visible) {
            search.text = ""
            root.query = ""
            list.currentIndex = filtered.values.length > 0 ? 0 : -1
            search.forceActiveFocus()
        }
    }
}
