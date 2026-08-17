pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Options toolbar
Toolbar {
    id: root

    // Use a synchronizer on these
    property var action
    property var selectionMode
    // Signals
    signal dismiss()

    ToolbarTabBar {
        id: tabBar
        tabButtonList: [
            {"icon": "activity_zone", "name": Translation.tr("Rect")},
            {"icon": "gesture", "name": Translation.tr("Circle")}
        ]
        // One-way: the mode drives the strip, and only a real click drives the mode.
        //
        // Binding `currentIndex` to the mode *and* writing the mode back from
        // `onCurrentIndexChanged` is a two-way binding. Qt resolves that by dropping the binding,
        // and the handler's first value wins - including the transient one from before
        // `selectionMode` has been synchronised in, which evaluates the ternary against undefined
        // and yields 1. That is why the snip tool opened with the lasso instead of the rectangle.
        currentIndex: root.selectionMode === RegionSelection.SelectionMode.RectCorners ? 0 : 1
        onTabClicked: index => {
            root.selectionMode = index === 0 ? RegionSelection.SelectionMode.RectCorners : RegionSelection.SelectionMode.Circle;
        }
    }
}
