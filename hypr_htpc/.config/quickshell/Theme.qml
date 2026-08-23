pragma Singleton
import QtQuick
import Quickshell

Singleton {
    readonly property color background: Qt.rgba(0, 0, 0, 0.92)
    readonly property color panel: "#ee111318"
    readonly property color surface: Qt.rgba(1, 1, 1, 0.10)
    readonly property color surfaceHover: Qt.rgba(1, 1, 1, 0.18)
    readonly property color active: Qt.rgba(1, 1, 1, 0.26)
    readonly property color ink: "#ffffff"
    readonly property color inkMuted: Qt.rgba(1, 1, 1, 0.62)
    readonly property color border: Qt.rgba(1, 1, 1, 0.25)
    readonly property color alert: "#ff6666"

    readonly property string fontFamily: "SF Pro Display"
    readonly property string fallbackFont: "Noto Sans"
    readonly property string iconFont: "Symbols Nerd Font Mono"

    readonly property int barHeight: 56
    readonly property int barFont: 18
    readonly property int bodyFont: 17
    readonly property int smallFont: 14
    readonly property int radius: 18
}
