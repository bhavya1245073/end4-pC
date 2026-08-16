pragma Singleton
pragma ComponentBehavior: Bound

// `qs -c end4-pC ipc call plugins ...` - the plugin system's own command line.
//
// Exists mostly so that what plugins have registered is discoverable. A plugin can
// declare a keybind and an IPC command, and until you can list them there is no way to
// know what to put in a compositor config short of reading manifests.
//
//     qs -c end4-pC ipc call plugins list
//     qs -c end4-pC ipc call plugins shortcuts     # what to bind, and how
//     qs -c end4-pC ipc call plugins commands      # every IPC target plugins own
//     qs -c end4-pC ipc call plugins enable gifs
//     qs -c end4-pC ipc call plugins toggle dock

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    IpcHandler {
        target: "plugins"

        function list(): string {
            const lines = [];
            for (const plugin of PluginRegistry.all) {
                const state = PluginRegistry.isEnabled(plugin.id)
                    ? (PluginRegistry.isActive(plugin.id) ? "on" : "unsupported")
                    : "off";
                const kinds = Object.keys(plugin.provides).filter(kind => Array.isArray(plugin.provides[kind]) && plugin.provides[kind].length > 0);
                lines.push(`${state.padEnd(12)} ${plugin.id.padEnd(22)} ${kinds.join(", ")}`);
            }
            const text = lines.join("\n");
            console.log(text);
            return text;
        }

        // Every keybind a plugin declares, with the line to put in a compositor config.
        // The compositor dispatches a `quickshell:` global directly, without spawning a
        // process, which is why this is better than binding a shell command.
        function shortcuts(): string {
            const lines = [];
            for (const shortcut of PluginRegistry.collectInstalled("shortcuts")) {
                const name = shortcut.id ?? shortcut.name ?? "";
                if (name === "")
                    continue;
                const on = PluginRegistry.isActive(shortcut.pluginId) ? "" : "  (plugin off)";
                lines.push(`quickshell:${name}${on}`);
                lines.push(`    ${shortcut.description ?? shortcut.pluginName}`);
                if (shortcut.suggestedKey)
                    lines.push(`    hyprland: bind = ${shortcut.suggestedKey}, global, quickshell:${name}`);
                else
                    lines.push(`    hyprland: bind = SUPER, <key>, global, quickshell:${name}`);
            }
            const text = lines.length > 0 ? lines.join("\n") : "no plugin shortcuts declared";
            console.log(text);
            return text;
        }

        // IPC targets plugins own, and the commands on them.
        function commands(): string {
            const lines = [];
            for (const entry of PluginRegistry.collectInstalled("ipc")) {
                const target = entry.target ?? entry.pluginId;
                const on = PluginRegistry.isActive(entry.pluginId) ? "" : "  (plugin off)";
                lines.push(`${target}${on}   from ${entry.pluginId}`);
                lines.push(`    qs -c ${Quickshell.env("QS_CONFIG_NAME") ?? "end4-pC"} ipc call ${target} <function>`);
                lines.push(`    (run 'ipc show' for the function list once the plugin is on)`);
            }
            const text = lines.length > 0 ? lines.join("\n") : "no plugin IPC targets declared";
            console.log(text);
            return text;
        }

        function enable(id: string): string {
            if (!PluginRegistry.get(id))
                return `no such plugin: ${id}`;
            PluginRegistry.setEnabled(id, true);
            return `${id} enabled`;
        }

        function disable(id: string): string {
            if (!PluginRegistry.get(id))
                return `no such plugin: ${id}`;
            PluginRegistry.setEnabled(id, false);
            return `${id} disabled`;
        }

        function toggle(id: string): string {
            if (!PluginRegistry.get(id))
                return `no such plugin: ${id}`;
            const next = !PluginRegistry.isEnabled(id);
            PluginRegistry.setEnabled(id, next);
            return `${id} ${next ? "enabled" : "disabled"}`;
        }

        function reload(): string {
            PluginRegistry.rescan();
            return "rescanning plugins";
        }
    }
}
