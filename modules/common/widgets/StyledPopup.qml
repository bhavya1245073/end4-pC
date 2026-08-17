import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

LazyLoader {
    id: root
    property Item hoverTarget
    default property Item contentItem
    property real popupBackgroundMargin: 0

    // When the popup goes away.
    //
    //   "pill"    (default) open while the pointer is on the widget that owns it, gone the moment it
    //             leaves. Right for anything read-only: the clock, the weather, a chart.
    //   "manual"  opened by clicking the widget, and it stays until the user clicks the widget again,
    //             clicks anywhere else, or presses Escape.
    //
    // Anything with a button in it needs "manual". A hover popup is a separate Wayland surface, and
    // the pointer has to leave the widget's surface to reach it - at which point "open while hovering
    // the widget" is false and the window is destroyed while the pointer is still travelling. Keeping
    // it alive by tracking hover on the popup as well means relying on a pointer-leave event arriving
    // for a surface that maps and unmaps under the cursor, and when one goes missing the popup is
    // stuck on screen instead. Clicking has neither problem: nothing about it is a race.
    property string dismiss: "pill"

    readonly property bool hoverDriven: root.dismiss !== "manual"

    // "manual" only. PluginBarWidget flips this on click.
    property bool open: false

    active: root.hoverDriven ? !!(root.hoverTarget && root.hoverTarget.containsMouse) : root.open

    function close(): void {
        root.open = false;
    }

    function toggle(): void {
        root.open = !root.open;
    }

    readonly property bool barVertical: Config.options.bar.vertical
    readonly property string barEdge: {
        if (!barVertical) return Config.options.bar.bottom ? "bottom" : "top"
        return Config.options.bar.bottom ? "right" : "left"
    }
    readonly property real barThickness: barVertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.barHeight

    component: PanelWindow {
        id: popupWindow

        // Bring contentItem reference into this scope
        property Item innerContent: root.contentItem

        // In "manual" mode the window covers the screen: the card is drawn where it always was, and
        // the rest is a transparent catcher, which is what makes "click anywhere else to close" work
        // without a second surface and without any hover tracking. In hover mode the window is only
        // as big as the card, exactly as before.
        readonly property bool catcher: !root.hoverDriven

        color: "transparent"
        anchors.left: popupWindow.catcher || root.barEdge !== "right"
        anchors.right: popupWindow.catcher || root.barEdge === "right"
        anchors.top: popupWindow.catcher || root.barEdge !== "bottom"
        anchors.bottom: popupWindow.catcher || root.barEdge === "bottom"

        implicitWidth: popupBackground.implicitWidth + Appearance.sizes.elevationMargin * 2 + root.popupBackgroundMargin
        implicitHeight: popupBackground.implicitHeight + Appearance.sizes.elevationMargin * 2 + root.popupBackgroundMargin

        readonly property real centerOffsetX: {
            const base = root.QsWindow?.mapFromItem(
                root.hoverTarget,
                (root.hoverTarget.width - popupBackground.implicitWidth) / 2, 0
            ).x ?? 0
            const margin = Appearance.sizes.elevationMargin
            const maxLeft = popupWindow.screen.width - popupBackground.implicitWidth - margin - 10
            return Math.max(margin, Math.min(base, maxLeft))
        }
        readonly property real centerOffsetY: {
            const base = root.QsWindow?.mapFromItem(
                root.hoverTarget,
                0, (root.hoverTarget.height - popupBackground.implicitHeight) / 2
            ).y ?? 0
            const margin = Appearance.sizes.elevationMargin
            const maxTop = popupWindow.screen.height - popupBackground.implicitHeight - margin - 15
            return Math.max(margin, Math.min(base, maxTop))
        }

        // In catcher mode the whole window takes input, which is what makes a click outside the card
        // close it; in hover mode only the card does, so the rest of the screen is untouched.
        //
        // `item: null` on its own is an *empty* region, not an absent one - the window then accepts no
        // clicks anywhere, which looked exactly like a popup whose contents had stopped existing.
        mask: Region {
            item: popupWindow.catcher ? null : popupBackground
            width: popupWindow.catcher ? popupWindow.width : 0
            height: popupWindow.catcher ? popupWindow.height : 0
        }
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0

        // Where the card sits, as offsets from the screen edges. In hover mode these are the window's
        // own margins - the window is card-sized. In catcher mode the window is the whole screen and
        // the same numbers position the card inside it, so the popup appears in exactly the same place
        // either way.
        readonly property real offsetLeft: {
            if (root.barEdge === "right") return 0
            if (root.barEdge === "left") return root.barThickness
            return centerOffsetX
        }
        readonly property real offsetTop: {
            if (root.barEdge === "bottom") return 0
            if (root.barEdge === "top") return root.barThickness
            return centerOffsetY
        }
        readonly property real offsetRight: root.barEdge === "right" ? root.barThickness : 0
        readonly property real offsetBottom: root.barEdge === "bottom" ? root.barThickness : 0

        margins {
            left: popupWindow.catcher ? 0 : popupWindow.offsetLeft
            top: popupWindow.catcher ? 0 : popupWindow.offsetTop
            right: popupWindow.catcher ? 0 : popupWindow.offsetRight
            bottom: popupWindow.catcher ? 0 : popupWindow.offsetBottom
        }
        WlrLayershell.namespace: "quickshell:popup"
        WlrLayershell.layer: WlrLayer.Overlay
        // Escape closes it, so it needs to be able to hear the key. Only in catcher mode: a hover
        // popup must never take focus from what the user is typing in.
        WlrLayershell.keyboardFocus: popupWindow.catcher ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        // Click anywhere that is not the card. Present only in catcher mode, where the window covers
        // the screen; in hover mode the window is card-sized and this would sit under the card.
        MouseArea {
            anchors.fill: parent
            enabled: popupWindow.catcher
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: root.close()
        }

        Item {
            id: cardSlot

            // Card-sized and placed by hand when the window is the whole screen; the whole window
            // otherwise.
            x: popupWindow.catcher ? popupWindow.offsetLeft : 0
            y: popupWindow.catcher ? popupWindow.offsetTop : 0
            width: popupWindow.catcher ? popupWindow.implicitWidth : popupWindow.width
            height: popupWindow.catcher ? popupWindow.implicitHeight : popupWindow.height

            focus: popupWindow.catcher
            Keys.onEscapePressed: root.close()

            StyledRectangularShadow {
                target: popupBackground
            }

            Rectangle {
                id: popupBackground
                readonly property real margin: 8

                anchors {
                    fill: parent
                    leftMargin: Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.left)
                    rightMargin: Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.right)
                    topMargin: Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.top)
                    bottomMargin: Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.bottom)
                }

                // Use local reference instead of crossing LazyLoader scope boundary
                implicitWidth: (popupWindow.innerContent?.implicitWidth ?? 0) + margin * 2
                implicitHeight: (popupWindow.innerContent?.implicitHeight ?? 0) + margin * 2

                color: Appearance.colors.colLayer1Base
                radius: Appearance.rounding.normal + 4
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                // Reparent content here once the window is ready
                Component.onCompleted: {
                    if (popupWindow.innerContent) {
                        popupWindow.innerContent.parent = popupBackground
                        popupWindow.innerContent.anchors.centerIn = popupBackground
                    }
                }
            }
        }
    }
}