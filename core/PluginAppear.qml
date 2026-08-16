// Entrance animation for anything that appears: a card, a menu row, a popup, a list item.
//
//     PluginAppear { }                      // as a child - animates its parent
//
//     PluginAppear { target: card; index: 3 }   // or point it at something, with a stagger
//
// One line instead of six: a fade plus a small rise plus a slight scale, on the shell's own curve
// and duration. Reversible - set `shown: false` and it leaves, faster than it arrived.
//
// It animates `opacity` and a `Translate`/`Scale` transform rather than `x`/`y`, so it is safe
// inside a RowLayout or ColumnLayout: a layout owns the position of its children and fights anything
// that assigns to it, which is the single most common way an animated widget ends up jittering.
//
// `index` staggers a group. Give each delegate its model index and a list arrives as one gesture
// instead of all at once.

import QtQuick
import qs.core

Item {
    id: root

    // What to animate. Defaults to the parent, which is the usual case.
    property Item target: root.parent

    property bool shown: true

    // Position in a staggered group; -1 for no stagger.
    property int index: -1

    // Direction it comes from: "up" (rises), "down", "left", "right", "none".
    property string from: "up"

    property real distance: Theme.motion.slideDistance
    property real scaleFrom: Theme.motion.enterScale

    // Off for something that should just fade.
    property bool scaled: true

    // Set false to place the item immediately, for a widget restored from a saved layout where an
    // entrance animation would look like the shell is loading rather than the widget arriving.
    property bool animated: true

    width: 0
    height: 0
    visible: false

    readonly property int __delay: root.index >= 0 ? Theme.motion.delay(root.index) : 0
    readonly property real __offset: root.shown || !root.animated ? 0 : root.distance

    Binding {
        target: root.target
        property: "opacity"
        value: root.shown || !root.animated ? 1 : 0

        // Restored when this object goes away, so removing the animation does not leave a widget
        // stuck invisible.
        restoreMode: Binding.RestoreBindingOrValue
    }

    Binding {
        target: root.target
        property: "transform"
        value: [translate, scaleTransform]
        restoreMode: Binding.RestoreBindingOrValue
    }

    Translate {
        id: translate
        x: root.from === "left" ? -root.__offset : root.from === "right" ? root.__offset : 0
        y: root.from === "up" ? root.__offset : root.from === "down" ? -root.__offset : 0

        Behavior on x {
            enabled: root.animated
            NumberAnimation {
                duration: root.shown ? Theme.motion.enter : Theme.motion.exit
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.shown ? Theme.motion.decelerate : Theme.motion.accelerate
            }
        }
        Behavior on y {
            enabled: root.animated
            NumberAnimation {
                duration: root.shown ? Theme.motion.enter : Theme.motion.exit
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.shown ? Theme.motion.decelerate : Theme.motion.accelerate
            }
        }
    }

    Scale {
        id: scaleTransform
        origin.x: (root.target?.width ?? 0) / 2
        origin.y: (root.target?.height ?? 0) / 2
        xScale: root.scaled && root.animated && !root.shown ? root.scaleFrom : 1
        yScale: scaleTransform.xScale

        Behavior on xScale {
            enabled: root.animated
            NumberAnimation {
                duration: root.shown ? Theme.motion.enter : Theme.motion.exit
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.shown ? Theme.motion.spatial : Theme.motion.accelerate
            }
        }
    }

    // The whole point of the stagger: start hidden, then let the delay decide when each one moves.
    Component.onCompleted: {
        if (!root.animated || !root.shown)
            return;
        root.shown = false;
        appearTimer.start();
    }

    Timer {
        id: appearTimer
        interval: Math.max(1, root.__delay)
        onTriggered: root.shown = true
    }
}
