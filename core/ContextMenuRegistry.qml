pragma Singleton

// Items in the desktop right-click menu, built-in and plugin alike.
//
// The menu's top-level rows were hardcoded, so the only way a plugin could appear
// there was the Widgets submenu. A plugin now declares a row:
//
//     "contextMenuItems": [
//         {
//             "id": "newNote",
//             "label": "New note",
//             "icon": "note_add",
//             "order": 25,
//             "ipc": { "target": "notes", "function": "create" }
//         }
//     ]
//
// An item does one of three things, checked in this order:
//
//     ipc    { target, function, args? }   calls a PluginIpc function in-process
//     exec   ["cmd", "arg"]                spawns a process, argv - never a shell string
//     entry  "MySubmenu.qml"               opens a submenu drawn by the plugin
//
// `order` places it among the built-ins, which sit at 10, 20, 30, 40 and 100 - so 25
// lands between Widgets and DropShelf. Plugin items default to 50, which puts them
// after the built-in rows and before Settings.

import QtQuick
import Quickshell

Singleton {
    id: root

    // The built-in rows, declared here rather than in the menu, so the menu renders one
    // list and a plugin row is indistinguishable from a shell row.
    //
    // `builtin` names a case the menu handles itself: these open submenus and manage
    // hover state, which is not something a manifest can express.
    readonly property var builtins: [
        { id: "wallpaper", label: "Wallpaper & style", icon: "format_paint", order: 10, builtin: "wallpaper" },
        { id: "widgets", label: "Widgets", icon: "widgets", order: 20, builtin: "widgets" },
        { id: "dropshelf", label: "DropShelf", icon: "stacks", order: 30, builtin: "dropshelf" },
        { id: "livewallpaper", label: "Live Wallpaper", icon: "video_template", order: 40, builtin: "livewallpaper" },
        { id: "settings", label: "Settings", icon: "settings", order: 100, builtin: "settings" }
    ]

    readonly property var all: Stable.list("ContextMenuRegistry.all", (() => {
        const entries = root.builtins.map(item => Object.assign({ pluginId: "", enabled: true }, item));

        for (const item of PluginRegistry.contextMenuItems) {
            if (!item.id || !item.label)
                continue;
            entries.push({
                id: `${item.pluginId}:${item.id}`,
                label: item.label,
                icon: item.icon ?? "extension",
                order: item.order ?? 50,
                builtin: "",
                pluginId: item.pluginId,
                ipc: item.ipc ?? null,
                exec: item.exec ?? null,
                url: item.url ?? "",
                enabled: true
            });
        }

        return entries.sort((a, b) => (a.order ?? 50) - (b.order ?? 50));
    })())

    // Run a plugin item. Returns true if the menu should close - which it should for an
    // action, and should not for a row that opened a submenu.
    function activate(item: var): bool {
        if (!item)
            return true;

        if (item.ipc?.target && item.ipc?.function) {
            // In-process, so a menu item costs no process spawn and can talk to live state.
            const handled = PluginRegistry.invokeIpc(item.ipc.target, item.ipc.function, item.ipc.args ?? []);
            if (!handled)
                console.warn(`[plugins] context menu item ${item.id}: no IPC ${item.ipc.target}.${item.ipc.function}`);
            return true;
        }

        if (Array.isArray(item.exec) && item.exec.length > 0) {
            PluginUtils.exec(item.exec);
            return true;
        }

        if (item.url)
            return false;   // the menu opens the submenu itself

        console.warn(`[plugins] context menu item ${item.id} does nothing: needs ipc, exec or entry`);
        return true;
    }
}
