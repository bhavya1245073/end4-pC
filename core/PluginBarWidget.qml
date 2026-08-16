// Base type for a plugin's bar widget.
//
// Handles everything a bar widget has to get right and nothing to do with what it
// shows: sizing in a horizontal *and* a vertical bar, the text colour for whichever
// pill style the user picked, hover and click plumbing, and a tooltip or popup.
//
// The minimum useful widget:
//
//     import qs.core
//     import qs.modules.common.widgets
//
//     PluginBarWidget {
//         pluginId: "my-plugin"
//         tooltip: "It is currently o'clock"
//
//         StyledText {
//             text: DateTime.time
//             color: root.colText      // already correct for the pill style
//         }
//     }
//
// What you get without asking:
//
//   colText, colTextDim, colAccent   colours that survive light mode and every
//                                    `bar.cornerStyle`, which hand-picking does not
//   settings                         this plugin's settings, defaults filled in
//   vertical, mirrored               set by the bar; lay out along `vertical`
//   tooltip                          a string, or put a `popup:` component
//   clicked/rightClicked/scrolled    signals, already wired
//   hovered, containsPress           for your own state layers
//
// Content must size itself (a StyledText, a RowLayout, a Rectangle with
// implicitWidth). Don't anchor it to fill this item, or its size and the widget's
// will chase each other.

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    // Set this to get `settings`. Optional, but then `settings` is empty.
    property string pluginId: ""

    // Set by the bar. Lay content out along the bar when vertical.
    property bool vertical: false
    property bool mirrored: false

    // ------------------------------------------------------------------ content

    default property alias content: contentHolder.data

    // --------------------------------------------------------------- settings

    // This plugin's settings from plugins.json, with manifest defaults filled in.
    // Live, so binding to `settings.foo` follows the GUI with no reload.
    readonly property var settings: PluginConfig.of(root.pluginId)

    // ----------------------------------------------------------------- colours
    //
    // The bar's pill can be a tonal container or bare, depending on
    // `bar.cornerStyle`, and the readable text colour differs between them. Picking
    // one by hand is the single most common way a bar widget ends up unreadable in
    // light mode or in a style its author never tried.

    readonly property bool isMaterial: Config.options.bar.cornerStyle === 3

    readonly property color colText: root.isMaterial ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
    readonly property color colTextDim: Appearance.colors.colSubtext
    readonly property color colAccent: root.isMaterial ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colPrimary

    // ------------------------------------------------------------------ layout

    // Space around the content, along the bar's long axis.
    property real padding: root.isMaterial ? 4 : 8

    implicitWidth: root.vertical ? Appearance.sizes.verticalBarWidth : contentHolder.width + root.padding * 2
    implicitHeight: root.vertical ? contentHolder.height + root.padding * 2 : Appearance.sizes.barHeight

    // ------------------------------------------------------------ interaction

    // A one-line tooltip. Ignored if `popup` is set, since that is strictly better.
    property string tooltip: ""

    // A Component for a richer hover panel. Use PluginPopup as its root.
    property Component popup: null

    // Set false for a purely decorative widget, so it does not eat clicks.
    property bool interactive: true

    readonly property bool hovered: mouse.containsMouse
    readonly property bool containsPress: mouse.containsPress

    signal clicked
    signal rightClicked
    signal middleClicked

    // `up` is +1.
    signal scrolled(int up)

    // Declared before the content on purpose: later siblings draw on top, so a
    // widget that has its own MouseArea keeps priority and this one only sees what
    // the content did not handle.
    MouseArea {
        id: mouse

        anchors.fill: parent
        enabled: root.interactive
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

        // The same rule the built-in widgets follow, so tooltips across the bar
        // behave consistently with the user's setting.
        hoverEnabled: root.interactive && !Config.options.bar.tooltips.clickToShow

        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor

        onClicked: mouseEvent => {
            if (mouseEvent.button === Qt.RightButton)
                root.rightClicked();
            else if (mouseEvent.button === Qt.MiddleButton)
                root.middleClicked();
            else
                root.clicked();
        }

        onWheel: wheelEvent => root.scrolled(wheelEvent.angleDelta.y > 0 ? 1 : -1)

        StyledToolTip {
            // A MouseArea has containsMouse, not `hovered`, and StyledToolTip treats a
            // missing `hovered` as "always", so the hover test has to be explicit.
            extraVisibleCondition: false
            alternativeVisibleCondition: mouse.containsMouse && root.tooltip !== "" && root.popup === null
            text: root.tooltip
        }
    }

    Item {
        id: contentHolder
        anchors.centerIn: parent
        width: childrenRect.width
        height: childrenRect.height
    }

    // StyledPopup is a LazyLoader keyed on its hoverTarget, so it already builds
    // nothing until first hover. This only has to hand it something to watch.
    Loader {
        active: root.popup !== null
        sourceComponent: root.popup

        onLoaded: {
            if (item && item.hasOwnProperty("hoverTarget"))
                item.hoverTarget = mouse;
        }
    }
}
