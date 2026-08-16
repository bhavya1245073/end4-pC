// A pill: a label, optionally an icon, on a harmonised background.
//
//     PluginChip { text: "Stoic"; icon: "sell" }
//     PluginChip { text: "3 failed"; tone: PluginChip.Error }
//     PluginChip { text: "Focus"; tone: PluginChip.Accent; onClicked: ... }
//
// `tone` picks a *pair* of colours that are guaranteed to contrast, which is the
// part hand-rolled chips get wrong: they set a container colour from the theme and
// then draw text in `Theme.text`, which is tuned for the panel behind it, not for
// the fill in front of it. Every tone here is an M3 container/on-container pair.
//
// Give it a `tone` or a `color`, not both.

import QtQuick
import qs.modules.common.widgets

Rectangle {
    id: root

    enum Tone { Neutral, Accent, Muted, Error, Notice }

    property string text: ""
    property string icon: ""
    property int tone: PluginChip.Tone.Muted
    property bool compact: false

    // Set `color` directly to escape the tones; `colText` then follows it via
    // Theme.on(), which picks black or white by luminance rather than by guess.
    property color colText: root.__pair.fg

    signal clicked

    readonly property var __pair: {
        switch (root.tone) {
        case PluginChip.Tone.Accent:
            return { bg: Theme.accentBlock, fg: Theme.onAccentBlock };
        case PluginChip.Tone.Error:
            return { bg: Theme.errorBlock, fg: Theme.onErrorBlock };
        case PluginChip.Tone.Notice:
            return { bg: Theme.noticeBlock, fg: Theme.onNoticeBlock };
        case PluginChip.Tone.Neutral:
            return { bg: Theme.surfaceHigh, fg: Theme.text };
        default:
            return { bg: Theme.accentMuted, fg: Theme.onAccentMuted };
        }
    }

    readonly property real __padH: root.compact ? Theme.pad.m : Theme.pad.l
    readonly property real __padV: root.compact ? Theme.pad.xs : Theme.pad.s

    color: root.__pair.bg
    radius: Theme.radius.full

    implicitWidth: content.implicitWidth + root.__padH * 2
    implicitHeight: content.implicitHeight + root.__padV * 2

    Behavior on color {
        animation: Theme.anim.fast.colorAnimation.createObject(this)
    }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: root.icon !== "" ? Theme.pad.s : 0

        MaterialSymbol {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.icon !== ""
            text: root.icon
            // Tied to the label, so a chip in a small font does not get a huge glyph.
            iconSize: Math.round(label.font.pixelSize * 1.15)
            color: root.colText
        }

        StyledText {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            color: root.colText
            font.pixelSize: root.compact ? Theme.font.xs : Theme.font.s
            elide: Text.ElideRight
        }
    }

    // Only interactive if someone connected to clicked - an inert chip should not
    // show a pointer cursor or react to hover.
    readonly property bool interactive: root.clicked.length > 0

    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        visible: root.interactive && (hoverHandler.hovered || tapHandler.pressed)
        color: Theme.fade(root.colText, tapHandler.pressed ? Theme.state.press : Theme.state.hover)
    }

    HoverHandler {
        id: hoverHandler
        enabled: root.interactive
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        id: tapHandler
        enabled: root.interactive
        onSingleTapped: root.clicked()
    }
}
