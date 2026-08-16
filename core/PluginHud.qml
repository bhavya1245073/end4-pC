// A transient overlay: shown for a moment, then gone.
//
//     PluginHud {
//         id: hud
//         anchor: "bottom-center"
//         duration: 2000
//
//         RowLayout {
//             MaterialSymbol { text: "volume_up" }
//             StyledText { text: `${Math.round(PluginAudio.volume * 100)}%` }
//         }
//     }
//
//     // then, from anywhere:
//     hud.flash()
//
// Every flash() restarts the countdown, so holding a volume key keeps one HUD on screen
// instead of stacking. Hovering it pauses the countdown - a HUD that vanishes while being
// read is worse than one that lingers.
//
// The surface exists only while visible, and it never takes keyboard focus, so it cannot
// interrupt typing. Content is laid out at its natural size and centred; the card, radius,
// background and shadow come from the shell so a plugin's HUD looks like the shell's own.
//
// For an OSD that should also be reachable from IPC and keybinds, declare it as an
// `osdIndicators` entry in the manifest instead - the shell then owns the window and the
// timeout, and `OsdRegistry.show(id)` raises it.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    // "top-center", "bottom-center", "center", "top-left", "top-right", "bottom-left",
    // "bottom-right", "left", "right".
    property string anchor: "bottom-center"

    // Milliseconds on screen. 0 means "stay until hide() is called".
    property int duration: 2500

    // Distance from the screen edge it is anchored to.
    property real margin: 80

    property bool animated: true

    // Pause the countdown while the pointer is over it.
    property bool pauseOnHover: true

    property bool visibleNow: false

    // Content goes here. A Component rather than an alias, because the window it is placed in is
    // created on demand and an alias cannot reach into that; QML wraps a child into a Component
    // for a Component-typed property, so a plugin writes its content as a child either way.
    default property Component content: null

    signal shown
    signal hidden

    function flash(): void {
        root.visibleNow = true;
        if (root.duration > 0)
            dismissTimer.restart();
    }

    function show(): void {
        root.visibleNow = true;
        dismissTimer.stop();
    }

    function hide(): void {
        root.visibleNow = false;
        dismissTimer.stop();
    }

    Timer {
        id: dismissTimer
        interval: root.duration
        // Hovering stops the clock rather than extending it: the countdown resumes from the
        // start when the pointer leaves, which is what "let me read this" means.
        running: false
        onTriggered: {
            if (root.pauseOnHover && hoverProbe.hovered) {
                dismissTimer.restart();
                return;
            }
            root.visibleNow = false;
        }
    }

    QtObject {
        id: hoverProbe
        property bool hovered: false
    }

    onVisibleNowChanged: root.visibleNow ? root.shown() : root.hidden()

    LazyLoader {
        activeAsync: root.visibleNow

        PanelWindow {
            id: panel
            visible: root.visibleNow
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:pluginHud"
            // Never: a HUD that takes focus makes the keypress that triggered it go missing.
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            anchors {
                top: root.anchor.startsWith("top") || root.anchor === "left" || root.anchor === "right"
                bottom: root.anchor.startsWith("bottom") || root.anchor === "left" || root.anchor === "right"
                left: root.anchor.endsWith("left") || root.anchor === "left" || root.anchor.endsWith("center") || root.anchor === "center"
                right: root.anchor.endsWith("right") || root.anchor === "right" || root.anchor.endsWith("center") || root.anchor === "center"
            }

            margins {
                top: root.anchor.startsWith("top") ? root.margin : 0
                bottom: root.anchor.startsWith("bottom") ? root.margin : 0
                left: root.anchor.endsWith("left") ? root.margin : 0
                right: root.anchor.endsWith("right") ? root.margin : 0
            }

            implicitWidth: card.implicitWidth
            implicitHeight: card.implicitHeight

            HoverHandler {
                onHoveredChanged: hoverProbe.hovered = hovered
            }

            Rectangle {
                id: card
                anchors.centerIn: parent
                implicitWidth: contentHolder.implicitWidth + Theme.pad.xl * 2
                implicitHeight: contentHolder.implicitHeight + Theme.pad.l * 2
                radius: Appearance.rounding.large
                color: Theme.solid
                border.width: 1
                border.color: Theme.outlineFaint

                // Animated on the axis it is anchored to, so a bottom HUD rises and a top one
                // drops. Opacity alone reads as a flicker at 60Hz.
                opacity: root.visibleNow ? 1 : 0
                transform: Translate {
                    y: root.visibleNow || !root.animated ? 0 : (root.anchor.startsWith("top") ? -16 : 16)

                    Behavior on y {
                        enabled: root.animated
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveEnter.duration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
                        }
                    }
                }

                Behavior on opacity {
                    enabled: root.animated
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.OutCubic
                    }
                }

                Item {
                    id: contentHolder
                    anchors.centerIn: parent
                    implicitWidth: inner.implicitWidth
                    implicitHeight: inner.implicitHeight
                    width: implicitWidth
                    height: implicitHeight

                    Loader {
                        id: inner
                        anchors.centerIn: parent
                        sourceComponent: root.content
                    }
                }
            }
        }
    }
}
