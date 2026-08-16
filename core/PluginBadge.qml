// A count or dot badge, for overlaying on an icon.
//
//     PluginIconButton {
//         icon: "notifications"
//         PluginBadge { count: Notifications.list.length }   // auto top-right
//     }
//
//     PluginBadge { dot: true; tone: PluginBadge.Tone.Error }
//
// Anchors itself to its parent's top-right corner by default, and hides itself when
// there is nothing to show, so `count: 0` needs no `visible:` of its own. Counts
// above `max` render as "99+" rather than widening the badge without limit.

import QtQuick
import qs.modules.common.widgets

Rectangle {
    id: root

    enum Tone { Accent, Error, Notice, Neutral }

    property int count: 0
    property string text: ""
    property bool dot: false
    property int max: 99
    property int tone: PluginBadge.Tone.Error

    readonly property string label: root.text !== "" ? root.text
        : root.count > root.max ? `${root.max}+`
        : String(root.count)

    // A dot shows whenever it is asked to; a count badge disappears at zero, which is
    // what every caller wants and nobody remembers to write.
    visible: root.dot || root.count > 0 || root.text !== ""

    readonly property var __pair: {
        switch (root.tone) {
        case PluginBadge.Tone.Accent:
            return { bg: Theme.accent, fg: Theme.onAccent };
        case PluginBadge.Tone.Notice:
            return { bg: Theme.notice, fg: Theme.on(Theme.notice) };
        case PluginBadge.Tone.Neutral:
            return { bg: Theme.surfaceHigh, fg: Theme.text };
        default:
            return { bg: Theme.error, fg: Theme.on(Theme.error) };
        }
    }

    color: root.__pair.bg
    radius: Theme.radius.full

    readonly property real minSize: root.dot ? 8 : 16

    implicitWidth: root.dot ? root.minSize
        : Math.max(root.minSize, label.implicitWidth + Theme.pad.m)
    implicitHeight: root.minSize

    // Overlapping the corner rather than sitting inside it, so it reads as attached
    // to the icon instead of as part of the content.
    anchors.right: parent?.right ?? undefined
    anchors.top: parent?.top ?? undefined
    anchors.rightMargin: -root.implicitWidth / 3
    anchors.topMargin: -root.implicitHeight / 3

    StyledText {
        id: label
        anchors.centerIn: parent
        visible: !root.dot
        text: root.label
        color: root.__pair.fg
        font.pixelSize: Theme.font.xs
        font.weight: Font.DemiBold
    }

    // A count changing is worth noticing; a silent number swap is easy to miss.
    Behavior on implicitWidth {
        animation: Theme.anim.fast.numberAnimation.createObject(this)
    }
    Behavior on color {
        animation: Theme.anim.fast.colorAnimation.createObject(this)
    }
}
