// A panel that slides in from an edge of the screen.
//
//     PluginDrawer {
//         id: drawer
//         edge: "right"
//         size: 380
//         title: "Notes"
//
//         NotesList { anchors.fill: parent }
//     }
//
//     drawer.toggle()
//
// The sidebars and the dock are this shape, and a plugin gets it without touching layer-shell:
// the drawer spans the edge it is attached to, slides rather than appears, dismisses on Escape
// and on a click outside, and can either float over windows or reserve space so that maximised
// windows shrink to fit (`exclusive`).
//
// `size` is width for a left/right drawer and height for a top/bottom one, so one property
// means "how big" whichever edge is chosen.
//
// Keyboard focus is exclusive while open, because a drawer usually contains something to type
// in; set `takesFocus: false` for one that does not.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    // "left", "right", "top", "bottom".
    property string edge: "right"

    // Width for left/right, height for top/bottom.
    property real size: 360

    // Fraction of the edge it covers, 0..1. 1 is the full edge.
    property real span: 1

    property string title: ""
    property string icon: ""
    property bool showHeader: title.length > 0 || icon.length > 0

    property bool open: false

    // Reserve screen space, so maximised windows do not sit underneath.
    property bool exclusive: false

    property bool closeOnEscape: true
    property bool closeOnClickOutside: true
    property bool takesFocus: true
    property bool animated: true

    // Content goes here. A Component, because the drawer's surface is created on demand and an
    // alias cannot cross into it; a child object is wrapped into a Component automatically.
    default property Component content: null

    signal opened
    signal closed

    function show(): void { root.open = true; }
    function hide(): void { root.open = false; }
    function toggle(): void { root.open = !root.open; }

    onOpenChanged: root.open ? root.opened() : root.closed()

    readonly property bool __horizontal: root.edge === "left" || root.edge === "right"

    LazyLoader {
        activeAsync: root.open

        PanelWindow {
            id: panel

            visible: root.open
            color: "transparent"
            exclusionMode: root.exclusive ? ExclusionMode.Auto : ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "quickshell:pluginDrawer"
            WlrLayershell.keyboardFocus: root.takesFocus ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            // Anchored to its edge and stretched along it. A drawer with span < 1 is centred on
            // that edge rather than pinned to a corner.
            anchors {
                left: root.edge !== "right"
                right: root.edge !== "left"
                top: root.edge !== "bottom"
                bottom: root.edge !== "top"
            }

            implicitWidth: root.__horizontal ? root.size : 0
            implicitHeight: root.__horizontal ? 0 : root.size

            Keys.onEscapePressed: if (root.closeOnEscape) root.open = false

            // Dismissal by clicking outside the card: the surface already covers the edge, so
            // the empty part of it is the "outside".
            TapHandler {
                enabled: root.closeOnClickOutside
                onTapped: eventPoint => {
                    const local = card.mapFromItem(null, eventPoint.position.x, eventPoint.position.y);
                    if (local.x < 0 || local.y < 0 || local.x > card.width || local.y > card.height)
                        root.open = false;
                }
            }

            Rectangle {
                id: card

                // The slide: offset by its own size on the axis it comes in from, so it starts
                // fully off-screen and ends flush.
                readonly property real hiddenOffset: root.animated ? (root.__horizontal ? root.size : root.size) : 0

                width: root.__horizontal ? root.size : parent.width * root.span
                height: root.__horizontal ? parent.height * root.span : root.size
                anchors.horizontalCenter: root.__horizontal ? undefined : parent.horizontalCenter
                anchors.verticalCenter: root.__horizontal ? parent.verticalCenter : undefined
                anchors.left: root.edge === "left" ? parent.left : undefined
                anchors.right: root.edge === "right" ? parent.right : undefined
                anchors.top: root.edge === "top" ? parent.top : undefined
                anchors.bottom: root.edge === "bottom" ? parent.bottom : undefined

                color: Theme.solid
                radius: Appearance.rounding.large
                border.width: 1
                border.color: Theme.outlineFaint

                transform: Translate {
                    x: !root.open && root.__horizontal ? (root.edge === "left" ? -card.hiddenOffset : card.hiddenOffset) : 0
                    y: !root.open && !root.__horizontal ? (root.edge === "top" ? -card.hiddenOffset : card.hiddenOffset) : 0

                    Behavior on x {
                        enabled: root.animated
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveEnter.duration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
                        }
                    }
                    Behavior on y {
                        enabled: root.animated
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveEnter.duration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
                        }
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.margins: Theme.pad.l
                        Layout.bottomMargin: 0
                        visible: root.showHeader
                        spacing: Theme.pad.s

                        MaterialSymbol {
                            visible: root.icon.length > 0
                            text: root.icon
                            iconSize: Theme.font.l
                            color: Theme.accent
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: root.title
                            font.pixelSize: Theme.font.l
                            font.weight: Font.DemiBold
                            color: Theme.text
                            elide: Text.ElideRight
                        }

                        PluginIconButton {
                            icon: "close"
                            tooltip: qsTr("Close")
                            onClicked: root.open = false
                        }
                    }

                    Loader {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.margins: Theme.pad.l
                        sourceComponent: root.content
                    }
                }
            }
        }
    }
}
