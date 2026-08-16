// A complete desktop widget: opaque card, header, content, footer, drag, resize,
// and both position and size remembered - with none of it written per plugin.
//
//     PluginDesktopCard {
//         pluginId: "quote-of-the-day"
//         widgetId: "quoteDesktop"
//         title: qsTr("Quote of the day")
//         icon: "format_quote"
//         badge: QuoteState.category
//
//         actions: [
//             PluginIconButton { icon: "shuffle"; tooltip: qsTr("Another"); onClicked: QuoteState.next() },
//             PluginIconButton { icon: "content_copy"; tooltip: qsTr("Copy"); onClicked: PluginUtils.copy(QuoteState.text) }
//         ]
//
//         StyledText {
//             Layout.fillWidth: true
//             wrapMode: Text.Wrap
//             text: QuoteState.text
//             color: Theme.text
//         }
//
//         footer: [ StyledText { text: QuoteState.author; color: Theme.textFaint } ]
//     }
//
// The content slot is a ColumnLayout, so children use Layout.fillWidth /
// Layout.fillHeight and get real layout behaviour instead of fighting anchors. The
// card sizes itself to its content until the user resizes it, after which the stored
// size wins and the content is given the space.
//
// Draws `Theme.solid` rather than a layered surface: the layered ones are
// translucent, which over a photograph is unreadable.

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

PluginBackgroundWidget {
    id: root

    property string title: ""
    property string icon: ""
    property string badge: ""
    property int badgeTone: PluginChip.Tone.Muted

    // Slots. Assign as lists; children with no slot land in the content area.
    default property alias content: contentSlot.data
    property alias actions: actionSlot.data
    property alias footer: footerSlot.data

    property real padding: Theme.pad.xl
    property real spacing: Theme.pad.l
    property real radius: Theme.radius.l
    property color backgroundColor: Theme.solid
    property bool elevated: true
    property bool showHeaderSeparator: false

    property bool resizable: true
    // Most cards should size their own height from their content - a quote is as tall as
    // the quote. Set this for a card whose content should fill whatever space it is given
    // (a list, an image, a chart).
    property bool resizeVertically: false
    property real minWidth: 160
    property real minHeight: 100
    // The canvas is the screen, so a card can never be dragged-resized off it.
    property real maxWidth: root.canvas?.width ?? 3840
    property real maxHeight: root.canvas?.height ?? 2160

    // Text in a card sits on `Theme.solid`, not on the wallpaper, so the readable
    // colour is the normal one rather than the over-wallpaper override.
    colText: Theme.text

    readonly property real storedWidth: PluginConfig.widgetValue(root.pluginId, root.widgetId, "w", 0)
    readonly property real storedHeight: PluginConfig.widgetValue(root.pluginId, root.widgetId, "h", 0)

    // Content dictates size until the user says otherwise; after that the stored size
    // does, and the content stretches. Both are clamped so a card saved on a big
    // monitor is still usable on a small one.
    property real cardWidth: root.storedWidth > 0
        ? Math.max(root.minWidth, Math.min(root.storedWidth, root.maxWidth))
        : Math.max(root.minWidth, layout.implicitWidth + root.padding * 2)
    property real cardHeight: root.storedHeight > 0
        ? Math.max(root.minHeight, Math.min(root.storedHeight, root.maxHeight))
        : Math.max(root.minHeight, layout.implicitHeight + root.padding * 2)

    implicitWidth: root.cardWidth
    implicitHeight: root.cardHeight

    StyledRectangularShadow {
        target: background
        visible: root.elevated
    }

    Rectangle {
        id: background
        anchors.fill: parent
        radius: root.radius
        color: root.backgroundColor

        Behavior on color {
            animation: Theme.anim.fast.colorAnimation.createObject(this)
        }
    }

    ColumnLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: root.padding
        spacing: root.spacing

        RowLayout {
            id: header
            Layout.fillWidth: true
            spacing: Theme.pad.m
            // Collapses entirely when nothing sets a title, icon, badge or action, so a
            // bare card is just padding and content.
            visible: root.title !== "" || root.icon !== "" || root.badge !== "" || actionSlot.children.length > 0

            MaterialSymbol {
                visible: root.icon !== ""
                text: root.icon
                iconSize: Theme.font.l
                color: Theme.accent
            }

            StyledText {
                visible: root.title !== ""
                Layout.fillWidth: true
                text: root.title
                color: root.colText
                font.pixelSize: Theme.font.m
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            // Keeps the actions right-aligned when there is no title to do it.
            Item {
                Layout.fillWidth: true
                visible: root.title === ""
            }

            PluginChip {
                visible: root.badge !== ""
                text: root.badge
                tone: root.badgeTone
                compact: true
            }

            Row {
                id: actionSlot
                spacing: Theme.pad.xs
            }
        }

        Rectangle {
            Layout.fillWidth: true
            visible: root.showHeaderSeparator && header.visible
            implicitHeight: 1
            color: Theme.outlineDim
        }

        ColumnLayout {
            id: contentSlot
            Layout.fillWidth: true
            // Takes the slack when the card is bigger than its content, which is what
            // makes a resized card grow its content instead of growing its padding.
            Layout.fillHeight: true
            spacing: Theme.pad.m
        }

        RowLayout {
            id: footerSlot
            Layout.fillWidth: true
            spacing: Theme.pad.m
            visible: footerSlot.children.length > 0
        }
    }

    // ─────────────────────────────────────────────────────────────── resize ──
    // The shell's own grip, the same one five built-in desktop widgets use, so a plugin
    // card resizes with the same affordance in the same place - and follows if that
    // changes. It reports deltas; storing them is what a plugin should not have to write.
    ResizeHandler {
        anchorItem: background
        hoverActive: root.containsMouse
        locked: !root.draggable || !root.resizable
        currentWidth: root.cardWidth
        resizeMode: root.resizeVertically ? "diagonal" : "horizontal"
        strokeCol: Theme.accent

        onResized: newWidth => {
            root.cardWidth = Math.max(root.minWidth, Math.min(newWidth, root.maxWidth));
        }

        onResizedXY: (dx, dy, startWidth) => {
            if (!root.resizeVertically)
                return;
            // Height needs its own start value: the handler only tracks width.
            if (root.resizeStartHeight === 0)
                root.resizeStartHeight = root.cardHeight;
            root.cardHeight = Math.max(root.minHeight, Math.min(root.resizeStartHeight + dy, root.maxHeight));
        }

        onResizeFinished: {
            root.resizeStartHeight = 0;
            PluginConfig.setWidgetValue(root.pluginId, root.widgetId, "w", Math.round(root.cardWidth));
            if (root.resizeVertically)
                PluginConfig.setWidgetValue(root.pluginId, root.widgetId, "h", Math.round(root.cardHeight));

            // The assignments above broke the bindings; restore them so a later config
            // change - another monitor, a settings edit - still moves the card.
            root.cardWidth = Qt.binding(() => root.storedWidth > 0
                ? Math.max(root.minWidth, Math.min(root.storedWidth, root.maxWidth))
                : Math.max(root.minWidth, layout.implicitWidth + root.padding * 2));
            root.cardHeight = Qt.binding(() => root.storedHeight > 0
                ? Math.max(root.minHeight, Math.min(root.storedHeight, root.maxHeight))
                : Math.max(root.minHeight, layout.implicitHeight + root.padding * 2));
        }
    }

    // Only meaningful mid-drag; see onResizedXY.
    property real resizeStartHeight: 0
}
