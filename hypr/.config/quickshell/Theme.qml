pragma Singleton
import QtQuick
import Quickshell

// Black / white bar palette. Avoid property names starting with "on" + Capital.
Singleton {
    readonly property color background: "#000000"
    readonly property color surface: "#0a0a0a"
    readonly property color surfaceContainer: Qt.rgba(1, 1, 1, 0.10)
    readonly property color surfaceContainerHigh: Qt.rgba(1, 1, 1, 0.14)
    readonly property color surfaceContainerHighest: Qt.rgba(1, 1, 1, 0.18)

    readonly property color ink: "#ffffff"
    readonly property color inkMuted: Qt.rgba(1, 1, 1, 0.55)
    readonly property color hairline: Qt.rgba(1, 1, 1, 0.35)
    readonly property color hairlineMuted: Qt.rgba(1, 1, 1, 0.18)

    readonly property color primary: "#ffffff"
    readonly property color primaryInk: "#000000"
    readonly property color primaryContainer: Qt.rgba(1, 1, 1, 0.2)
    readonly property color secondary: Qt.rgba(1, 1, 1, 0.75)
    readonly property color tertiary: Qt.rgba(1, 1, 1, 0.65)
    readonly property color cyan: "#ffffff"
    readonly property color error: "#ffffff"
    readonly property color high: "#ffffff"

    readonly property color foreground: ink
    readonly property color foregroundDim: inkMuted
    readonly property color accent: primary
    readonly property color panelBg: Qt.rgba(0, 0, 0, 0.92)
    readonly property color panelBorder: hairlineMuted
    readonly property color sectionBg: surfaceContainerHigh
    readonly property color danger: error

    readonly property string fontFamily: "SF Pro Text"
    readonly property string fontFamilyFallback: "CaskaydiaCove Nerd Font"
    readonly property string iconFont: "Symbols Nerd Font Mono"
    readonly property string iconFontFallback: "Symbols Nerd Font Mono"

    readonly property int fontSize: 12
    readonly property int barHeight: 32
    readonly property int barMargin: 0
    readonly property int barInnerHeight: 28
    readonly property int pillRadius: 999
    readonly property int panelRadius: 16
    readonly property int modulePad: 8
    readonly property color alert: "#ff4d4d"

    readonly property int animFast: 150
    readonly property int animNormal: 220
    readonly property int animEmphasized: 320
}
