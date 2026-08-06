//@ pragma UseQApplication
import QtQuick
import Quickshell
import "lock"

// PAM UI test without session lock:
//   qs -p ~/.config/quickshell/lock-test.qml
ShellRoot {
    LockContext {
        id: lockContext
        onUnlocked: {
            status.text = "PAM OK — unlocked"
            status.color = "#7CFC00"
        }
        onFailed: {
            status.text = "PAM failed"
            status.color = "#ff4d4d"
        }
    }

    FloatingWindow {
        width: 480
        height: 720
        title: "Lockscreen PAM test"

        LockSurface {
            anchors.fill: parent
            context: lockContext
        }

        Text {
            id: status
            z: 10
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: 24
            color: "#888888"
            font.pixelSize: 13
            text: "Type password + Enter (does not lock session)"
        }
    }

    Connections {
        target: Quickshell
        function onLastWindowClosed(): void { Qt.quit() }
    }
}
