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
    readonly property color hover: Qt.rgba(1, 1, 1, 0.12)
    readonly property color hoverStrong: Qt.rgba(1, 1, 1, 0.20)
    readonly property color hoverBright: Qt.rgba(1, 1, 1, 0.28)

    // Liquid Glass (Regular) — lensing cues without compositor blur.
    readonly property color glassFill: Qt.rgba(1, 1, 1, 0.11)
    readonly property color glassFillHover: Qt.rgba(1, 1, 1, 0.17)
    readonly property color glassRim: Qt.rgba(1, 1, 1, 0.22)
    readonly property color glassRimHover: Qt.rgba(1, 1, 1, 0.34)
    readonly property color glassSpecular: Qt.rgba(1, 1, 1, 0.28)
    readonly property color glassSpecularSoft: Qt.rgba(1, 1, 1, 0.06)
    readonly property color glassShade: Qt.rgba(0, 0, 0, 0.18)
    readonly property color glassShadow: Qt.rgba(0, 0, 0, 0.28)
    readonly property color glassActiveFill: Qt.rgba(1, 1, 1, 0.88)
    readonly property color glassActiveInk: "#0a0a0a"
    readonly property color glassGlow: Qt.rgba(1, 1, 1, 0.14)

    // Control Center popup palette, kept separate from the monochrome bar.
    readonly property color popupSurface: "#e62b2935"
    readonly property color popupTile: "#22ffffff"
    readonly property color popupBorder: "#30ffffff"
    readonly property color popupText: "#ffffff"
    readonly property color popupMuted: "#b8ffffff"
    readonly property color popupAccent: "#0a84ff"

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

    readonly property string fontFamily: "Inter"
    readonly property string fontFamilyFallback: "CaskaydiaCove Nerd Font"
    readonly property string iconFont: "Symbols Nerd Font Mono"
    readonly property string iconFontFallback: "Symbols Nerd Font Mono"

    readonly property int fontSize: 12
    // Flip true → left vertical bar (VerticalBar). False → top Bar.
    readonly property bool barVertical: true
    readonly property int barHeight: 36
    readonly property int barWidth: 56
    readonly property int barMargin: 0
    readonly property int barInnerHeight: 32
    readonly property int barThickness: barVertical ? barWidth : barHeight
    // Popup inset past the bar edge (top bar → top inset; left bar → left inset).
    readonly property int popupTopInset: barVertical ? 0 : barHeight
    readonly property int popupLeftInset: barVertical ? barWidth : 0
    // Gap between bar bottom and widget cards (panel already starts at barHeight).
    readonly property int widgetTopGap: 5
    readonly property int pillRadius: 999
    readonly property int panelRadius: 16
    readonly property int modulePad: 4
    readonly property color alert: "#ff4d4d"

    readonly property int animFast: 150
    readonly property int animNormal: 220
    readonly property int animEmphasized: 320
}
