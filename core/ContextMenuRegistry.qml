pragma Singleton

// Items in the desktop right-click menu, built-in and plugin alike.
//
// A plugin declares a row in its manifest:
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
// A row does one of four things, checked in this order:
//
//     ipc      { target, function, args? }   calls a PluginIpc function in-process
//     panel    { id, args? }                 opens a panel by id
//     exec      ["cmd", "arg"]               spawns a process, argv - never a shell string
//     entry     "MySubmenu.qml"              opens a submenu drawn by the plugin
//
// Arguments may reference where the menu was opened: "$menuX", "$menuY" and "$screen" are
// substituted from the menu's own open arguments, so a row can place a window under the cursor
// without the menu knowing what that row is for.
//
// `badge` names a PluginBus topic whose retained value is shown on the right of the row - a count
// of items waiting, unread messages, files in a shelf. The menu binds to it, so it updates while
// open, and no row needs a special case in the menu to have one.
//
// `order` places it among the shell's own rows, which sit at 10, 20 and 100. Plugin rows default
// to 50, after the shell's and before Settings.
//
// ## Why the shell's rows are in this list too
//
// They used to be special-cased in the menu: five rows with a `builtin` tag and a switch that ran
// different code for each. That made the menu the only place a top-level row could exist, and made
// a plugin row a second-class citizen with a different code path. Now the shell's rows are ordinary
// rows using the same four verbs - a submenu is a URL, opening settings is a `panel` action - and
// the menu has exactly one path through it.

import QtQuick
import Quickshell

Singleton {
    id: root

    // Submenus the shell itself provides. They are ordinary QML files, so they can be addressed
    // by URL exactly like a plugin's, which is what removes the last special case.
    readonly property string __shellWidgets: `file://${Quickshell.shellDir}/modules/common/widgets`

    readonly property var builtins: [
        {
            id: "wallpaper",
            label: "Wallpaper & style",
            icon: "format_paint",
            order: 10,
            url: `${root.__shellWidgets}/WallpaperSubmenu.qml`
        },
        {
            id: "widgets",
            label: "Widgets",
            icon: "widgets",
            order: 20,
            url: `${root.__shellWidgets}/WidgetsSubmenu.qml`
        },
        {
            id: "settings",
            label: "Settings",
            icon: "settings",
            order: 100,
            panel: { id: "settings" }
        }
    ]

    readonly property var all: Stable.list("ContextMenuRegistry.all", (() => {
        const entries = root.builtins.map(item => Object.assign({
            pluginId: "",
            enabled: true,
            badge: "",
            ipc: null,
            exec: null,
            panel: null,
            url: ""
        }, item));

        for (const item of PluginRegistry.contextMenuItems) {
            if (!item.id || !item.label)
                continue;
            entries.push({
                id: `${item.pluginId}:${item.id}`,
                label: item.label,
                icon: item.icon ?? "extension",
                order: item.order ?? 50,
                pluginId: item.pluginId,
                ipc: item.ipc ?? null,
                panel: item.panel ?? null,
                exec: item.exec ?? null,
                url: item.url ?? "",
                badge: item.badge ?? "",
                enabled: true
            });
        }

        return entries.sort((a, b) => (a.order ?? 50) - (b.order ?? 50));
    })())

    // Does this row open a submenu rather than doing something?
    function opensSubmenu(item: var): bool {
        return !!item && `${item.url ?? ""}`.length > 0;
    }

    // The retained bus value for a row's badge, or undefined when it has none.
    function badgeValue(item: var): var {
        const topic = `${item?.badge ?? ""}`;
        if (topic.length === 0)
            return undefined;
        return PluginBus.value(topic, undefined);
    }

    // Run a row. `context` is the menu's own open arguments - { screen, x, y } - and is what
    // "$menuX" and friends resolve against. Returns true if the menu should close, which it should
    // for an action and should not for a row that opened a submenu.
    function activate(item: var, context: var): bool {
        if (!item)
            return true;

        if (item.ipc?.target && item.ipc?.function) {
            // In-process, so a menu row costs no process spawn and can talk to live state.
            const handled = PluginRegistry.invokeIpc(item.ipc.target, item.ipc.function, root.__resolveArgs(item.ipc.args ?? [], context));
            if (!handled)
                console.warn(`[plugins] context menu item ${item.id}: no IPC ${item.ipc.target}.${item.ipc.function}`);
            return true;
        }

        if (item.panel?.id) {
            PanelRegistry.open(item.panel.id, root.__resolveObject(item.panel.args ?? ({}), context));
            return true;
        }

        if (Array.isArray(item.exec) && item.exec.length > 0) {
            PluginUtils.exec(root.__resolveArgs(item.exec, context));
            return true;
        }

        if (root.opensSubmenu(item))
            return false;   // the menu opens the submenu itself

        console.warn(`[plugins] context menu item ${item.id} does nothing: needs ipc, panel, exec or entry`);
        return true;
    }

    // "$menuX" -> the x the menu was opened at, and so on. Anything else is passed through
    // untouched, so a literal argument that happens to start with a dollar is safe.
    function __resolveOne(value: var, context: var): var {
        if (typeof value !== "string")
            return value;
        switch (value) {
        case "$menuX":
            return context?.x ?? 0;
        case "$menuY":
            return context?.y ?? 0;
        case "$screen":
            return context?.screen?.name ?? "";
        default:
            return value;
        }
    }

    function __resolveArgs(args: var, context: var): var {
        return (Array.isArray(args) ? args : []).map(value => root.__resolveOne(value, context));
    }

    function __resolveObject(args: var, context: var): var {
        const resolved = ({});
        for (const key of Object.keys(args ?? {}))
            resolved[key] = root.__resolveOne(args[key], context);
        return resolved;
    }
}
