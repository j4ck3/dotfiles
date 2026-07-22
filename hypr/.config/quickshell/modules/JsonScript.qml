import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

import ".."

// Script-backed macOS stacked stat (label over value).
Item {
    id: root
    property string scriptName
    property int intervalMs: 3000
    property bool continuous: false
    property string label: ""
    property string value: ""
    property string tooltip: ""
    property string cssClass: ""
    property bool hidden: false

    implicitWidth: Math.max(labelText.implicitWidth, valueText.implicitWidth) + 4
    implicitHeight: col.implicitHeight
    Layout.preferredWidth: implicitWidth
    Layout.fillHeight: true
    visible: !hidden && (label.length > 0 || value.length > 0)

    function parsePayload(raw: string): void {
        const t = raw.trim()
        if (!t.length) {
            root.label = ""
            root.value = ""
            root.tooltip = ""
            root.cssClass = ""
            root.hidden = true
            return
        }

        let text = t
        let tip = ""
        let cls = ""

        if (t.startsWith("{")) {
            try {
                const j = JSON.parse(t)
                text = (j.text || "").replace(/<[^>]+>/g, "")
                tip = j.tooltip || ""
                cls = j.class || ""
            } catch (e) {
                text = t
            }
        } else {
            text = t.replace(/<[^>]+>/g, "")
        }

        text = text.replace(/\\n/g, "\n")
        const parts = text.split("\n").map(s => s.trim()).filter(s => s.length)
        if (parts.length >= 2) {
            root.label = parts[0]
            root.value = parts.slice(1).join(" ")
        } else if (parts.length === 1) {
            // "CPU 2%" fallback
            const m = parts[0].match(/^([A-Za-z]+)\s+(.*)$/)
            if (m) {
                root.label = m[1]
                root.value = m[2]
            } else {
                root.label = ""
                root.value = parts[0]
            }
        } else {
            root.label = ""
            root.value = ""
        }

        root.tooltip = tip
        root.cssClass = cls
        root.hidden = cls === "hidden" || (root.label.length === 0 && root.value.length === 0)
    }

    Column {
        id: col
        anchors.centerIn: parent
        spacing: -1

        Text {
            id: labelText
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            color: Theme.inkMuted
            font.family: Theme.fontFamily
            font.pixelSize: 9
            font.weight: Font.Medium
            font.letterSpacing: 0.3
            opacity: 0.7
            visible: root.label.length > 0
        }

        Text {
            id: valueText
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.value
            color: root.cssClass === "high" ? "#ff4d4d"
                 : root.cssClass === "active" ? Theme.primary
                 : Theme.ink
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.weight: Font.Medium
            opacity: 0.95
        }
    }

    Process {
        id: proc
        command: [Globals.scriptsDir + "/" + root.scriptName]
        running: root.continuous

        stdout: StdioCollector {
            waitForEnd: !root.continuous
            onStreamFinished: {
                if (!root.continuous)
                    root.parsePayload(text)
            }
            onTextChanged: {
                if (root.continuous && text.length) {
                    const lines = text.trim().split("\n")
                    root.parsePayload(lines[lines.length - 1])
                }
            }
        }
    }

    Timer {
        interval: root.intervalMs
        running: !root.continuous && root.scriptName.length > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: proc.running = true
    }

    Component.onCompleted: {
        if (root.continuous)
            proc.running = true
    }
}
