pragma Singleton

// Where a plugin's content is currently mounted, so one file can render correctly in five
// places.
//
// The surfaces a plugin can appear on are genuinely different shapes: a bar pill is 24 px tall
// and horizontal, a flyout is ~320 px wide, a floating window is resizable, a sidebar tab is
// tall and narrow, a desktop widget is whatever the user dragged it to. Writing five QML files
// duplicates the state logic five times, and the copies drift.
//
// The host tells the content where it is by setting `PluginResponsive.slot` on the context it
// creates - PluginSurface does this, and so do the bar and desktop widget registries. Content
// then reads it:
//
//     PluginSurface {
//         barContent: Component { PluginBarWidget { ... } }
//         flyoutContent: Component { ... }
//         fullContent: Component { ... }
//     }
//
// or, for content that is the same shape everywhere and only wants to know how much room it
// has, just `PluginResponsive.isCompact`.
//
// ## Why a singleton and not a property on each surface
//
// Because the content is loaded from a URL and cannot see the object that loaded it. A property
// would have to be injected by every host, and a host that forgot would leave the content
// guessing - which is the situation this replaces. A singleton is readable from anywhere in the
// document, including from a nested delegate five levels down, which is where the question is
// usually asked.
//
// The slot is per-instantiation: PluginSurface sets it while building its slot's content and
// restores it after, so nesting works and a bar widget that opens a flyout does not leave the
// whole shell thinking everything is a bar pill.

import QtQuick
import Quickshell
import qs.core
import qs.modules.common

Singleton {
    id: root

    enum Slot { Unknown, BarPill, Flyout, FloatingWindow, SidebarTab, DesktopWidget, Panel, Settings }

    // Where the content being built right now lives.
    property int slot: PluginResponsive.Slot.Unknown

    readonly property string slotName: {
        switch (root.slot) {
        case PluginResponsive.Slot.BarPill:
            return "BarPill";
        case PluginResponsive.Slot.Flyout:
            return "Flyout";
        case PluginResponsive.Slot.FloatingWindow:
            return "FloatingWindow";
        case PluginResponsive.Slot.SidebarTab:
            return "SidebarTab";
        case PluginResponsive.Slot.DesktopWidget:
            return "DesktopWidget";
        case PluginResponsive.Slot.Panel:
            return "Panel";
        case PluginResponsive.Slot.Settings:
            return "Settings";
        default:
            return "Unknown";
        }
    }

    // Room for one line and an icon, and nothing else: a bar pill or an OSD.
    readonly property bool isCompact: root.slot === PluginResponsive.Slot.BarPill

    // Room for a few rows, but not for a two-column layout.
    readonly property bool isNarrow: root.isCompact
        || root.slot === PluginResponsive.Slot.Flyout
        || root.slot === PluginResponsive.Slot.SidebarTab

    // Resizable, keyboard-focusable, worth putting a toolbar in.
    readonly property bool isFull: root.slot === PluginResponsive.Slot.FloatingWindow
        || root.slot === PluginResponsive.Slot.Panel
        || root.slot === PluginResponsive.Slot.Settings

    // Vertical when the bar is vertical and the content is in it; vertical in a sidebar tab.
    readonly property int orientation: {
        if (root.slot === PluginResponsive.Slot.BarPill)
            return Config.options?.bar?.vertical ? Qt.Vertical : Qt.Horizontal;
        if (root.slot === PluginResponsive.Slot.SidebarTab)
            return Qt.Vertical;
        return Qt.Horizontal;
    }

    readonly property bool vertical: root.orientation === Qt.Vertical

    // A sensible default width for the slot, so content does not have to guess.
    readonly property real preferredWidth: {
        switch (root.slot) {
        case PluginResponsive.Slot.Flyout:
            return 320;
        case PluginResponsive.Slot.SidebarTab:
            return 300;
        case PluginResponsive.Slot.DesktopWidget:
            return 260;
        case PluginResponsive.Slot.FloatingWindow:
            return 520;
        default:
            return 0;   // as small as the content is
        }
    }

    // Hosts call this around building content. Returns the previous slot so it can be restored -
    // nesting is normal (a bar pill's flyout contains a list whose rows contain buttons), and a
    // host that clobbered the slot would leave everything below it mislabelled.
    function enter(slot: int): int {
        const previous = root.slot;
        root.slot = slot;
        return previous;
    }

    function leave(previous: int): void {
        root.slot = previous;
    }
}
