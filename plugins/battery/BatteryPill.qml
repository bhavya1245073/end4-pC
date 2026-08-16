// The battery capsule itself, drawn rather than glyphed.
//
// A MaterialSymbol battery icon has a fixed number of bars, so it can only ever
// approximate the level. This is a track with a fill inside it, so the level is
// exact and moves continuously.
//
// Used by both the bar widget and the desktop widget, at different sizes. It draws
// horizontally; rotate it for a vertical bar.

import QtQuick
import qs.core

Item {
    id: root

    // 0..1.
    property real value: 0

    // Breathe the fill. Means "charging" or "about to die" - both are things you
    // want noticed, and neither is worth a blink.
    property bool pulse: false

    property color colFill: Theme.text
    property color colTrack: Theme.fade(root.colFill, 0.82)

    property real capsuleLength: 26
    property real capsuleThickness: 13

    // The gap between track and fill. Small, but it is what makes the fill read as
    // sitting *inside* the battery rather than being the battery.
    readonly property real inset: Math.max(1, root.capsuleThickness / 9)

    // A real battery outline has a terminal. Without it this is just a progress
    // bar; with it, it reads as a battery with no icon and no label.
    readonly property real nubLength: Math.max(1.5, root.capsuleThickness / 7)
    readonly property real nubGap: Math.max(1, root.capsuleThickness / 11)

    implicitWidth: root.capsuleLength + root.nubGap + root.nubLength
    implicitHeight: root.capsuleThickness

    Rectangle {
        id: track

        width: root.capsuleLength
        height: root.capsuleThickness
        radius: height / 2
        color: root.colTrack

        anchors {
            left: parent.left
            verticalCenter: parent.verticalCenter
        }

        Behavior on color {
            animation: Theme.anim.fast.colorAnimation.createObject(this)
        }

        Rectangle {
            id: fill

            // Never narrower than its own diameter, or a nearly empty battery
            // renders as a squashed lens instead of a dot.
            readonly property real span: track.width - root.inset * 2
            readonly property real minimum: height

            width: Math.max(fill.minimum, fill.span * Math.max(0, Math.min(1, root.value)))
            height: track.height - root.inset * 2
            radius: height / 2
            color: root.colFill

            anchors {
                left: parent.left
                leftMargin: root.inset
                verticalCenter: parent.verticalCenter
            }

            // Level changes are worth animating: the reading is never urgent, and a
            // number that slides is much easier to notice than one that teleports.
            Behavior on width {
                animation: Theme.anim.normal.numberAnimation.createObject(this)
            }

            Behavior on color {
                animation: Theme.anim.fast.colorAnimation.createObject(this)
            }

            // Charging, or nearly empty, needs to be legible without reading the
            // glyph or the number. A slow breathe reads as "look at this" at a
            // glance and, unlike a blink, does not pull the eye away from whatever
            // you were actually doing.
            SequentialAnimation on opacity {
                running: root.pulse
                loops: Animation.Infinite
                alwaysRunToEnd: true

                NumberAnimation {
                    to: 0.55
                    duration: 900
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    to: 1
                    duration: 900
                    easing.type: Easing.InOutSine
                }
            }

            // Leaving the animation stops it wherever it happened to be.
            onOpacityChanged: if (!root.pulse && opacity !== 1) opacity = 1
        }
    }

    Rectangle {
        id: nub

        width: root.nubLength
        height: root.capsuleThickness * 0.42
        topRightRadius: width
        bottomRightRadius: width
        color: root.colFill
        opacity: 0.45

        anchors {
            left: track.right
            leftMargin: root.nubGap
            verticalCenter: parent.verticalCenter
        }

        Behavior on color {
            animation: Theme.anim.fast.colorAnimation.createObject(this)
        }
    }
}
