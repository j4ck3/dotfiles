import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import ".."

Rectangle {
    id: root

    required property var context

    color: Theme.background

    readonly property string userName: {
        const u = Quickshell.env("USER")
        return u && u.length ? u : "user"
    }

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
        enabled: true
    }

    // Ambient vignette
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.04) }
            GradientStop { position: 0.45; color: "transparent" }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.55) }
        }
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -40
        spacing: 28
        width: Math.min(420, parent.width - 48)

        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 6

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: {
                    const h = clock.hours.toString().padStart(2, "0")
                    const m = clock.minutes.toString().padStart(2, "0")
                    return `${h}:${m}`
                }
                color: Theme.ink
                font.family: Theme.fontFamily
                font.pixelSize: 72
                font.weight: Font.Thin
                font.letterSpacing: 2
                renderType: Text.NativeRendering
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: Qt.formatDateTime(clock.date, "dddd, MMMM d")
                color: Theme.inkMuted
                font.family: Theme.fontFamily
                font.pixelSize: 16
                font.weight: Font.Medium
                renderType: Text.NativeRendering
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            spacing: 12

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: root.userName
                color: Theme.ink
                font.family: Theme.fontFamily
                font.pixelSize: 15
                font.weight: Font.Medium
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 48
                radius: Theme.panelRadius
                color: Theme.surfaceContainer
                border.width: 1
                border.color: passwordBox.activeFocus ? Theme.hairline : Theme.hairlineMuted

                Behavior on border.color {
                    ColorAnimation { duration: Theme.animFast }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 10
                    spacing: 10

                    Text {
                        text: "󰌾"
                        color: Theme.inkMuted
                        font.family: Theme.iconFontFallback
                        font.pixelSize: 16
                    }

                    TextField {
                        id: passwordBox
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        focus: true
                        enabled: !root.context.unlockInProgress
                        echoMode: TextInput.Password
                        inputMethodHints: Qt.ImhSensitiveData
                        color: Theme.ink
                        placeholderText: "Password"
                        placeholderTextColor: Theme.inkMuted
                        background: Item {}
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        leftPadding: 0
                        rightPadding: 0
                        verticalAlignment: TextInput.AlignVCenter

                        onTextChanged: root.context.currentText = text
                        onAccepted: root.context.tryUnlock()

                        Connections {
                            target: root.context
                            function onCurrentTextChanged(): void {
                                if (passwordBox.text !== root.context.currentText)
                                    passwordBox.text = root.context.currentText
                            }
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        radius: 10
                        color: unlockBtn.containsMouse && unlockBtn.enabled
                               ? Theme.hoverStrong : "transparent"
                        opacity: unlockBtn.enabled ? 1 : 0.35

                        Text {
                            anchors.centerIn: parent
                            text: root.context.unlockInProgress ? "󰔟" : "󰌿"
                            color: Theme.ink
                            font.family: Theme.iconFontFallback
                            font.pixelSize: 15
                        }

                        MouseArea {
                            id: unlockBtn
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !root.context.unlockInProgress && root.context.currentText !== ""
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: root.context.tryUnlock()
                        }
                    }
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredHeight: 18
                visible: root.context.showFailure
                text: "Incorrect password"
                color: Theme.alert
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: Font.Medium
            }
        }
    }

    Component.onCompleted: passwordBox.forceActiveFocus()
}
