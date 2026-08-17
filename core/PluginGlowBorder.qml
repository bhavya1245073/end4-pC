// A glow around something, for focus and drag-over states.
//
// The usual way to show "this is the drop target" or "this has keyboard focus" is a 2 px border
// in the accent colour, which at a distance is invisible on a busy wallpaper. A glow reads
// instantly and does not shift the layout, because it is drawn outside the item's own bounds:
//
//     PluginGlowBorder {
//         target: card
//         active: dropTarget.dragging
//     }
//
// Layered rectangles rather than a shader. A real Gaussian outer glow means a blur pass over an
// offscreen texture the size of the item plus the glow, every frame it changes, on a GPU that is
// also running the compositor. Four nested rounded rectangles with falling alpha are
// indistinguishable at glow radii under ~12 px, cost nothing, and cannot fail to compile on a
// driver with no float framebuffers.

import QtQuick
import qs.core
import qs.modules.common

Item {
    id: root

    // What to glow around. Defaults to the parent, which is the common case.
    property Item target: root.parent

    property bool active: false
    property color colour: Theme.accent

    // How far out the glow reaches.
    property real size: 8

    // Corner radius of the target. Read from it when it has one.
    property real radius: root.target?.radius ?? Theme.radius.m

    property real intensity: 0.55

    // Non-interactive by construction: a focus ring that eats clicks is a bug, and this sits on
    // top of whatever it decorates.
    anchors.fill: root.target
    anchors.margins: -root.size
    visible: root.active && PluginFX.effectsAllowed
    z: 100

    opacity: root.active ? 1 : 0
    Behavior on opacity {
        NumberAnimation {
            duration: Theme.motion.fast
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.motion.enter
        }
    }

    Repeater {
        // Four rings, outermost first. Each is inset a quarter of the glow size from the last, and
        // alpha falls off as the square of the distance from the target - which is what makes a
        // stack of hard edges read as a soft gradient.
        model: 4

        delegate: Rectangle {
            required property int index

            // 0 for the outermost ring, three quarters of the glow for the innermost - so the
            // innermost sits just outside the target's own edge.
            readonly property real inset: root.size * (index / 4)

            anchors.centerIn: parent
            width: root.width - inset * 2
            height: root.height - inset * 2

            radius: root.radius + (root.size - inset)
            color: "transparent"
            border.width: Math.max(1, root.size / 4)
            border.color: Qt.rgba(
                root.colour.r,
                root.colour.g,
                root.colour.b,
                root.intensity * Math.pow((index + 1) / 4, 2))
        }
    }

    // A breathing pulse while active, so a drop target is noticed in peripheral vision. Stops
    // with the rest of the shell's animation.
    SequentialAnimation {
        running: root.active && PluginFX.effectsAllowed
        loops: Animation.Infinite
        alwaysRunToEnd: false

        NumberAnimation {
            target: root
            property: "intensity"
            from: 0.4
            to: 0.7
            duration: 900
            easing.type: Easing.InOutQuad
        }

        NumberAnimation {
            target: root
            property: "intensity"
            from: 0.7
            to: 0.4
            duration: 900
            easing.type: Easing.InOutQuad
        }
    }
}
