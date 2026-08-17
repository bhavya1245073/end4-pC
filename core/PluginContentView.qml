pragma ComponentBehavior: Bound

// A searchable, keyboard-navigable, image-aware view of a list of things.
//
// This is the component most plugins are: a GIF picker, an emoji picker, clipboard history,
// bookmarks, recent files, a font previewer, a colour palette. Written by hand each one is
// two hundred lines of GridView cell arithmetic, a debounce timer, a spinner, an empty
// state, arrow-key handling that has to know the column count, and a hover overlay - and
// each one gets a different subset of it right.
//
//     PluginContentView {
//         pluginId: "gif-picker"
//         items: GifState.results          // plain objects, any shape
//         loading: GifState.searching
//         mode: "grid"
//
//         onSearch: text => GifState.search(text)
//         onActivated: item => PluginUtils.copy(item.url)
//
//         actions: [
//             { id: "fav", icon: "star", label: qsTr("Favourite"), onTriggered: item => favourites.toggle(item) }
//         ]
//     }
//
// That is a complete, good picker: debounced remote search, a progressive thumbnail then
// animated preview, arrow keys and Enter, hover actions, a spinner while searching, an empty
// state, and animation that stops when the screen locks.
//
// ## Item shape
//
// Items are plain objects. Recognised fields, all optional:
//
//     id                    identity, for selection and favourites
//     title | name | label  the primary line
//     subtitle | comment    the dim second line
//     icon                  Material Symbol name
//     thumbnail             a still image URL, loaded first
//     preview               an animated image URL, loaded on hover
//     image                 used for both when there is only one
//     badge                 short text in a corner chip
//     category              matched against `category`
//     colour                a swatch instead of an image
//
// Anything else is ignored by the default delegate and available to a custom one.
//
// ## Local versus remote search
//
// Bind `onSearch` and the view assumes the *provider* filters: `items` is shown as given and
// the debounced query is handed over. Leave it unbound and the view filters `items` itself
// across `searchFields`. Doing both would double-filter results the server already narrowed,
// which is the bug that makes a remote picker show nothing for a query that clearly matched.
//
// ## The performance contract
//
// Animated previews play only when `PluginLifecycle.animate` is true and only for the item
// under the pointer, so a grid of forty GIFs costs one decoder rather than forty, and none
// behind a lock screen. Grid and list delegates are recycled by the view. Nothing is decoded
// for an item that has never been on screen.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.core
import qs.modules.common
import qs.modules.common.widgets

