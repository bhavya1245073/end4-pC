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
            if (!panel)
                return `no such panel: ${id}`;
            return JSON.stringify({ id: id, open: panel.open, args: panel.args, at: panel.at });
        }
    }

    // Intents: anything a plugin declared as an action.
    //
    //     qs -c end4-pC ipc call intent list
    //     qs -c end4-pC ipc call intent call "gif-picker:search" 'query=celebrate'
    //     qs -c end4-pC ipc call intent call "dropover:park" 'path=~/shot.png'
    //     qs -c end4-pC ipc call intent describe "gif-picker:search"
    //
    // The same entry point the launcher and other plugins use, so a keybind, a script and a peer
    // plugin cannot diverge in what they can reach.
    IpcHandler {
        target: "intent"

        function list(): string {
            const actions = PluginIntent.actions;
            if (actions.length === 0)
                return "no plugin declares any actions";

            const lines = [];
            for (const action of actions) {
                const live = PluginIntent.has(action.ref);
                const on = PluginRegistry.isActive(action.pluginId);
                const status = !on ? "off" : live ? "ready" : "no handler";
                const args = Object.keys(action.schema ?? {})
                    .map(name => action.schema[name]?.required === true ? `<${name}>` : `[${name}]`)
                    .join(" ");
                lines.push(`${status.padEnd(11)} ${action.ref.padEnd(34)} ${args}`);
            }
            return lines.join("\n");
        }

        // Arguments as `key=value`, quoted if they contain spaces. A bare value with no key goes
        // to the action's first required argument, so `intent call gif-picker:search cat` works.
        function call(ref: string, args: string): string {
            const parsed = PluginIntent.withPositional(ref, PluginIntent.parseArgs(args));
            const outcome = PluginIntent.call(ref, parsed);
            if (!outcome.ok)
                return `error: ${outcome.error}`;
            if (outcome.result === null || outcome.result === undefined)
                return `ok: ${ref}`;
            return typeof outcome.result === "string" ? outcome.result : JSON.stringify(outcome.result);
        }

        // Split from call() because Quickshell's IPC has no optional parameters.
        function run(ref: string): string {
            return this.call(ref, "");
        }

        function describe(ref: string): string {
            const action = PluginIntent.describe(ref);
            if (!action)
                return `no such action: ${ref}`;
            return JSON.stringify({
                ref: action.ref,
                label: action.label,
                description: action.description,
                plugin: action.pluginId,
                enabled: PluginRegistry.isActive(action.pluginId),
                handled: PluginIntent.has(action.ref),
                schema: action.schema
            }, null, 2);
        }

        // What the launcher would show for a query - the fastest way to find out why typing
        // something does not offer the action you expected.
        function match(query: string): string {
            const rows = PluginIntent.match(query);
            if (rows.length === 0)
                return `nothing matches "${query}"`;
            return rows.map(row => `${String(row.score).padStart(4)}  ${row.ref.padEnd(34)} ${row.subtitle}`).join("\n");
        }

        function recent(): string {
            if (PluginIntent.recent.length === 0)
                return "nothing has been called yet";
            return PluginIntent.recent.map(entry => {
                const ago = Math.round((Date.now() - entry.at) / 1000);
                const args = Object.keys(entry.args ?? {}).length > 0 ? ` ${JSON.stringify(entry.args)}` : "";
                return `${(entry.ok ? "ok" : "FAIL").padEnd(5)} ${String(ago).padStart(5)}s ago  ${entry.ref}${args}${entry.ok ? "" : `  - ${entry.error}`}`;
            }).join("\n");
        }

        // Declared but with nothing listening, for a plugin whose service failed to load.
        function orphans(): string {
            const orphans = PluginIntent.unimplemented;
            return orphans.length === 0
                ? "every declared action of every enabled plugin has a handler"
                : `no handler registered for:\n  ${orphans.join("\n  ")}`;
        }
    }

    // Undo, redo and what is on the stack.
    //
    //     qs -c end4-pC ipc call history undo
    //     qs -c end4-pC ipc call history list
    IpcHandler {
        target: "history"

        function undo(): string {
            const label = PluginHistory.nextUndoLabel;
            return PluginHistory.undo() ? `undone: ${label}` : "nothing to undo";
        }

        function redo(): string {
            const label = PluginHistory.nextRedoLabel;
            return PluginHistory.redo() ? `redone: ${label}` : "nothing to redo";
        }

        function list(): string {
            const stacks = PluginHistory.list();
            const lines = [];
            lines.push(`undo (${stacks.undo.length}):`);
            for (const entry of stacks.undo)
                lines.push(`  ${String(Math.round(entry.ageMs / 1000)).padStart(5)}s  ${entry.label}${entry.pluginId ? `  [${entry.pluginId}]` : ""}`);
            lines.push(`redo (${stacks.redo.length}):`);
            for (const entry of stacks.redo)
                lines.push(`  ${String(Math.round(entry.ageMs / 1000)).padStart(5)}s  ${entry.label}${entry.pluginId ? `  [${entry.pluginId}]` : ""}`);
            return lines.join("\n");
        }

        function clear(): string {
            PluginHistory.clear();
            return "history cleared";
        }
    }

    // The network layer: what is cached, what is in flight, and offline mode for testing.
    IpcHandler {
        target: "http"

        function stats(): string {
            const stats = PluginHttp.cacheStats();
            return `${stats.entries} cached response(s), ${Math.round(stats.bytes / 1024)} KiB, ${stats.inFlight} in flight`
                + `\nnetworking is ${PluginHttp.enabled ? "on" : "off"}`;
        }

        function clear(): string {
            return `dropped ${PluginHttp.clearCache()} cached response(s)`;
        }

        function offline(): string {
            PluginHttp.enabled = false;
            return "networking off: requests are served from cache or fail";
        }

        function online(): string {
            PluginHttp.enabled = true;
            return "networking on";
        }

        function cancel(): string {
            return `cancelled ${PluginHttp.cancelAll()} request(s)`;
        }
    }

    // Permissions, and the power contract.
    IpcHandler {
        target: "caps"

        function list(): string {
            const lines = [];
            for (const plugin of PluginRegistry.all) {
                const declared = PluginPermissions.declared(plugin.id);
                const undeclared = PluginPermissions.undeclared(plugin.id);
                if (declared.length === 0 && undeclared.length === 0)
                    continue;
                const states = declared.map(permission =>
                    PluginPermissions.granted(plugin.id, permission) ? permission : `${permission}(denied)`);
                const extra = undeclared.length > 0 ? `  undeclared: ${undeclared.join(", ")}` : "";
                lines.push(`${plugin.id.padEnd(24)} ${states.join(", ")}${extra}`);
            }
            return lines.length === 0 ? "no plugin declares any permissions" : lines.join("\n");
        }

        function deny(pluginId: string, permission: string): string {
            PluginPermissions.set(pluginId, permission, false);
            return `${pluginId} may no longer use ${permission}`;
        }

        function allow(pluginId: string, permission: string): string {
            PluginPermissions.set(pluginId, permission, true);
            return `${pluginId} may use ${permission}`;
        }

        function lifecycle(): string {
            return JSON.stringify(PluginLifecycle.describe(), null, 2);
        }

        function powersave(on: string): string {
            PluginLifecycle.forcePowerSaver = ["1", "true", "on", "yes"].includes(String(on).toLowerCase());
            return `power-saver simulation ${PluginLifecycle.forcePowerSaver ? "on" : "off"}`;
        }

        function fx(): string {
            const fx = PluginFX.describe();
            const lines = [
                `effects allowed: ${fx.effectsAllowed}`,
                `wallpaper sampling: ${fx.sampling}`,
                `compositor: ${fx.compositor}`
            ];
            if (fx.compositorBlurAvailable) {
                lines.push("", "for a true backdrop blur behind plugin windows, add to hyprland.conf:");
                lines.push(PluginFX.blurRule("quickshell:pluginWindow"));
            }
            return lines.join("\n");
        }

        function toast(text: string): string {
            PluginToast.show(text);
            return `showed: ${text}`;
        }
    }
}
