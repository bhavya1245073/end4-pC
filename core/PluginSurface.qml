// One plugin file that renders correctly wherever it is mounted.
//
//     // BatterySurface.qml - the whole plugin's UI
//     PluginSurface {
//         pluginId: "battery"
//
//         barContent: Component {
//             PluginBarWidget { icon: "battery_android_full"; text: BatteryState.label }
//         }
//
//         flyoutContent: Component {
//             Column {
//                 PluginRow { label: qsTr("Health"); value: BatteryState.health }
//                 PluginRow { label: qsTr("Draw"); value: BatteryState.draw }
//             }
//         }
//
//         fullContent: Component {
//             BatteryHistoryChart {}
//         }
//     }
//
// The manifest points its bar widget, its desktop widget and its panel at this one file. Each
// host mounts it, `PluginResponsive.slot` says which one, and the matching slot is built. State
// lives in the plugin's own singleton, so all three views show the same thing - which is the
// part that gets out of step when a plugin is five files.
//
// ## Fallbacks
//
// A slot with no content falls back to the next most detailed one that exists: a missing
// flyout uses `fullContent`, a missing bar pill uses `flyoutContent` inside a pill. So a plugin
// can define one slot and appear everywhere, then add specialised versions later without
// changing where it is mounted.
//
// ## Only one slot is ever built
//
// `sourceComponent` picks exactly one. The others are Components - QML values that describe how
// to build something - and cost nothing until instantiated. A plugin with three rich slots
// mounted in the bar pays for the pill only.

import QtQuick
import qs.core
import qs.modules.common

Item {
    id: root

    property string pluginId: ""

    // The slots, in increasing order of room.
    property Component barContent: null
    property Component flyoutContent: null
    property Component fullContent: null

    // Where this instance thinks it is. Defaults to whatever the host declared through
    // PluginResponsive, and can be overridden for a host that mounts content itself.
    property int slot: PluginResponsive.slot

    readonly property Item content: slotLoader.item

    readonly property Component chosen: {
        switch (root.slot) {
        case PluginResponsive.Slot.BarPill:
            return root.barContent ?? root.flyoutContent ?? root.fullContent;
        case PluginResponsive.Slot.Flyout:
        case PluginResponsive.Slot.SidebarTab:
        case PluginResponsive.Slot.DesktopWidget:
            return root.flyoutContent ?? root.fullContent ?? root.barContent;
        case PluginResponsive.Slot.FloatingWindow:
        case PluginResponsive.Slot.Panel:
        case PluginResponsive.Slot.Settings:
            return root.fullContent ?? root.flyoutContent ?? root.barContent;
        default:
            // Mounted somewhere that did not say where. The richest slot is the safer guess: too
            // much detail in a small space is a layout problem, too little is a missing feature.
            return root.fullContent ?? root.flyoutContent ?? root.barContent;
        }
    }

    implicitWidth: slotLoader.item?.implicitWidth ?? 0
    implicitHeight: slotLoader.item?.implicitHeight ?? 0

    Loader {
        id: slotLoader
        anchors.fill: parent
        sourceComponent: root.chosen

        onLoaded: {
            // A slot's content may want to know, without importing anything.
            if (item.hasOwnProperty("surfaceSlot"))
                item.surfaceSlot = root.slot;
        }
    }

    Component.onCompleted: {
        if (!root.barContent && !root.flyoutContent && !root.fullContent) {
            console.warn(`[surface] ${root.pluginId || "a PluginSurface"} has no barContent,`
                + ` flyoutContent or fullContent, so it will render nothing`);
        }
    }
}
