// A container that crossfades when its content changes, without disturbing the
// layout around it.
//
//     PluginTransition {
//         trigger: QuoteState.index          // fade whenever this changes
//         StyledText { text: QuoteState.text; wrapMode: Text.Wrap }
//     }
//
// The problem it solves: the obvious way to animate a text swap is a Behavior on
// opacity plus a y translation, and inside a ColumnLayout that translation fights the
// layout - the layout positions the item, the animation offsets it, and the item ends
// up overlapping its neighbour or snapping back mid-animation. This isolates the
// animated properties on an inner item that the layout does not manage, so the outer
// item keeps a stable position and implicit size.
//
// `trigger` is any value; when it changes, the content fades out, the change lands,
// and it fades back in. Bind it to whatever identifies the content (an index, an id,
// the text itself), not to a timestamp that changes every tick.

import QtQuick

Item {
    id: root

    default property alias content: inner.data

    // Change this to play the transition. Comparing by value, so assigning the same
    // value again is not a change and does not flicker.
    property var trigger: null

    property int duration: Theme.anim.fast.duration
    // How far the content slides in from, in pixels. 0 for a pure crossfade.
    property real slide: 6
    property bool animate: true

    implicitWidth: inner.implicitWidth
    implicitHeight: inner.implicitHeight

    // Fixed by the parent layout; the animation only ever touches `inner`.
    Item {
        id: inner
        width: root.width
        height: root.height
        implicitWidth: childrenRect.width
        implicitHeight: childrenRect.height

        opacity: 1
        y: 0
    }

    onTriggerChanged: {
        if (!root.animate || !root.visible)
            return;
        fade.restart();
    }

    SequentialAnimation {
        id: fade

        ParallelAnimation {
            NumberAnimation {
                target: inner
                property: "opacity"
                to: 0
                duration: Math.round(root.duration * 0.4)
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: inner
                property: "y"
                to: -root.slide
                duration: Math.round(root.duration * 0.4)
                easing.type: Easing.OutCubic
            }
        }

        // Snapped to the far side so the content slides in rather than back out the way
        // it left, which reads as a replacement instead of a wobble.
        PropertyAction {
            target: inner
            property: "y"
            value: root.slide
        }

        ParallelAnimation {
            NumberAnimation {
                target: inner
                property: "opacity"
                to: 1
                duration: root.duration
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: inner
                property: "y"
                to: 0
                duration: root.duration
                easing.type: Easing.OutCubic
            }
        }
    }
}
