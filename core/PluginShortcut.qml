// One keybind declared by a plugin's manifest.
//
// `provides.shortcuts` was being collected by the registry and then ignored, so a
// plugin could declare a keybind and nothing would ever happen. This is what makes
// it real.
//
//     "shortcuts": [
//         {
//             "id": "batteryDetails",
//             "description": "Show battery details",
//             "ipc": { "target": "battery", "function": "toggle" }
//         },
//         {
//             "id": "batteryPowerSave",
//             "description": "Switch to power saving",
//             "exec": ["powerprofilesctl", "set", "power-saver"]
//         }
//     ]
//
// The name the compositor binds to is `quickshell:<id>`, same as for the built-ins:
//
//     bind = SUPER, B, global, quickshell:batteryDetails
//
// A plugin that needs more than "run this" or "call that" should declare a
// CompositorGlobalShortcut in its own QML instead; this exists so that the simple
// case needs no QML at all, and so the shell can list what a plugin binds.

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    // The registry entry: { id | name, description, exec, ipc, suggestedKey, ... }
    required property var descriptor

    // `id` is the documented field; `name` is accepted because the manifest examples
    // used it while this was metadata that nothing acted on.
    readonly property string shortcutName: root.descriptor.id ?? root.descriptor.name ?? ""

    function trigger() {
        const exec = root.descriptor.exec;
        if (Array.isArray(exec) && exec.length > 0) {
            Quickshell.execDetached(exec);
            return;
        }

        const ipc = root.descriptor.ipc;
        if (ipc?.target && ipc?.function) {
            // Going through the IPC layer rather than reaching into the plugin's
            // objects keeps this working whether or not the plugin is currently
            // loaded, and gives the same entry point the command line has.
            Quickshell.execDetached(["qs", "-c", Quickshell.env("QS_CONFIG_NAME") ?? "end4-pC", "ipc", "call", ipc.target, ipc.function]);
            return;
        }

        // A plugin may declare a shortcut purely so the shell can tell the user what
        // to bind, and handle it with its own CompositorGlobalShortcut. Registering
        // the name here would then be a duplicate, so say nothing.
    }

    CompositorGlobalShortcut {
        name: root.shortcutName
        description: root.descriptor.description ?? `${root.descriptor.pluginName} shortcut`

        // Only claim the name if this entry actually does something; otherwise the
        // plugin's own handler owns it.
        active: root.shortcutName !== "" && (Array.isArray(root.descriptor.exec) || (root.descriptor.ipc?.target !== undefined))

        onPressed: root.trigger()
    }
}
