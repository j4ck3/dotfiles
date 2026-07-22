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
    visible: Globals.shortcutsOpen
    color: "transparent"
    exclusiveZone: 0

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    WlrLayershell.namespace: "qs-shortcuts"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    property string activeTab: "apps"
    property string query: ""
    property var tabs: []

    FileView {
        id: shortcutsFile
        path: Qt.resolvedUrl("../data/shortcuts.json")
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
    }

    Component.onCompleted: {
        try {
            root.tabs = JSON.parse(shortcutsFile.text())
            if (root.tabs.length)
                root.activeTab = root.tabs[0].id
        } catch (e) {
            root.tabs = []
        }
    }

    function matchesItem(item: var, q: string): bool {
        if (!q.length)
            return true
        return (item.keys + " " + item.desc).toLowerCase().includes(q.toLowerCase())
    }

    function sectionVisible(section: var, q: string): bool {
        return section.items.some(item => root.matchesItem(item, q))
    }

    HyprlandFocusGrab {
        active: root.visible
        windows: [root]
        onCleared: Globals.shortcutsOpen = false
    }

    // Dim backdrop
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)
        opacity: root.visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }

        MouseArea {
            anchors.fill: parent
            onClicked: Globals.shortcutsOpen = false
            focus: root.visible
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    Globals.shortcutsOpen = false
                    event.accepted = true
                }
            }
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(980, parent.width - 80)
        height: Math.min(720, parent.height - 80)
        radius: 28
        color: Theme.surfaceContainerHighest
        border.width: 1
        border.color: Theme.hairlineMuted
        scale: root.visible ? 1 : 0.94
        opacity: root.visible ? 1 : 0

        Behavior on scale {
            NumberAnimation {
                duration: Theme.animEmphasized
                easing.type: Easing.OutBack
                easing.overshoot: 0.4
            }
        }
        Behavior on opacity {
            NumberAnimation { duration: Theme.animNormal }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    Layout.fillWidth: true
                    height: 44
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
                            font.pixelSize: 16
                        }

                        TextField {
                            id: search
                            Layout.fillWidth: true
                            placeholderText: "Search keybindings..."
                            color: Theme.ink
                            background: Item {}
                            onTextChanged: root.query = text
                        }
                    }
                }

                M3IconButton {
                    icon: "󰅖"
                    onClicked: Globals.shortcutsOpen = false
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: root.tabs

                    Rectangle {
                        required property var modelData
                        property bool selected: root.activeTab === modelData.id

                        implicitWidth: tabLabel.implicitWidth + 24
                        implicitHeight: 34
                        radius: 17
                        color: selected ? Theme.primary : Theme.surfaceContainer

                        Text {
                            id: tabLabel
                            anchors.centerIn: parent
                            text: modelData.label
                            color: selected ? Theme.primaryInk : Theme.inkMuted
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            font.family: Theme.fontFamily
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.activeTab = modelData.id
                        }

                        Behavior on color {
                            ColorAnimation { duration: Theme.animFast }
                        }
                    }
                }

                Item { Layout.fillWidth: true }
            }

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: columns.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                RowLayout {
                    id: columns
                    width: parent.width
                    spacing: 20

                    Repeater {
                        model: {
                            const tab = root.tabs.find(t => t.id === root.activeTab)
                            if (!tab)
                                return []
                            const mid = Math.ceil(tab.sections.length / 2)
                            return [tab.sections.slice(0, mid), tab.sections.slice(mid)]
                        }

                        ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            spacing: 14

                            Repeater {
                                model: modelData

                                ColumnLayout {
                                    required property var modelData
                                    visible: root.sectionVisible(modelData, root.query)
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Text {
                                        text: modelData.title
                                        color: Theme.primary
                                        font.bold: true
                                        font.pixelSize: 12
                                        font.letterSpacing: 0.4
                                    }

                                    Repeater {
                                        model: modelData.items

                                        RowLayout {
                                            required property var modelData
                                            visible: root.matchesItem(modelData, root.query)
                                            Layout.fillWidth: true
                                            spacing: 12

                                            Text {
                                                text: modelData.desc
                                                color: Theme.inkMuted
                                                Layout.fillWidth: true
                                                wrapMode: Text.Wrap
                                                font.pixelSize: 12
                                                font.family: Theme.fontFamily
                                            }

                                            Rectangle {
                                                color: Theme.surfaceContainer
                                                radius: 10
                                                implicitHeight: keyLabel.implicitHeight + 8
                                                implicitWidth: keyLabel.implicitWidth + 14

                                                Text {
                                                    id: keyLabel
                                                    anchors.centerIn: parent
                                                    text: modelData.keys
                                                    color: Theme.ink
                                                    font.pixelSize: 11
                                                    font.family: Theme.fontFamily
                                                    font.weight: Font.Medium
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

            Text {
                text: "Esc to close · Super Shift + ? to toggle"
                color: Theme.inkMuted
                font.pixelSize: 11
            }
        }
    }

    onVisibleChanged: {
        if (visible) {
            search.text = ""
            root.query = ""
            search.forceActiveFocus()
        }
    }
}
