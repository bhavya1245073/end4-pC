pragma Singleton
pragma ComponentBehavior: Bound

// Every panel the shell can open, and whether it is open.
//
//     PanelRegistry.toggle("overview")
//     PanelRegistry.open("wallpaper-selector", { target: "lockWall" })
//     PanelRegistry.close("session")
//     PanelRegistry.isOpen("sidebarRight")
//
// A panel declares itself in a manifest and is then addressable by id from IPC, a keybind, a
// context menu row, a bar button or another plugin - none of which need to know it exists at
// compile time. That is the whole difference from the bag of booleans this replaces: core used to
// carry one property per feature (`overviewOpen`, `oskOpen`, `dropShelfOpen`, thirty of them), so
// every new panel meant editing core, and a plugin could not have one at all.
//
// ## Binding to it
//
// Read state through `state(id)`, which returns a long-lived object per panel:
//
//     visible: PanelRegistry.state("overview").open
//
// The object's identity never changes, so that binding is invalidated only when *that* panel
// opens or closes - not when any panel does. `isOpen(id)` is the same value for imperative code.
//
// ## Arguments
//
// `open(id, args)` carries a payload, which is how a panel that means different things in
// different places stays one panel: the wallpaper selector is opened with `{ target: "wallpaper" }`
// from the desktop menu and `{ target: "lockWall" }` from settings, and reads it as
// `state("wallpaper-selector").args.target`.
//
// ## Exclusivity
//
// Panels in the same `group` close each other, because two full-screen overlays at once is never
// what anyone meant. Groups come from the manifest; built-ins use "overlay" for the full-screen
// ones and no group for the rest.

import QtQuick
import Quickshell
import qs.services

Singleton {
    id: root

    // Panels the shell itself owns. These are rows in the same table plugin panels land in - not a
    // special case - so a built-in can be toggled, listed and bound to exactly like a plugin's.
    //
    // `group: "overlay"` means full-screen and mutually exclusive.
    readonly property var builtins: [
        { id: "bar", label: "Bar", persistent: true, initial: true },
        { id: "sidebarLeft", label: "Left sidebar", group: "sidebar" },
        { id: "sidebarRight", label: "Right sidebar", group: "sidebar" },
        { id: "settings", label: "Settings" },
        { id: "crosshair", label: "Crosshair" }
    ]

    // Panels contributed by plugins, from `provides.panels` entries that declare an `id`.
    readonly property var contributed: PluginRegistry.installedPanels
        .filter(entry => (entry.id ?? "").length > 0)
        .map(entry => ({
            id: entry.id,
            label: entry.label ?? entry.id,
            group: entry.group ?? "",
            pluginId: entry.pluginId,
            initial: entry.initial === true,
            persistent: entry.persistent === true
        }))

    readonly property var all: {
        const rows = root.builtins.slice();
        for (const entry of root.contributed) {
            // A plugin may deliberately replace a built-in panel by using its id; last one wins,
            // matching how a plugin directory shadows a shipped one.
            const existing = rows.findIndex(candidate => candidate.id === entry.id);
            if (existing === -1)
                rows.push(entry);
            else
                rows[existing] = entry;
        }
        return rows;
    }

    readonly property var ids: root.all.map(entry => entry.id)

    // ------------------------------------------------------------------ state

    // id -> QtObject { open, args, at }. Created on demand and never destroyed: a panel's state
    // object outlives the panel's window, which is what lets a binding on it be cheap.
    property var states: ({})

    // Bumped whenever any panel opens or closes, for `openIds` and for the settings GUI.
    property int revision: 0

    function state(id: string): var {
        let existing = root.states[id];
        if (existing)
            return existing;
        existing = stateComponent.createObject(root, { panelId: id });
        root.states[id] = existing;
        return existing;
    }

    function isOpen(id: string): bool {
        return root.states[id]?.open === true;
    }

    readonly property var openIds: {
        root.revision;
        return Object.keys(root.states).filter(id => root.states[id].open).sort();
    }

    readonly property bool anyOverlayOpen: {
        root.revision;
        return root.openIds.some(id => root.groupOf(id) === "overlay");
    }

    function groupOf(id: string): string {
        return root.all.find(entry => entry.id === id)?.group ?? "";
    }

    function describe(id: string): var {
        return root.all.find(entry => entry.id === id) ?? null;
    }

    // ----------------------------------------------------------------- acting

    signal opened(string id, var args)
    signal closed(string id)

    function open(id: string, args: var): bool {
        if (!id)
            return false;
        if (!root.ids.includes(id) && !root.states[id]) {
            // Not fatal: a panel may register a moment later, and refusing outright would make
            // startup order matter. The state is created, so whoever appears will see it.
            console.warn(`[panels] "${id}" is not a known panel - opening it anyway; known:`, root.ids.join(", "));
        }

        const group = root.groupOf(id);
        if (group.length > 0) {
            for (const other of root.openIds) {
                if (other !== id && root.groupOf(other) === group)
                    root.close(other);
            }
        }

        const panel = root.state(id);
        panel.args = args ?? ({});
        panel.at = Date.now();
        if (!panel.open) {
            panel.open = true;
            root.revision += 1;
            root.opened(id, panel.args);
            PluginBus.publish(`panel:${id}`, { open: true, args: panel.args });
        }
        return true;
    }

    function close(id: string): bool {
        const panel = root.states[id];
        if (!panel?.open)
            return false;
        panel.open = false;
        root.revision += 1;
        root.closed(id);
        PluginBus.publish(`panel:${id}`, { open: false, args: ({}) });
        return true;
    }

    function toggle(id: string, args: var): bool {
        return root.isOpen(id) ? root.close(id) : root.open(id, args);
    }

    function set(id: string, open: bool, args: var): bool {
        return open ? root.open(id, args) : root.close(id);
    }

    // Everything except the panels marked persistent - what Escape and a lock screen want.
    function closeAll(): int {
        let closed = 0;
        for (const id of root.openIds) {
            if (root.describe(id)?.persistent === true)
                continue;
            if (root.close(id))
                closed += 1;
        }
        return closed;
    }

    function closeGroup(group: string): int {
        let closed = 0;
        for (const id of root.openIds) {
            if (root.groupOf(id) === group && root.close(id))
                closed += 1;
        }
        return closed;
    }

    // Panels that should start open - the bar, and anything a plugin marks `initial`.
    Component.onCompleted: {
        for (const entry of root.all) {
            if (entry.initial === true)
                root.open(entry.id, ({}));
        }
    }

    // A plugin appearing later brings its own initial panels with it.
    onContributedChanged: {
        for (const entry of root.contributed) {
            if (entry.initial === true && !root.isOpen(entry.id))
                root.open(entry.id, ({}));
        }
    }

    readonly property Component stateComponent: Component {
        QtObject {
            property string panelId: ""
            property bool open: false
            property var args: ({})
            property real at: 0
        }
    }
}
