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
        currentIndex: root.selectionMode === RegionSelection.SelectionMode.RectCorners ? 0 : 1
        onCurrentIndexChanged: {
            const newMode = currentIndex === 0 ? RegionSelection.SelectionMode.RectCorners : RegionSelection.SelectionMode.Circle;
            if (root.selectionMode === newMode)
                return;
            // Deferred, not written straight from the handler. `currentIndex` is bound to
            // `selectionMode`, so assigning it here is a write during the evaluation of the
            // binding that triggered it - which Qt correctly calls a binding loop, and resolves
            // by dropping the binding. The tab strip then stops following the mode.
            //
            // The equality check above is not enough on its own: Qt reports the cycle, not the
            // value, so writing the same value in the same pass is still a loop.
            Qt.callLater(() => {
                if (root.selectionMode !== newMode)
                    root.selectionMode = newMode;
            });
        }
    }
}
