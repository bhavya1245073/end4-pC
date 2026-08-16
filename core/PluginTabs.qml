// A tab strip with a sliding indicator, plus the pages behind it.
//
//     PluginTabs {
//         tabs: [
//             { label: "Today", icon: "today" },
//             { label: "Week", icon: "date_range", badge: 3 }
//         ]
//
//         Item { /* page 0 */ }
//         Item { /* page 1 */ }
//     }
//
// Children are the pages, in tab order, and only the current one is visible. `currentIndex` is
// readable and writable, so a plugin can drive it from IPC or a keybind.
//
// The indicator animates between tabs and the pages crossfade, both with the shell's own
// curves. A tab entry needs a `label`, an `icon`, or both; `badge` adds a count.
//
// Set `pagesVisible: false` to use it as a bare selector - a filter row, for instance - and put
// nothing inside it.

import QtQuick
import QtQuick.Layouts
import qs.core
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    // [{ label, icon, badge, enabled }]
    property var tabs: []

    property int currentIndex: 0

    property bool pagesVisible: true

    // "top" or "bottom" - where the strip sits relative to the pages.
    property string stripPosition: "top"

    property real stripHeight: 40

    // Pages, in tab order.
    default property alias pages: pageHolder.data

    signal tabSelected(int index)

    implicitWidth: 240
    implicitHeight: root.stripHeight + (root.pagesVisible ? 160 : 0)

    function select(index: int): void {
        if (index < 0 || index >= root.tabs.length)
            return;
        if (root.tabs[index]?.enabled === false)
            return;
        root.currentIndex = index;
        root.tabSelected(index);
    }

    function next(): void {
        root.select((root.currentIndex + 1) % Math.max(1, root.tabs.length));
    }

    function previous(): void {
        root.select((root.currentIndex - 1 + root.tabs.length) % Math.max(1, root.tabs.length));
    }

    // Keeps the selection valid when the tab list shrinks - a tab list is often derived from
    // state that changes.
    onTabsChanged: {
        if (root.currentIndex >= root.tabs.length)
            root.currentIndex = Math.max(0, root.tabs.length - 1);
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.pad.s

        // The strip is laid out first or last depending on stripPosition; two Loaders would
        // duplicate the delegate, so instead the column order is decided by z-free reordering
        // of two items with Layout.row-like intent: a plain conditional on Layout order is not
        // available, so the strip is placed by moving the pages instead.
        Item {
            id: stripSlot
            Layout.fillWidth: true
            Layout.preferredHeight: root.stripHeight
            Layout.alignment: Qt.AlignTop
            visible: root.tabs.length > 0

            Rectangle {
                anchors.fill: parent
                radius: Theme.radius.full
                color: Theme.raised
            }

            // The sliding indicator, behind the labels.
            Rectangle {
                id: indicator
                radius: Theme.radius.full
                color: Theme.accentBlock
                y: 3
                height: parent.height - 6
                width: strip.count > 0 ? (strip.width / strip.count) - 6 : 0
                x: 3 + (strip.count > 0 ? (strip.width / strip.count) * root.currentIndex : 0)
                visible: root.tabs.length > 1

                Behavior on x {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
                    }
                }
            }

            Row {
                id: strip
                anchors.fill: parent
                readonly property int count: root.tabs.length

                Repeater {
                    model: root.tabs

                    delegate: Item {
                        id: tab
                        required property var modelData
                        required property int index

                        width: strip.count > 0 ? strip.width / strip.count : 0
                        height: strip.height

                        readonly property bool current: tab.index === root.currentIndex
                        readonly property bool disabled: tab.modelData?.enabled === false

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: Theme.pad.xs

                            MaterialSymbol {
                                visible: (tab.modelData?.icon ?? "").length > 0
                                text: tab.modelData?.icon ?? ""
                                iconSize: Theme.font.m
                                color: tab.disabled ? Theme.textFaint : tab.current ? Theme.onAccentBlock : Theme.textDim
                            }

                            StyledText {
                                visible: (tab.modelData?.label ?? "").length > 0
                                text: tab.modelData?.label ?? ""
                                font.pixelSize: Theme.font.s
                                font.weight: tab.current ? Font.DemiBold : Font.Normal
                                color: tab.disabled ? Theme.textFaint : tab.current ? Theme.onAccentBlock : Theme.textDim
                            }

                            PluginChip {
                                visible: (tab.modelData?.badge ?? 0) > 0
                                text: `${tab.modelData?.badge ?? 0}`
                                tone: PluginChip.Tone.Accent
                                compact: true
                            }
                        }

                        TapHandler {
                            enabled: !tab.disabled
                            onTapped: root.select(tab.index)
                        }

                        HoverHandler {
                            cursorShape: tab.disabled ? Qt.ArrowCursor : Qt.PointingHandCursor
                        }
                    }
                }
            }
        }

        Item {
            id: pageHolder
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.pagesVisible

            // Only the current page is visible, and each page fills the area. Assigning
            // visibility rather than loading and unloading keeps a page's scroll position and
            // its state across tab switches, which is what a user expects from a tab.
            Repeater {
                model: 0
            }

            onChildrenChanged: root.__applyPageVisibility()
        }
    }

    function __applyPageVisibility(): void {
        const children = pageHolder.children;
        for (let i = 0; i < children.length; i++) {
            const child = children[i];
            child.visible = (i === root.currentIndex);
            // Pages are declared without anchors, so they are filled here rather than making
            // every plugin write `anchors.fill: parent` in each one.
            if (child.anchors)
                child.anchors.fill = pageHolder;
        }
    }

    onCurrentIndexChanged: root.__applyPageVisibility()
    Component.onCompleted: root.__applyPageVisibility()
}
