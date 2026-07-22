import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import ".."

PanelWindow {
    id: root
    visible: Globals.clipboardOpen
    color: "transparent"
    exclusiveZone: 0

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    WlrLayershell.namespace: "qs-clipboard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    property string query: ""
    property var entries: []

    function close(): void {
        Globals.clipboardOpen = false
    }

    function reload(): void {
        listProc.running = false
        listProc.running = true
    }

    function parseList(text: string): var {
        const lines = text.split("\n").filter(l => l.length > 0)
        const out = []
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i]
            const tab = line.indexOf("\t")
            if (tab < 0)
                continue
            const id = line.slice(0, tab)
            const preview = line.slice(tab + 1)
            const isImage = preview.startsWith("[[ binary data") || preview.startsWith("[image]")
            out.push({
                id: id,
                preview: isImage ? "[image]" : preview,
                isImage: isImage,
                raw: line
            })
        }
        return out
    }

    function filteredEntries(): var {
        const q = root.query
        if (!q.length)
            return root.entries
        return root.entries.filter(e => e.preview.toLowerCase().includes(q))
    }

    function selectedEntry(): var {
        const items = filtered.values
        if (list.currentIndex < 0 || list.currentIndex >= items.length)
            return null
        return items[list.currentIndex]
    }

    function pasteSelected(): void {
        const entry = root.selectedEntry()
        if (!entry)
            return
        Quickshell.execDetached({
            command: ["sh", "-c", 'printf "%s\\n" "$1" | cliphist decode | wl-copy', "qs-clip", entry.raw]
        })
        root.close()
    }

    function deleteSelected(): void {
        const entry = root.selectedEntry()
        if (!entry)
            return
        Quickshell.execDetached({
            command: ["sh", "-c", 'printf "%s\\n" "$1" | cliphist delete', "qs-clip", entry.raw]
        })
        reloadTimer.restart()
    }

    function wipeAll(): void {
        Quickshell.execDetached(["cliphist", "wipe"])
        root.entries = []
        list.currentIndex = -1
    }

    function moveSelection(delta: int): void {
        if (list.count <= 0)
            return
        const next = Math.max(0, Math.min(list.count - 1, list.currentIndex + delta))
        list.currentIndex = next
        list.positionViewAtIndex(next, ListView.Contain)
    }

    Timer {
        id: reloadTimer
        interval: 80
        onTriggered: root.reload()
    }

    Process {
        id: listProc
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.entries = root.parseList(text)
                list.currentIndex = root.entries.length > 0 ? 0 : -1
            }
        }
    }

    HyprlandFocusGrab {
        active: root.visible
        windows: [root]
        onCleared: root.close()
    }

    LauncherCard {
        anchors.fill: parent
        visible: root.visible
        onScrimClicked: root.close()

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
                    text: "󰅌"
                    color: Theme.primary
                    font.family: Theme.iconFontFallback
                    font.pixelSize: 15
                }

                TextField {
                    id: search
                    Layout.fillWidth: true
                    placeholderText: "Filter clipboard…"
                    color: Theme.ink
                    placeholderTextColor: Theme.inkMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    background: Item {}
                    selectByMouse: true

                    onTextChanged: {
                        root.query = text.trim().toLowerCase()
                        list.currentIndex = filtered.values.length > 0 ? 0 : -1
                    }

                    Keys.onPressed: event => {
                        const ctrl = event.modifiers & Qt.ControlModifier
                        const shift = event.modifiers & Qt.ShiftModifier
                        if (event.key === Qt.Key_Escape) {
                            root.close()
                            event.accepted = true
                        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J || (ctrl && event.key === Qt.Key_N)) {
                            root.moveSelection(1)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K || (ctrl && event.key === Qt.Key_P)) {
                            root.moveSelection(-1)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_L) {
                            root.pasteSelected()
                            event.accepted = true
                        } else if (ctrl && shift && event.key === Qt.Key_D) {
                            root.wipeAll()
                            event.accepted = true
                        } else if (ctrl && event.key === Qt.Key_D) {
                            root.deleteSelected()
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
            highlightMoveDuration: 80
            preferredHighlightBegin: 0
            preferredHighlightEnd: height
            highlightRangeMode: ListView.ApplyRange
            currentIndex: filtered.values.length > 0 ? 0 : -1

            model: ScriptModel {
                id: filtered
                values: root.filteredEntries()
            }

            highlight: Rectangle {
                radius: Theme.pillRadius
                color: Theme.primaryContainer
            }

            delegate: Item {
                id: row
                required property var modelData
                required property int index
                width: ListView.view.width
                height: 36
                z: 1

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: list.currentIndex = row.index
                    onDoubleClicked: root.pasteSelected()
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10

                    Text {
                        text: modelData.isImage ? "󰋫" : "󰦪"
                        color: Theme.inkMuted
                        font.family: Theme.iconFontFallback
                        font.pixelSize: 14
                    }

                    Text {
                        Layout.fillWidth: true
                        text: modelData.preview
                        color: Theme.ink
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: list.count === 0
                text: root.query.length ? "No matching entries" : "Clipboard history empty"
                color: Theme.inkMuted
                font.family: Theme.fontFamily
                font.pixelSize: 13
            }
        }

        Text {
            text: "↑↓ / j·k · Enter paste · Ctrl+D delete · Ctrl+Shift+D wipe · Esc"
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
            root.reload()
            search.forceActiveFocus()
        }
    }
}
