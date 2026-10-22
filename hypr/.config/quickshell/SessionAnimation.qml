import QtQuick
import Quickshell
import Quickshell.Wayland

// Visual only: power commands belong exclusively to session-action.
Scope {
    id: root
    property string phase: "idle"
    property real closure: 0
    property real lineWidth: 1

    function play(): string {
        if (phase !== "idle") return "busy"
        closure = 0
        lineWidth = 1
        phase = "active"
        animation.start()
        return "started"
    }

    SequentialAnimation {
        id: animation
        // Let the layer surfaces map before starting the CRT close.
        PauseAnimation { duration: 80 }
        NumberAnimation {
            target: root; property: "closure"; to: 1; duration: 360
            easing.type: Easing.InCubic
        }
        NumberAnimation {
            target: root; property: "lineWidth"; to: 0; duration: 220
            easing.type: Easing.InCubic
        }
        ScriptAction { script: root.phase = "complete" }
        // Never leave a black overlay behind after resume or a failed action.
        PauseAnimation { duration: 900 }
        ScriptAction { script: root.phase = "idle" }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            visible: root.phase !== "idle"
            color: "transparent"
            // Ignore reserved space. Setting exclusiveZone as well would reset
            // exclusionMode to Normal during initialization.
            exclusionMode: ExclusionMode.Ignore
            // Do not steal keyboard focus or intercept pointer input.
            mask: Region {}
            anchors { top: true; bottom: true; left: true; right: true }
            WlrLayershell.namespace: "qs-session-animation"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Rectangle {
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: Math.ceil(parent.height * root.closure / 2)
                color: "black"
            }
            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: Math.ceil(parent.height * root.closure / 2)
                color: "black"
            }
            Rectangle {
                anchors.centerIn: parent
                width: parent.width * root.lineWidth
                height: 2
                color: "#e7f5ff"
                visible: root.closure >= 1 && root.lineWidth > 0
            }
        }
    }
}
