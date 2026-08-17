// A slow animated gradient in the current Material You palette, for the background of a card,
// a header or an empty state.
//
//     PluginMeshGradient {
//         anchors.fill: parent
//         radius: Theme.radius.l
//     }
//
// Colours come from the palette, so it re-tints with the wallpaper and never clashes with the
// rest of the shell. Motion is slow enough to be atmosphere rather than distraction, and stops
// entirely when `PluginFX.effectsAllowed` is false - so it costs nothing in power-saver mode or
// behind a lock screen, where it would otherwise be a GPU load nobody can see.
//
// ## Why four radial gradients and not a shader
//
// A mesh gradient is what a designer calls three or four soft colour blobs drifting over each
// other. Done as a fragment shader it needs a .frag, a .qsb compiled at build time, and a
// fallback for drivers that reject it - and the visual result is the same as four
// `RadialGradient`s at low alpha, which the scene graph already batches. The cheap version is
// also the one that cannot fail to load on someone else's GPU.

import QtQuick
import Qt5Compat.GraphicalEffects
import qs.core
import qs.modules.common

Item {
    id: root

    property real radius: 0

    // 0..1. How far the blobs drift from their resting positions.
    property real motion: 0.5

    // How strong the colour is over the base. Low by default: this is a background, and text
    // goes on top of it.
    property real intensity: 0.5

    // Seconds for one full cycle. Deliberately long - anything under ~20 s reads as movement
    // rather than as a living surface.
    property real periodSeconds: 34

    property color base: Theme.solid

    // Drawn from the palette rather than hard-coded, so this follows the wallpaper.
    readonly property var palette: [Theme.accent, Theme.notice, Theme.accentMuted, Theme.high]

    clip: true

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.base
    }

    // One driver for every blob, so they stay in phase with each other and there is one
    // animation rather than four.
    QtObject {
        id: phase
        property real t: 0
    }

    NumberAnimation {
        target: phase
        property: "t"
        from: 0
        to: 2 * Math.PI
        duration: Math.max(4000, root.periodSeconds * 1000)
        loops: Animation.Infinite
        running: PluginFX.effectsAllowed
    }

    Repeater {
        model: 4

        delegate: Item {
            required property int index

            // Each blob gets its own angular offset and a slightly different rate, so the
            // pattern never repeats visibly within a cycle.
            readonly property real offset: index * (Math.PI / 2)
            readonly property real rate: 1 + index * 0.23

            readonly property real driftX: Math.cos(phase.t * rate + offset) * root.width * 0.22 * root.motion
            readonly property real driftY: Math.sin(phase.t * rate * 0.8 + offset) * root.height * 0.22 * root.motion

            // Resting positions at the four corners, pulled inward so the blobs overlap in the
            // middle rather than hugging the edges.
            readonly property real homeX: (index === 0 || index === 3) ? root.width * 0.3 : root.width * 0.7
            readonly property real homeY: (index < 2) ? root.height * 0.32 : root.height * 0.68

            anchors.fill: parent

            RadialGradient {
                anchors.fill: parent
                horizontalOffset: (homeX - root.width / 2) + driftX
                verticalOffset: (homeY - root.height / 2) + driftY
                horizontalRadius: root.width * 0.62
                verticalRadius: root.height * 0.62

                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: Qt.rgba(
                            root.palette[index].r,
                            root.palette[index].g,
                            root.palette[index].b,
                            0.55 * root.intensity)
                    }
                    GradientStop {
                        position: 1
                        color: "transparent"
                    }
                }
            }
        }
    }

    // Rounds the whole stack in one pass. Rounding each gradient separately would show four sets
    // of corners.
    layer.enabled: root.radius > 0
    layer.effect: OpacityMask {
        maskSource: Rectangle {
            width: root.width
            height: root.height
            radius: root.radius
        }
    }
}
