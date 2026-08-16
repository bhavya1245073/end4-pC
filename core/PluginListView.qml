// A scrolling list with search, empty state and a keyboard-navigable selection.
//
//     PluginListView {
//         items: PluginNotifications.history
//         searchFields: ["summary", "appName"]
//         emptyText: "No notifications"
//
//         delegate: PluginRow {
//             label: modelData.summary
//             value: modelData.appName
//         }
//     }
//
// What it adds over a bare ListView: a filter field that searches the fields you name, an empty
// state that says which of "nothing here" and "nothing matches" applies, momentum scrolling with
// the shell's own scrollbar, and Up/Down/Enter handling so a list is usable without a mouse.
//
// `items` is an array of plain objects. The delegate receives `modelData` and `index` as usual.
// Filtering is case-insensitive substring matching over `searchFields`, or over every string
// field when `searchFields` is empty.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.core
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    property var items: []

    // Which fields the filter looks at. Empty means every string-valued field.
    property var searchFields: []

    property bool searchable: true
    property string searchPlaceholder: qsTr("Filter")
    property string query: ""

    property string emptyText: qsTr("Nothing here")
    property string emptyIcon: "inbox"
    property string noMatchText: qsTr("No matches")

    property Component delegate: null

    property real spacing: Theme.pad.xs

    // Highlighted row, for keyboard use. -1 for none.
    property int currentIndex: -1

    signal activated(var item, int index)

    implicitWidth: 240
    implicitHeight: 200

    readonly property var filtered: {
        const query = root.query.trim().toLowerCase();
        if (query.length === 0)
            return root.items ?? [];
        const fields = root.searchFields ?? [];
        return (root.items ?? []).filter(item => {
            if (!item)
                return false;
            const keys = fields.length > 0 ? fields : Object.keys(item);
            for (const key of keys) {
                const value = item[key];
                if (typeof value === "string" && value.toLowerCase().includes(query))
                    return true;
                // Numbers are matched too, so filtering a list of ports or percentages works
                // without the caller stringifying everything first.
                if (typeof value === "number" && `${value}`.includes(query))
                    return true;
            }
            return false;
        });
    }

    readonly property int count: root.filtered.length

    function activateCurrent(): void {
        if (root.currentIndex < 0 || root.currentIndex >= root.filtered.length)
            return;
        root.activated(root.filtered[root.currentIndex], root.currentIndex);
    }

    function moveSelection(delta: int): void {
        if (root.filtered.length === 0) {
            root.currentIndex = -1;
            return;
        }
        const next = root.currentIndex + delta;
        root.currentIndex = Math.max(0, Math.min(root.filtered.length - 1, next));
        list.positionViewAtIndex(root.currentIndex, ListView.Contain);
    }

    // Filtering can shorten the list under the selection.
    onFilteredChanged: {
        if (root.currentIndex >= root.filtered.length)
            root.currentIndex = root.filtered.length - 1;
    }

    onCurrentIndexChanged: list.currentIndex = root.currentIndex

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.pad.s

        MaterialTextField {
            id: search
            Layout.fillWidth: true
            visible: root.searchable
            placeholderText: root.searchPlaceholder
            onTextChanged: root.query = text
            Keys.onDownPressed: root.moveSelection(1)
            Keys.onUpPressed: root.moveSelection(-1)
            Keys.onReturnPressed: root.activateCurrent()
            Keys.onEnterPressed: root.activateCurrent()
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: root.filtered
            spacing: root.spacing
            // Not bound to root.currentIndex: ListView writes its own currentIndex when a delegate
            // is clicked or the view is keyed, and root.currentIndex is written from those same
            // events - which is a binding loop, and Qt resolves one by dropping the binding, so the
            // highlight silently stops following the selection. Pushed one way instead.
            highlightMoveDuration: Appearance.animation.elementMoveFast.duration
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: StyledScrollBar {}

            delegate: Item {
                required property var modelData
                required property int index

                width: list.width
                implicitHeight: inner.item ? inner.item.implicitHeight : 0
                height: implicitHeight

                Loader {
                    id: inner
                    width: parent.width
                    sourceComponent: root.delegate
                    // The delegate is written by the plugin, so its properties are set by name
                    // rather than by required-property injection: a plugin that does not declare
                    // `index` should not fail to load.
                    onLoaded: {
                        if (item.hasOwnProperty("modelData"))
                            item.modelData = parent.modelData;
                        if (item.hasOwnProperty("index"))
                            item.index = parent.index;
                    }
                }

                TapHandler {
                    onTapped: {
                        root.currentIndex = parent.index;
                        root.activated(parent.modelData, parent.index);
                    }
                }
            }

            // Empty state. Two different messages, because "no matches" and "nothing here" send
            // the user in opposite directions.
            ColumnLayout {
                anchors.centerIn: parent
                visible: root.filtered.length === 0
                spacing: Theme.pad.s

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.query.length > 0 ? "search_off" : root.emptyIcon
                    iconSize: Theme.font.xl * 1.5
                    color: Theme.textFaint
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.query.length > 0 ? root.noMatchText : root.emptyText
                    font.pixelSize: Theme.font.s
                    color: Theme.textFaint
                }
            }
        }
    }
}
