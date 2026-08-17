// The window PluginToast draws into.
//
// Instantiated once by PluginHost, for the same reason PluginDialogHost is: feedback that
// only works when some unrelated plugin happens to be enabled is worse than none, because
// the caller has already decided the user needs to be told.
//
// Top-centre of the focused monitor, above everything, and click-through except for the
// pill itself - a toast that eats clicks in the middle of the screen would be worse than
// no toast. That is what `mask` is for: the window is full-width, the input region is the
// pill.
//
// The dismiss timer is driven from `toast.at` rather than restarted by hand, so a
// coalesced repeat (PluginToast bumps `at`) extends the toast without the host knowing
// anything about coalescing.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.modules.common
import qs.modules.common.widgets

Scope {
    id: root

    readonly property var toast: PluginToast.current
    readonly property int toastId: root.toast?.id ?? 0
    readonly property string tone: root.toast?.tone ?? "accent"

    // A toast is a shell surface, so it is coloured like every other shell surface: the same
    // container fill and the same text colour as a popup or a dialog. Only the icon and the
    // border carry the tone.
    //
    // Tinting the whole pill per tone is the obvious version and it is wrong twice: the four
    // tone containers do not have a guaranteed contrast pairing with each other, so "success"
    // and "notice" came out with near-black text on olive, and a pill that changes colour per
    // message reads as four different components rather than one.
    readonly property color fillColour: Theme.solid
    readonly property color inkColour: Theme.text

    readonly property color markColour: {
        if (root.tone === "error")
            return Theme.error;
        if (root.tone === "notice")
            return Theme.notice;
        if (root.tone === "success")
            return Theme.accent;
        return Theme.accent;
    }

    LazyLoader {
        // Not `active: PluginToast.visible`: the window has to outlive the toast by one
        // animation so the exit transition is visible. `keepAlive` is released by the
        // host's own timer below.
        activeAsync: PluginToast.visible || keepAlive.running

        PanelWindow {
            id: panel

            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:pluginToast"
            // Never takes focus. A toast that steals the keyboard mid-sentence is a bug.
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            anchors { top: true; left: true; right: true }
            implicitHeight: pill.implicitHeight + Theme.pad.xl * 3

            // Only the pill takes clicks; the rest of the strip is not there as far as the
            // pointer is concerned.
            mask: Region {
                item: pill
            }

            Rectangle {
                id: pill

                anchors.horizontalCenter: parent.horizontalCenter
                y: Theme.pad.xl

                implicitWidth: Math.min(panel.width - Theme.pad.xl * 4, row.implicitWidth + Theme.pad.l * 2)
                implicitHeight: Math.max(40, row.implicitHeight + Theme.pad.m * 2)
                width: implicitWidth
                height: implicitHeight

                radius: Theme.radius.full
                color: root.fillColour
                border.width: 1
                border.color: Theme.fade(root.markColour, 0.35)

                opacity: PluginToast.visible ? 1 : 0
                scale: PluginToast.visible ? 1 : 0.92
                transform: Translate {
                    y: PluginToast.visible ? 0 : -Theme.motion.slideDistance
                    Behavior on y {
                        NumberAnimation {
                            duration: Theme.motion.fast
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.motion.enter
                        }
                    }
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.motion.fast
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.motion.enter
                    }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: Theme.motion.fast
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.motion.enter
                    }
                }

                StyledRectangularShadow {
                    target: pill
                }

                // Click the body to dismiss early. Everyone tries it.
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    onClicked: PluginToast.dismissCurrent()
                }

                RowLayout {
                    id: row
                    anchors.centerIn: parent
                    spacing: Theme.pad.m

                    MaterialSymbol {
                        text: root.toast?.icon ?? "bolt"
                        iconSize: Theme.font.l
                        color: root.markColour
                        Layout.leftMargin: Theme.pad.s
                    }

                    StyledText {
                        Layout.maximumWidth: panel.width * 0.6
                        text: root.toast?.text ?? ""
                        color: root.inkColour
                        font.pixelSize: Theme.font.m
                        elide: Text.ElideRight
                    }

                    // "x3" when the same toast arrived while it was up.
                    PluginBadge {
                        visible: (root.toast?.repeats ?? 1) > 1
                        text: `\u00d7${root.toast?.repeats ?? 1}`
                        tone: PluginBadge.Tone.Neutral
                    }

                    PluginChip {
                        visible: (root.toast?.actionLabel ?? "").length > 0
                        text: root.toast?.actionLabel ?? ""
                        tone: PluginChip.Tone.Accent
                        compact: true
                        onClicked: PluginToast.activate(root.toastId)
                    }
                }
            }

            // Auto-dismiss. Restarting on `toastId` covers a new toast; restarting on `at`
            // covers a coalesced repeat of the same one.
            Timer {
                id: dismissTimer
                interval: root.toast?.durationMs ?? 2600
                running: PluginToast.visible
                repeat: false
                onTriggered: PluginToast.dismiss(root.toastId)
            }

            Connections {
                target: root
                function onToastChanged(): void {
                    if (PluginToast.visible)
                        dismissTimer.restart();
                }
            }
        }
    }

    // Holds the window open for one animation after the last toast goes away.
    Timer {
        id: keepAlive
        interval: Theme.motion.fast + 60
        repeat: false
    }

    onToastChanged: {
        if (!PluginToast.visible)
            keepAlive.restart();
    }
}
