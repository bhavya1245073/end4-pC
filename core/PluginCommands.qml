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

        // Where plugins are looked for, in precedence order. The first thing to check when a
        // plugin that exists on disk does not appear in the list.
        function paths(): string {
            return PluginRegistry.pluginPaths
                .map((path, index) => `${index + 1}. ${path}${path === PluginRegistry.userPluginsDir ? "   (drop-in, no rebuild)" : ""}`)
                .join("\n");
        }

        // Which directory each plugin was actually loaded from - the answer to "why am I editing a
        // file and nothing changes".
        //
        // Split in two because Quickshell's IPC has no optional parameters: a function that
        // declares an argument cannot be called without one, so "all of them" needs its own name.
        function where(id: string): string {
            return PluginRegistry.dirOf(id);
        }

        function origins(): string {
            return PluginRegistry.discovered.map(pluginId => `${pluginId.padEnd(24)} ${PluginRegistry.dirOf(pluginId)}`).join("\n");
        }

        // Per search path: does it exist, and how many plugin directories are on it. The first
        // thing to look at when a plugin is missing.
        function scan(): string {
            return PluginRegistry.scannerReport();
        }

        // Retained topics on the event bus, with their current values: the state plugins publish
        // to each other and to the shell.
        function bus(): string {
            const lines = [];
            for (const topic of PluginBus.topics) {
                const info = PluginBus.describe(topic);
                lines.push(`${topic.padEnd(28)} listeners=${info.listeners} ${info.retained ? `value=${JSON.stringify(info.value)}` : "(not retained)"}`);
            }
            return lines.length > 0 ? lines.join("\n") : "no topics";
        }

        // Live timers, so a plugin leaking handles is visible rather than mysterious.
        function timers(): string {
            const stats = PluginTimer.stats;
            return `${stats.alive} alive: ${JSON.stringify(stats.byKind)}`;
        }
    }

    // Panels: the windows the shell can show, built-in and plugin alike.
    //
    //     qs -c end4-pC ipc call panels list
    //     qs -c end4-pC ipc call panels toggle overview
    //     qs -c end4-pC ipc call panels open wallpaperSelector
    //
    // Every panel is addressable by id, which is the point of the registry: a keybind, a script or
    // another plugin can open one without the shell having a property for it.
    IpcHandler {
        target: "panels"

        function list(): string {
            const lines = [];
            for (const panel of PanelRegistry.all) {
                const open = PanelRegistry.isOpen(panel.id);
                const owner = panel.pluginId ? `plugin:${panel.pluginId}` : "shell";
                const group = panel.group ? ` group=${panel.group}` : "";
                lines.push(`${(open ? "open" : "closed").padEnd(7)} ${panel.id.padEnd(20)} ${owner.padEnd(28)}${group}`);
            }
            return lines.join("\n");
        }

        function open(id: string): string {
            return PanelRegistry.open(id, ({})) ? `opened ${id}` : `no such panel: ${id}`;
        }

        function close(id: string): string {
            return PanelRegistry.close(id) ? `closed ${id}` : `${id} was not open`;
        }

        function toggle(id: string): string {
            PanelRegistry.toggle(id, ({}));
            return `${id} is now ${PanelRegistry.isOpen(id) ? "open" : "closed"}`;
        }

        function closeAll(): string {
            return `closed ${PanelRegistry.closeAll()} panel(s)`;
        }

        function state(id: string): string {
            const panel = PanelRegistry.state(id);
            return JSON.stringify({ id: id, open: panel.open, args: panel.args, at: panel.at });
        }
    }
}
