import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Notifications
import ".."

Item {
    id: root

    NotificationServer {
        id: server
        keepOnReload: true
        actionsSupported: true
        actionIconsSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: true
        bodyMarkupSupported: true
        bodySupported: true
        imageSupported: true
        inlineReplySupported: true
        persistenceSupported: true

        onNotification: notif => {
            notif.tracked = true
        }
    }

    PanelWindow {
        id: win
        screen: Globals.focusedScreen()
        color: "transparent"
        exclusiveZone: 0
        exclusionMode: ExclusionMode.Ignore
        visible: true
        implicitWidth: 388
        implicitHeight: screen ? screen.height : 800
        mask: Region {
            item: stack
        }

        anchors {
            top: true
            right: true
        }

        margins {
            top: Theme.barHeight + 10
            right: 14
        }

        WlrLayershell.namespace: "qs-notifications"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Column {
            id: stack
            anchors {
                top: parent.top
                right: parent.right
            }
            width: 360
            spacing: 10

            move: Transition {
                NumberAnimation {
                    properties: "y"
                    duration: 90
                    easing.type: Easing.OutCubic
                }
            }

            Repeater {
                id: repeater
                model: server.trackedNotifications

                delegate: Rectangle {
                    id: card
                    required property var modelData
                    width: stack.width
                    implicitHeight: body.implicitHeight + 14 + (timeoutSec > 0 ? 22 : 14)
                    radius: 18
                    color: "#000000"
                    border.width: isCritical ? 1 : 0
                    border.color: isCritical ? Theme.alert : "transparent"
                    opacity: 0
                    clip: true

                    readonly property var notif: modelData
                    property real life: 1
                    readonly property bool isCritical: {
                        try {
                            return notif.urgency === NotificationUrgency.Critical
                        } catch (e) {
                            return false
                        }
                    }
                    readonly property real timeoutSec: {
                        if (isCritical)
                            return 0
                        // Fixed short toast lifetime (ignore long client timeouts).
                        return 2.5
                    }

                    Component.onCompleted: opacity = 1

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 90
                            easing.type: Easing.OutCubic
                        }
                    }

                    NumberAnimation {
                        id: lifeAnim
                        target: card
                        property: "life"
                        from: 1
                        to: 0
                        duration: Math.max(1, Math.round(card.timeoutSec * 1000))
                        running: card.timeoutSec > 0
                        easing.type: Easing.Linear
                        onFinished: card.notif.expire()
                    }

                    HoverHandler {
                        id: hover
                        onHoveredChanged: {
                            if (card.timeoutSec <= 0)
                                return
                            if (hovered)
                                lifeAnim.pause()
                            else
                                lifeAnim.resume()
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        onClicked: event => {
                            if (event.button === Qt.RightButton) {
                                const tracked = server.trackedNotifications.values
                                for (let i = 0; i < tracked.length; i++)
                                    tracked[i].dismiss()
                            } else if (event.button === Qt.MiddleButton) {
                                const acts = card.notif.actions
                                if (acts && acts.length)
                                    acts[0].invoke()
                                if (!card.notif.resident)
                                    card.notif.dismiss()
                            } else {
                                card.notif.dismiss()
                            }
                        }
                    }

                    // Timeout progress pill
                    Rectangle {
                        id: lifeTrack
                        anchors {
                            left: parent.left
                            right: parent.right
                            bottom: parent.bottom
                            leftMargin: 14
                            rightMargin: 14
                            bottomMargin: 10
                        }
                        height: 4
                        radius: height / 2
                        color: Theme.surfaceContainerHigh
                        visible: card.timeoutSec > 0
                        clip: true

                        Rectangle {
                            width: Math.max(lifeTrack.height, lifeTrack.width * card.life)
                            height: lifeTrack.height
                            radius: height / 2
                            color: Theme.ink
                            visible: card.life > 0.001
                        }
                    }

                    ColumnLayout {
                        id: body
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            margins: 14
                            bottomMargin: card.timeoutSec > 0 ? 22 : 14
                        }
                        spacing: 10

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 14

                            Rectangle {
                                Layout.preferredWidth: 44
                                Layout.preferredHeight: 44
                                Layout.alignment: Qt.AlignTop
                                radius: 12
                                color: Theme.surfaceContainer
                                clip: true

                                Image {
                                    anchors.fill: parent
                                    anchors.margins: card.notif.image ? 0 : 6
                                    source: {
                                        if (card.notif.image && String(card.notif.image).length)
                                            return String(card.notif.image)
                                        const icon = card.notif.appIcon || ""
                                        if (icon.length)
                                            return Quickshell.iconPath(icon, "dialog-information")
                                        return Quickshell.iconPath("dialog-information", "dialog-information")
                                    }
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Text {
                                        visible: !!(card.notif.appName && card.notif.appName.length)
                                        text: card.notif.appName || ""
                                        color: Theme.inkMuted
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.weight: Font.Medium
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    Text {
                                        text: "󰅖"
                                        color: Theme.inkMuted
                                        font.family: Theme.iconFontFallback
                                        font.pixelSize: 14
                                        z: 2

                                        MouseArea {
                                            anchors.fill: parent
                                            anchors.margins: -6
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: card.notif.dismiss()
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: card.notif.summary || ""
                                    color: Theme.ink
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 14
                                    font.weight: Font.DemiBold
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                    visible: text.length > 0
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: card.notif.body || ""
                                    color: Theme.inkMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 4
                                    elide: Text.ElideRight
                                    textFormat: Text.StyledText
                                    visible: text.length > 0
                                }
                            }
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 8
                            visible: card.notif.actions && card.notif.actions.length > 0

                            Repeater {
                                model: card.notif.actions

                                Rectangle {
                                    required property var modelData
                                    implicitWidth: actionLabel.implicitWidth + 20
                                    implicitHeight: 28
                                    radius: 14
                                    color: Theme.surfaceContainerHigh

                                    Text {
                                        id: actionLabel
                                        anchors.centerIn: parent
                                        text: modelData.text || modelData.identifier || "Action"
                                        color: Theme.ink
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        font.weight: Font.Medium
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            modelData.invoke()
                                            if (!card.notif.resident)
                                                card.notif.dismiss()
                                        }
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            visible: !!card.notif.hasInlineReply

                            TextField {
                                id: replyField
                                Layout.fillWidth: true
                                placeholderText: card.notif.inlineReplyPlaceholder || "Reply…"
                                color: Theme.ink
                                placeholderTextColor: Theme.inkMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                background: Rectangle {
                                    radius: 12
                                    color: Theme.surfaceContainer
                                }
                                Keys.onReturnPressed: {
                                    if (text.trim().length) {
                                        card.notif.sendInlineReply(text.trim())
                                        if (!card.notif.resident)
                                            card.notif.dismiss()
                                    }
                                }
                            }

                            Rectangle {
                                implicitWidth: 56
                                implicitHeight: 28
                                radius: 14
                                color: Theme.primary

                                Text {
                                    anchors.centerIn: parent
                                    text: "Send"
                                    color: Theme.primaryInk
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (replyField.text.trim().length) {
                                            card.notif.sendInlineReply(replyField.text.trim())
                                            if (!card.notif.resident)
                                                card.notif.dismiss()
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
}
