// A round icon button, themed and interactive, in one line.
//
//     PluginIconButton {
//         icon: "content_copy"
//         tooltip: qsTr("Copy")
//         onClicked: PluginUtils.copy(text)
//     }
//
// Replaces the Rectangle + MouseArea + hover colour + press scale + tooltip that
// this would otherwise be, and gets the parts that are easy to get wrong right:
// the hit area is at least 32px even when the glyph is 14px, hover and press are
// state overlays on the real background rather than hardcoded greys, and the tooltip
// is the shell's own so it follows the theme and cannot escape the screen.
//
// Sizing: `size` is the button, `iconSize` follows it unless set. It has an
// implicit size, so it works directly in a RowLayout with no Layout.preferredWidth.

import QtQuick
import qs.modules.common.widgets

Item {
    id: root

    property string icon: ""
    property string text: ""
    property string tooltip: ""

    property real size: 32
    property real iconSize: Math.round(root.size * 0.5625)   // 18 at 32
    property bool filled: false

    // `flat` (default) tints on hover only; otherwise it always shows a backing.
    property bool flat: true
    property bool enabled: true
    property bool checked: false

    // A count or a dot in the corner. 0 hides it, which is what a live count usually is.
    property int badge: 0
    property bool badgeDot: false

    property color colIcon: root.checked ? Theme.onAccentBlock : Theme.text
    property color colBackground: root.checked ? Theme.accentBlock : (root.flat ? "transparent" : Theme.surfaceHigh)

    signal clicked
    signal rightClicked

    // Hit target never shrinks below a comfortable tap size even for a tiny glyph;
    // an 18px icon in an 18px button is unhittable on a touchscreen and fiddly with
    // a mouse.
    implicitWidth: Math.max(root.size, 32)
    implicitHeight: Math.max(root.size, 32)

    opacity: root.enabled ? 1 : Theme.state.disabled

    readonly property bool hovered: hoverHandler.hovered
    readonly property bool pressed: tapHandler.pressed

    Rectangle {
        id: background
        anchors.centerIn: parent
        width: root.size
        height: root.size
        radius: Theme.radius.full
        color: root.colBackground

        // Layered over whatever the background is, so it reads correctly on a card,
        // on a panel, and on an accent fill without three sets of hardcoded colours.
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            visible: root.enabled && (root.hovered || root.pressed)
            color: Theme.fade(root.colIcon, root.pressed ? Theme.state.press : Theme.state.hover)
        }

        // Keyboard focus ring. Drawn outside the fill so it is visible on a checked button too,
        // where a state layer would be lost against the accent.
        Rectangle {
            anchors.centerIn: parent
            width: parent.width + 6
            height: parent.height + 6
            radius: Theme.radius.full
            color: "transparent"
            border.width: 2
            border.color: Theme.accent
            visible: root.activeFocus
        }

        Behavior on color {
            animation: Theme.anim.fast.colorAnimation.createObject(this)
        }
    }

    MaterialSymbol {
        anchors.centerIn: background
        visible: root.icon !== ""
        text: root.icon
        iconSize: root.iconSize
        fill: root.filled || root.checked ? 1 : 0
        color: root.colIcon

        Behavior on color {
            animation: Theme.anim.fast.colorAnimation.createObject(this)
        }
    }

    StyledText {
        anchors.centerIn: background
        visible: root.icon === "" && root.text !== ""
        text: root.text
        color: root.colIcon
        font.pixelSize: Theme.font.s
    }

    PluginBadge {
        count: root.badge
        dot: root.badgeDot
    }

    // Grows a little under the pointer and dips when pressed. Both are small on purpose: a button
    // that jumps is noise, but a button that does nothing feels dead, and 6% is the difference.
    scale: root.pressed ? 0.92 : (root.hovered && root.enabled ? 1.06 : 1)
    Behavior on scale {
        NumberAnimation {
            duration: root.pressed ? Theme.motion.instant : Theme.motion.fast
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.pressed ? Theme.motion.effects : Theme.motion.spatialFast
        }
    }

    // Reachable by keyboard, and Space/Enter activate it - a button that only answers a mouse is
    // not a button.
    activeFocusOnTab: root.enabled
    Keys.onSpacePressed: root.clicked()
    Keys.onReturnPressed: root.clicked()

    HoverHandler {
        id: hoverHandler
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        id: tapHandler
        enabled: root.enabled
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onSingleTapped: eventPoint => {
            if (eventPoint.event?.button === Qt.RightButton)
                root.rightClicked();
            else
                root.clicked();
        }
    }

    PopupToolTip {
        extraVisibleCondition: root.tooltip !== ""
        text: root.tooltip
    }
}
