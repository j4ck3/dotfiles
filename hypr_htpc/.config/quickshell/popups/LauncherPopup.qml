import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import ".."

PanelWindow {
    id: root
    visible: Globals.launcherOpen
    color: "transparent"
    exclusiveZone: 0
    focusable: true
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    WlrLayershell.namespace: "quickshell-htpc-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    property string query: ""
    readonly property var blockedIds: [
        "avahi-discover", "assistant", "designer", "linguist",
        "qdbusviewer", "bvnc", "bssh", "qt5ct", "qt6ct", "qv4l2", "qvidcap"
    ]

    function close(): void { Globals.launcherOpen = false }

    function blocked(entry: var): bool {
        const id = (entry.id || "").toLowerCase()
        const name = (entry.name || "").toLowerCase()
        return blockedIds.indexOf(id) !== -1 || id.includes("avahi")
            || id.includes("pinentry") || name.startsWith("qt ")
            || name.startsWith("avahi")
    }

    function matches(entry: var): bool {
        if (blocked(entry))
            return false
        if (!query.length)
            return true
        let haystack = ((entry.name || "") + " " + (entry.genericName || "")).toLowerCase()
        const keywords = entry.keywords || []
        for (let i = 0; i < keywords.length; i++)
            haystack += " " + String(keywords[i]).toLowerCase()
        return haystack.includes(query)
    }

    function launchSelected(): void {
        const entry = filtered.values[list.currentIndex]
        if (entry) {
            entry.execute()
            close()
        }
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

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.42)
        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(760, root.width - 80)
        height: Math.min(620, root.height - 100)
        radius: 22
        color: "#000000"
        border.width: 1
        border.color: Theme.border

        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 54
                radius: 16
                color: Theme.surface

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 12
                    spacing: 10

                    Text {
                        text: "󰍉"
                        color: Theme.ink
                        font.family: Theme.iconFont
                        font.pixelSize: 22
                    }

                    TextField {
                        id: search
                        Layout.fillWidth: true
                        placeholderText: "Search applications…"
                        color: Theme.ink
                        placeholderTextColor: Theme.inkMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: 20
                        background: Item {}
                        selectByMouse: true
                        onTextChanged: {
                            root.query = text.trim().toLowerCase()
                            list.currentIndex = filtered.values.length ? 0 : -1
                        }
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Escape) {
                                root.close()
                                event.accepted = true
                            } else if (event.key === Qt.Key_Down
                                       || (event.key === Qt.Key_J
                                           && (event.modifiers & Qt.ControlModifier))) {
                                root.moveSelection(1)
                                event.accepted = true
                            } else if (event.key === Qt.Key_Up
                                       || (event.key === Qt.Key_K
                                           && (event.modifiers & Qt.ControlModifier))) {
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
                spacing: 3
                currentIndex: filtered.values.length ? 0 : -1
                model: ScriptModel {
                    id: filtered
                    values: {
                        const applications = [...DesktopEntries.applications.values]
                        return applications.filter(entry => root.matches(entry))
                            .sort((a, b) => (a.name || "").localeCompare(b.name || ""))
                    }
                }
                highlight: Rectangle {
                    radius: 14
                    color: Theme.active
                }
                highlightMoveDuration: 80

                delegate: Item {
                    id: entry
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    height: 58

                    Rectangle {
                        anchors.fill: parent
                        radius: 14
                        color: hover.containsMouse && list.currentIndex !== entry.index
                            ? Theme.surfaceHover : "transparent"
                    }
                    MouseArea {
                        id: hover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: list.currentIndex = entry.index
                        onClicked: {
                            entry.modelData.execute()
                            root.close()
                        }
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 14
                        IconImage {
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36
                            source: Quickshell.iconPath(entry.modelData.icon || "application-x-executable",
                                                       "application-x-executable")
                        }
                        Text {
                            Layout.fillWidth: true
                            text: entry.modelData.name || entry.modelData.id || ""
                            color: Theme.ink
                            font.family: Theme.fontFamily
                            font.pixelSize: 20
                            elide: Text.ElideRight
                        }
                        Text {
                            visible: !!entry.modelData.genericName
                            text: entry.modelData.genericName || ""
                            color: Theme.inkMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.smallFont
                            Layout.maximumWidth: 220
                            elide: Text.ElideRight
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    text: root.query.length ? "No matching applications" : "No applications found"
                    color: Theme.inkMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.bodyFont
                }
            }

            Text {
                Layout.fillWidth: true
                text: "↑↓ / Ctrl+J·K  ·  Enter launch  ·  Esc close"
                color: Theme.inkMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.smallFont
            }
        }
    }

    onVisibleChanged: {
        if (visible) {
            search.text = ""
            query = ""
            list.currentIndex = filtered.values.length ? 0 : -1
            search.forceActiveFocus()
        }
    }
}
