import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import ".."

FocusScope {
    id: root

    property var application: null
    property var info: ({})
    property bool refreshing: false
    signal backRequested()
    signal refreshRequested()
    signal updateRequested(var command)

    readonly property bool systemUpdate: info.manager === "pacman" || info.manager === "aur"
    readonly property bool canUpdate: !!(info.update_command && info.update_command.length)

    function dateLabel(timestamp: var): string {
        if (!timestamp)
            return "Unknown"
        const date = new Date(timestamp * 1000)
        const days = Math.max(0, Math.floor((Date.now() - date.getTime()) / 86400000))
        return `${days} days ago · ${date.toLocaleDateString()}`
    }

    function sizeLabel(bytes: var): string {
        if (bytes === null || bytes === undefined)
            return "Unknown"
        const units = ["B", "KiB", "MiB", "GiB"]
        let size = bytes
        let index = 0
        while (size >= 1024 && index < units.length - 1) {
            size /= 1024
            index++
        }
        return `${size.toFixed(index ? 1 : 0)} ${units[index]}`
    }

    function statusLabel(): string {
        const labels = {
            "current": "Up to date",
            "update_available": "Update available",
            "ahead": "Installed version is newer than source",
            "unknown": "Not verified"
        }
        const stale = info.checked_at && Date.now() / 1000 - info.checked_at > 3600
        const label = stale ? "Not verified · Cached check is over an hour old" : (labels[info.status] || "Not verified")
        return refreshing ? `${label} · Checking…` : label
    }

    Keys.onEscapePressed: event => {
        root.backRequested()
        event.accepted = true
    }

    component ActionButton: Button {
        id: button
        font.family: Theme.fontFamily
        font.pixelSize: 13
        padding: 10
        contentItem: Text {
            text: button.text
            font: button.font
            color: button.enabled ? Theme.ink : Theme.inkMuted
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 12
            color: button.hovered || button.activeFocus ? Theme.primaryContainer : Theme.surfaceContainer
            border.width: button.activeFocus ? 1 : 0
            border.color: Theme.primary
            opacity: button.enabled ? 1 : 0.5
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            ActionButton {
                text: "Back"
                onClicked: root.backRequested()
            }
            Text {
                Layout.fillWidth: true
                text: root.application ? root.application.name : "Application status"
                color: Theme.ink
                font.family: Theme.fontFamily
                font.pixelSize: 18
                elide: Text.ElideRight
            }
            ActionButton {
                text: root.refreshing ? "Checking…" : "Refresh"
                enabled: !root.refreshing
                onClicked: root.refreshRequested()
            }
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth

            ColumnLayout {
                width: parent.width
                spacing: 10

                Repeater {
                    model: [
                        ["Status", root.statusLabel()],
                        ["Installed version", root.info.installed || "Unknown"],
                        [root.info.source && root.info.source.indexOf("pacman-configured:") === 0 ? "Latest (configured repo)" : "Latest on this channel", root.info.latest || (root.refreshing ? "Checking…" : "Unknown")],
                        ["Package manager", root.info.manager === "aur" ? "AUR via paru" : (root.info.manager || "Unknown")],
                        ["Package / channel", root.info.source || root.info.package || "Unknown"],
                        ["Installed size", root.sizeLabel(root.info.size_bytes)],
                        [root.info.released_at ? "Version released" : root.info.built_at ? "Package built" : "Package commit", root.dateLabel(root.info.released_at || root.info.built_at || root.info.committed_at)],
                        ["Installed on", root.dateLabel(root.info.installed_at)],
                        ["Last checked", root.info.checked_at ? new Date(root.info.checked_at * 1000).toLocaleString() : "Not yet verified"]
                    ]
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 12
                        Text {
                            Layout.preferredWidth: 155
                            Layout.alignment: Qt.AlignTop
                            text: modelData[0]
                            color: Theme.inkMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                        }
                        Text {
                            Layout.fillWidth: true
                            text: modelData[1]
                            textFormat: Text.PlainText
                            color: Theme.ink
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            wrapMode: Text.WrapAnywhere
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: "Size is the installed package, not personal data or shared dependencies. Build or commit age is not the upstream release age."
                    color: Theme.inkMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }
            }
        }

        Text {
            Layout.fillWidth: true
            text: root.systemUpdate
                ? "Arch requires a full system upgrade. Opens a terminal for review and confirmation; other packages may update too."
                : root.canUpdate
                    ? "Opens a terminal to update this app on its installed channel. Review and confirm there."
                    : "No supported package manager found. Update this app using its original installer."
            color: Theme.inkMuted
            font.family: Theme.fontFamily
            font.pixelSize: 12
            wrapMode: Text.WordWrap
        }

        ActionButton {
            Layout.fillWidth: true
            text: root.systemUpdate ? "Open system updater…" : "Update application…"
            enabled: root.canUpdate
            onClicked: root.updateRequested(root.info.update_command)
        }

        Text {
            text: "Esc · Back to apps"
            color: Theme.inkMuted
            font.family: Theme.fontFamily
            font.pixelSize: 11
        }
    }
}