FocusScope {
    id: root

    // -------------------------------------------------------------- data in

    property string pluginId: ""
    property var items: []
    property bool loading: false

    // "grid" | "list" | "detail" | "carousel"
    property string mode: "grid"

    // Grid geometry. The view fits as many columns as it can and shares the remainder, so a
    // resize never leaves a ragged right edge.
    property real cellWidth: 132
    property real cellHeight: 108
    property real rowHeight: 52
    property real spacing: Theme.pad.s

    // ------------------------------------------------------------- searching

    property bool searchable: true
    property string searchPlaceholder: qsTr("Search")
    property int debounceMs: 180

    // Which fields local filtering looks at. Empty means every string field.
    property var searchFields: []

    // Live text, as typed.
    property string query: ""

    // Debounced text. What a provider is asked for, and what local filtering uses.
    readonly property string activeQuery: root.__debounced

    // Bind this for provider-side search. Its presence switches local filtering off.
    property var onSearch: null

    // Category chips above the list. [{ id, label, icon }]
    property var categories: []
    property string category: ""

    // ------------------------------------------------------------- behaviour

    // [{ id, icon, label, tone, onTriggered(item), shown(item) }]
    property var actions: []

    property string emptyIcon: "inbox"
    property string emptyText: qsTr("Nothing here yet")
    property string emptySubtitle: ""
    property string noMatchText: qsTr("No matches")

    // Replace the built-in delegate. Receives `modelData`, `index`, `selected`, `hovered`.
    property Component delegate: null

    // Show the count and the mode switch above the content.
    property bool showHeader: true
    property bool allowModeSwitch: false

    signal activated(var item, int index);
    signal previewed(var item, int index);
    signal dismissed();

    // ------------------------------------------------------------- data out

    readonly property var visibleItems: {
        const source = Array.isArray(root.items) ? root.items : [];
        const byCategory = root.category.length === 0
            ? source
            : source.filter(item => String(item?.category ?? "") === root.category);

        // A provider that searches for us has already filtered.
        if (typeof root.onSearch === "function")
            return byCategory;

        const query = root.__debounced.trim().toLowerCase();
        if (query.length === 0)
            return byCategory;

        const fields = root.searchFields ?? [];
        return byCategory.filter(item => {
            if (!item)
                return false;
            const keys = fields.length > 0 ? fields : Object.keys(item);
            for (const key of keys) {
                const value = item[key];
                if (typeof value === "string" && value.toLowerCase().includes(query))
                    return true;
                if (typeof value === "number" && `${value}`.includes(query))
                    return true;
            }
            return false;
        });
    }

    readonly property int count: root.visibleItems.length
    readonly property bool empty: root.count === 0 && !root.loading

    property int currentIndex: -1
    readonly property var currentItem: (root.currentIndex >= 0 && root.currentIndex < root.count)
        ? root.visibleItems[root.currentIndex] : null

    implicitWidth: 360
    implicitHeight: 280

    // ------------------------------------------------------------- functions

    function focusSearch(): void {
        if (root.searchable)
            searchField.forceActiveFocus();
    }

    function clearSearch(): void {
        root.query = "";
        root.__debounced = "";
        searchField.text = "";
    }

    function activateCurrent(): void {
        if (!root.currentItem)
            return;
        root.activated(root.currentItem, root.currentIndex);
    }

    function select(index: int): void {
        if (root.count === 0) {
            root.currentIndex = -1;
            return;
        }
        root.currentIndex = Math.max(0, Math.min(root.count - 1, index));
        root.__positionAt(root.currentIndex);
    }

    // Arrow keys. `columns` is 1 in list mode, so the same two calls serve both.
    function moveBy(delta: int): void {
        if (root.count === 0)
            return;
        // From nothing selected, Down selects the first rather than the second.
        root.select(root.currentIndex < 0 ? (delta > 0 ? 0 : root.count - 1) : root.currentIndex + delta);
    }

    function moveRow(delta: int): void {
        root.moveBy(delta * root.columns);
    }

    readonly property int columns: {
        if (root.mode !== "grid" && root.mode !== "carousel")
            return 1;
        const usable = Math.max(1, root.width - Theme.pad.s * 2);
        return Math.max(1, Math.floor(usable / Math.max(24, root.cellWidth)));
    }

    // --------------------------------------------------------- search plumbing

    property string __debounced: ""

    onQueryChanged: debounce.restart()

    Timer {
        id: debounce
        interval: Math.max(0, root.debounceMs)
        repeat: false
        onTriggered: {
            if (root.__debounced === root.query)
                return;
            root.__debounced = root.query;
            root.currentIndex = -1;
            if (typeof root.onSearch === "function") {
                try {
                    root.onSearch(root.__debounced);
                } catch (e) {
                    console.warn(`[contentView] ${root.pluginId}: onSearch threw:`, e);
                }
            }
        }
    }

    // A shorter list can strand the selection past the end.
    onCountChanged: {
        if (root.currentIndex >= root.count)
            root.currentIndex = root.count - 1;
    }

    function __positionAt(index: int): void {
        if (root.mode === "list" || root.mode === "detail")
            listView.positionViewAtIndex(index, ListView.Contain);
        else
            gridView.positionViewAtIndex(index, GridView.Contain);
    }

    // Keyboard for the whole view, so arrows work while the search field has focus - which is
    // where focus is while someone is typing, and therefore where the arrow keys are pressed.
    Keys.onPressed: event => {
        switch (event.key) {
        case Qt.Key_Down:
            root.mode === "list" || root.mode === "detail" ? root.moveBy(1) : root.moveRow(1);
            event.accepted = true;
            break;
        case Qt.Key_Up:
            root.mode === "list" || root.mode === "detail" ? root.moveBy(-1) : root.moveRow(-1);
            event.accepted = true;
            break;
        case Qt.Key_Right:
            if (root.columns > 1) {
                root.moveBy(1);
                event.accepted = true;
            }
            break;
        case Qt.Key_Left:
            if (root.columns > 1) {
                root.moveBy(-1);
                event.accepted = true;
            }
            break;
        case Qt.Key_Home:
            root.select(0);
            event.accepted = true;
            break;
        case Qt.Key_End:
            root.select(root.count - 1);
            event.accepted = true;
            break;
        case Qt.Key_PageDown:
            root.moveRow(3);
            event.accepted = true;
            break;
        case Qt.Key_PageUp:
            root.moveRow(-3);
            event.accepted = true;
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            root.activateCurrent();
            event.accepted = true;
            break;
        case Qt.Key_Tab:
            // Preview rather than move focus: in a picker there is nowhere else for focus to
            // go, and a preview key is worth more than a focus cycle of one.
            if (root.currentItem) {
                root.previewed(root.currentItem, root.currentIndex);
                event.accepted = true;
            }
            break;
        case Qt.Key_Escape:
            if (root.query.length > 0) {
                root.clearSearch();
                event.accepted = true;
            } else {
                root.dismissed();
                event.accepted = true;
            }
            break;
        }
    }

    // ------------------------------------------------------------------ layout

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.pad.s

        // Search row: field, a clear button that only exists when there is something to
        // clear, and a spinner in place of nothing while loading.
        RowLayout {
            Layout.fillWidth: true
            visible: root.searchable
            spacing: Theme.pad.s

            MaterialTextField {
                id: searchField
                Layout.fillWidth: true
                placeholderText: root.searchPlaceholder
                onTextChanged: root.query = text
                // Arrows and Enter belong to the view; everything else to the field.
                Keys.forwardTo: [root]
            }

            PluginIconButton {
                visible: root.query.length > 0
                icon: "close"
                tooltip: qsTr("Clear")
                onClicked: root.clearSearch()
            }

            Item {
                visible: root.loading
                implicitWidth: 18
                implicitHeight: 18
                Layout.alignment: Qt.AlignVCenter

                // Rotating arc rather than MaterialLoadingIndicator: this is 18 px in a row of
                // controls, and that component is a 48 px hero.
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: 2
                    border.color: Theme.fade(Theme.accent, 0.25)
                }

                Rectangle {
                    id: spinnerArc
                    width: 6
                    height: 6
                    radius: 3
                    color: Theme.accent
                    x: parent.width / 2 - 3
                    y: 0

                    transform: Rotation {
                        origin.x: 3
                        origin.y: 9
                        angle: spinnerSpin.angle
                    }
                }

                QtObject {
                    id: spinnerSpin
                    property real angle: 0
                }

                NumberAnimation {
                    target: spinnerSpin
                    property: "angle"
                    from: 0
                    to: 360
                    duration: 900
                    loops: Animation.Infinite
                    // Stops with the rest of the shell's animation, and when nothing is loading.
                    running: root.loading && PluginLifecycle.animate
                }
            }
        }

        // Category chips.
        Flow {
            Layout.fillWidth: true
            visible: (root.categories?.length ?? 0) > 0
            spacing: Theme.pad.xs

            Repeater {
                model: [{ id: "", label: qsTr("All"), icon: "" }].concat(root.categories ?? [])

                delegate: PluginChip {
                    required property var modelData

                    text: modelData.label ?? modelData.id ?? ""
                    icon: modelData.icon ?? ""
                    compact: true
                    tone: root.category === (modelData.id ?? "")
                        ? PluginChip.Tone.Accent
                        : PluginChip.Tone.Muted
                    onClicked: {
                        root.category = modelData.id ?? "";
                        root.currentIndex = -1;
                    }
                }
            }
        }

        // Header: count on the left, mode switch on the right.
        RowLayout {
            Layout.fillWidth: true
            visible: root.showHeader && (root.count > 0 || root.allowModeSwitch)
            spacing: Theme.pad.s

            StyledText {
                text: root.__debounced.length > 0
                    ? qsTr("%1 of %2").arg(root.count).arg(Array.isArray(root.items) ? root.items.length : 0)
                    : qsTr("%n item(s)", "", root.count)
                color: Theme.textFaint
                font.pixelSize: Theme.font.xs
            }

            Item {
                Layout.fillWidth: true
            }

            Repeater {
                model: root.allowModeSwitch ? [
                    { id: "grid", icon: "grid_view" },
                    { id: "list", icon: "view_list" },
                    { id: "detail", icon: "view_agenda" }
                ] : []

                delegate: PluginIconButton {
                    required property var modelData

                    icon: modelData.icon
                    tooltip: modelData.id
                    checked: root.mode === modelData.id
                    onClicked: root.mode = modelData.id
                }
            }
        }

        // The content itself. One Loader-free switch: both views exist, one is visible, so
        // switching modes keeps the model warm and does not re-decode every image.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            GridView {
                id: gridView
                anchors.fill: parent
                visible: root.mode === "grid" || root.mode === "carousel"
                clip: true
                model: root.visibleItems

                // Shares the leftover width between columns instead of leaving a ragged edge.
                cellWidth: root.columns > 0 ? Math.floor(width / root.columns) : root.cellWidth
                cellHeight: root.cellHeight + root.spacing

                flow: root.mode === "carousel" ? GridView.FlowTopToBottom : GridView.FlowLeftToRight
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: root.cellHeight * 3

                ScrollBar.vertical: StyledScrollBar {}

                delegate: Item {
                    id: gridCell
                    required property var modelData
                    required property int index

                    width: gridView.cellWidth
                    height: gridView.cellHeight

                    Loader {
                        anchors.fill: parent
                        anchors.margins: root.spacing / 2
                        sourceComponent: root.delegate ?? builtinCard
                        // Not required properties: a custom delegate should be able to declare
                        // only what it uses, and a required property it forgot would make the
                        // Loader fail silently.
                        onLoaded: {
                            item.modelData = gridCell.modelData;
                            item.index = gridCell.index;
                        }
                        Binding {
                            target: parent.item ?? null
                            property: "selected"
                            value: root.currentIndex === gridCell.index
                            when: (parent.item?.hasOwnProperty("selected") ?? false)
                        }
                    }
                }
            }

            ListView {
                id: listView
                anchors.fill: parent
                visible: root.mode === "list" || root.mode === "detail"
                clip: true
                model: root.visibleItems
                spacing: root.spacing
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: root.rowHeight * 6

                ScrollBar.vertical: StyledScrollBar {}

                delegate: Item {
                    id: listRow
                    required property var modelData
                    required property int index

                    width: listView.width
                    height: root.mode === "detail" ? root.rowHeight * 1.8 : root.rowHeight

                    Loader {
                        anchors.fill: parent
                        sourceComponent: root.delegate ?? builtinRow
                        onLoaded: {
                            item.modelData = listRow.modelData;
                            item.index = listRow.index;
                        }
                        Binding {
                            target: parent.item ?? null
                            property: "selected"
                            value: root.currentIndex === listRow.index
                            when: (parent.item?.hasOwnProperty("selected") ?? false)
                        }
                    }
                }
            }

            // Empty state. Not an overlay on an empty view - the view is genuinely empty, and
            // this replaces it, so there is no scrollbar over a message.
            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width - Theme.pad.xl * 2, 280)
                visible: root.empty
                spacing: Theme.pad.s

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.__debounced.length > 0 ? "search_off" : root.emptyIcon
                    iconSize: 44
                    color: Theme.textFaint
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.__debounced.length > 0 ? root.noMatchText : root.emptyText
                    color: Theme.textDim
                    font.pixelSize: Theme.font.m
                    wrapMode: Text.Wrap
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    visible: root.emptySubtitle.length > 0 && root.__debounced.length === 0
                    text: root.emptySubtitle
                    color: Theme.textFaint
                    font.pixelSize: Theme.font.s
                    wrapMode: Text.Wrap
                }
            }
        }
    }

    // --------------------------------------------------------- built-in cards

    // A card: image or colour or icon, a label, a badge, and hover actions.
    Component {
        id: builtinCard

        Rectangle {
            id: card

            property var modelData: null
            property int index: -1
            property bool selected: false

            readonly property bool hovered: cardMouse.containsMouse

            radius: Theme.radius.m
            color: card.selected ? Theme.accentBlock
                : card.hovered ? Theme.surfaceHigh
                : Theme.surface
            border.width: card.selected ? 2 : 1
            border.color: card.selected ? Theme.accent : Theme.fade(Theme.outline, 0.35)

            Behavior on color {
                ColorAnimation {
                    duration: Theme.motion.fast
                }
            }

            PluginProgressiveImage {
                id: cardImage
                anchors.fill: parent
                anchors.margins: 1
                radius: card.radius - 1
                thumbnail: card.modelData?.thumbnail ?? card.modelData?.image ?? ""
                preview: card.modelData?.preview ?? ""
                // The pointer is the play trigger: one decoder for the grid, not one per cell.
                playing: card.hovered
                fallbackIcon: card.modelData?.icon ?? ""
                fallbackColour: card.modelData?.colour ?? ""
                label: cardImage.hasMedia ? "" : root.__titleOf(card.modelData)
            }

            // Caption strip, only when there is an image to caption.
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: caption.implicitHeight + Theme.pad.s
                visible: cardImage.hasMedia && root.__titleOf(card.modelData).length > 0
                color: Theme.fade(Theme.scrim, 0.55)
                bottomLeftRadius: card.radius - 1
                bottomRightRadius: card.radius - 1

                StyledText {
                    id: caption
                    anchors.fill: parent
                    anchors.margins: Theme.pad.xs
                    text: root.__titleOf(card.modelData)
                    color: "white"
                    font.pixelSize: Theme.font.xs
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            PluginBadge {
                anchors { top: parent.top; right: parent.right; margins: Theme.pad.xs }
                visible: (card.modelData?.badge ?? "").length > 0
                text: card.modelData?.badge ?? ""
                tone: PluginBadge.Tone.Accent
            }

            // Hover actions, top-left so they never sit under the badge.
            Row {
                anchors { top: parent.top; left: parent.left; margins: Theme.pad.xs }
                spacing: Theme.pad.xs
                visible: card.hovered && (root.actions?.length ?? 0) > 0

                Repeater {
                    model: root.__actionsFor(card.modelData)

                    delegate: PluginIconButton {
                        required property var modelData

                        icon: modelData.icon ?? "more_horiz"
                        tooltip: modelData.label ?? ""
                        size: 24
                        onClicked: root.__runAction(modelData, card.modelData, card.index)
                    }
                }
            }

            MouseArea {
                id: cardMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                // Below the action buttons in stacking order, so they win the click.
                z: -1

                onEntered: root.currentIndex = card.index
                onClicked: mouse => {
                    root.currentIndex = card.index;
                    if (mouse.button === Qt.MiddleButton)
                        root.previewed(card.modelData, card.index);
                    else
                        root.activated(card.modelData, card.index);
                }
            }
        }
    }

    // A row: icon or thumbnail, title, subtitle, actions on hover.
    Component {
        id: builtinRow

        Rectangle {
            id: row

            property var modelData: null
            property int index: -1
            property bool selected: false

            readonly property bool hovered: rowMouse.containsMouse

            radius: Theme.radius.s
            color: row.selected ? Theme.accentBlock
                : row.hovered ? Theme.surfaceHigh
                : "transparent"

            Behavior on color {
                ColorAnimation {
                    duration: Theme.motion.fast
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.pad.m
                anchors.rightMargin: Theme.pad.s
                spacing: Theme.pad.m

                PluginProgressiveImage {
                    visible: (row.modelData?.thumbnail ?? row.modelData?.image ?? row.modelData?.colour ?? "").length > 0
                    implicitWidth: parent.height - Theme.pad.s * 2
                    implicitHeight: parent.height - Theme.pad.s * 2
                    radius: Theme.radius.xs
                    thumbnail: row.modelData?.thumbnail ?? row.modelData?.image ?? ""
                    preview: row.modelData?.preview ?? ""
                    playing: row.hovered
                    fallbackColour: row.modelData?.colour ?? ""
                }

                MaterialSymbol {
                    visible: (row.modelData?.icon ?? "").length > 0
                        && (row.modelData?.thumbnail ?? row.modelData?.image ?? "").length === 0
                    text: row.modelData?.icon ?? ""
                    iconSize: Theme.font.l
                    color: row.selected ? Theme.onAccentBlock : Theme.textDim
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: root.__titleOf(row.modelData)
                        color: row.selected ? Theme.onAccentBlock : Theme.text
                        font.pixelSize: Theme.font.m
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: root.__subtitleOf(row.modelData).length > 0
                        text: root.__subtitleOf(row.modelData)
                        color: Theme.textFaint
                        font.pixelSize: Theme.font.xs
                        elide: Text.ElideRight
                        maximumLineCount: root.mode === "detail" ? 2 : 1
                        wrapMode: root.mode === "detail" ? Text.Wrap : Text.NoWrap
                    }
                }

                PluginBadge {
                    visible: (row.modelData?.badge ?? "").length > 0
                    text: row.modelData?.badge ?? ""
                    tone: PluginBadge.Tone.Neutral
                }

                Row {
                    spacing: Theme.pad.xs
                    visible: row.hovered && (root.actions?.length ?? 0) > 0

                    Repeater {
                        model: root.__actionsFor(row.modelData)

                        delegate: PluginIconButton {
                            required property var modelData

                            icon: modelData.icon ?? "more_horiz"
                            tooltip: modelData.label ?? ""
                            size: 24
                            onClicked: root.__runAction(modelData, row.modelData, row.index)
                        }
                    }
                }
            }

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                z: -1
                onEntered: root.currentIndex = row.index
                onClicked: {
                    root.currentIndex = row.index;
                    root.activated(row.modelData, row.index);
                }
            }
        }
    }

    // --------------------------------------------------------------- helpers

    function __titleOf(item: var): string {
        return String(item?.title ?? item?.name ?? item?.label ?? item?.text ?? "");
    }

    function __subtitleOf(item: var): string {
        return String(item?.subtitle ?? item?.comment ?? item?.description ?? "");
    }

    // `shown` lets an action apply to some items only - a "Restore" that appears on archived
    // rows and nowhere else - without the caller filtering per delegate.
    function __actionsFor(item: var): var {
        return (root.actions ?? []).filter(action => {
            if (typeof action?.shown !== "function")
                return true;
            try {
                return action.shown(item) === true;
            } catch (e) {
                return false;
            }
        });
    }

    function __runAction(action: var, item: var, index: int): void {
        if (typeof action?.onTriggered !== "function")
            return;
        try {
            action.onTriggered(item, index);
        } catch (e) {
            console.warn(`[contentView] ${root.pluginId}: action "${action.id ?? action.icon}" threw:`, e);
            PluginToast.error(qsTr("That action failed"));
        }
    }
}
