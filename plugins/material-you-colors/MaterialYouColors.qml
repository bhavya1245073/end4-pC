// Keeps the KDE/Qt, Konsole, KSyntaxHighlighting, decoration and terminal
// palettes in step with the settings next door under Settings -> Plugins.
//
// The work itself is done by the `kde-material-you` binary, which reads those
// settings out of plugins.json on its own. So this file does not translate
// anything into command line flags: it only decides *when* to run, which keeps
// the schema in manifest.json the single description of every option. The
// wallpaper switcher calls the same binary through
// ~/.config/matugen/templates/kde/kde-material-you-colors-wrapper.sh, so a
// setting changed here is still in effect on the next wallpaper change.
//
// ## When it runs
//
// A snapshot of the settings that were in effect at the end of the last
// successful run is kept in plugins.json, under a key the manifest deliberately
// does not declare (PluginConfig keeps undeclared keys, precisely so a plugin can
// store state next to its settings). Comparing against it answers the two
// questions that matter and cannot otherwise be told apart:
//
//   * the shell started and the colours on disk already match  -> do nothing
//   * the plugin was just enabled, or a setting was edited while
//     the shell was not running                                -> apply
//
// Without it, either every shell reload rewrites thirty files and pokes D-Bus for
// no reason, or enabling the plugin leaves the session on the old palette until
// the next wallpaper change.
//
// The comparison waits for `PluginConfig.loaded`. plugins.json is read
// asynchronously, and before it arrives every setting reads as its manifest
// default and the snapshot reads as absent - which looks exactly like "just
// enabled" and would re-theme the session at every startup.
//
// Nothing here is Nix-specific; the binary comes from `runtimeDeps` in the
// manifest.

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.modules.common

Scope {
    id: root

    readonly property string pluginId: "material-you-colors"

    // Where the snapshot lives. Not in manifest.json's `settings`, so it never
    // shows up as a control in the GUI.
    readonly property string snapshotKey: "appliedSnapshot"

    readonly property var settings: PluginConfig.of(root.pluginId)

    // Every declared setting, in a stable order, as a string. PluginConfig
    // recomputes its `effective` map whenever *any* plugin changes, so `settings`
    // rebinds constantly; comparing this instead is what stops an unrelated
    // plugin's switch from re-theming the session.
    readonly property string snapshot: {
        const values = root.settings;
        const out = {};
        for (const key of Object.keys(values).sort()) {
            if (key === root.snapshotKey)
                continue;
            out[key] = values[key];
        }
        return JSON.stringify(out);
    }

    // Set while a run is in flight, so a burst of changes cannot start two
    // processes writing the same files.
    readonly property bool busy: applyProcess.running

    // A change that arrived mid-run, which that run cannot have seen.
    property bool rerunWhenDone: false

    // Surfaced by the IPC handler; a failure is logged rather than swallowed.
    property bool failed: false
    property string lastError: ""

    function apply(): void {
        if (root.busy) {
            root.rerunWhenDone = true;
            return;
        }

        root.failed = false;
        applyProcess.running = true;
    }

    // Whether the settings differ from what the last successful run applied.
    readonly property bool stale: root.snapshot !== (root.settings[root.snapshotKey] ?? "")

    Component.onCompleted: debounce.restart()

    onSnapshotChanged: debounce.restart()

    // A slider writes on every step, so wait for the user to stop moving it:
    // applying a palette rewrites around thirty files and sends several D-Bus
    // signals, which per pixel of slider travel would make the GUI crawl.
    Timer {
        id: debounce

        interval: 600
        onTriggered: {
            // Re-arm rather than decide on defaults. If the user had this plugin
            // switched off, PluginRegistry destroys this object as soon as
            // plugins.json lands, and the timer never fires again - which is the
            // correct outcome.
            if (!PluginConfig.loaded) {
                debounce.restart();
                return;
            }

            if (root.stale)
                root.apply();
        }
    }

    Process {
        id: applyProcess

        // No arguments: the binary reads the same plugins.json these settings
        // live in, so there is nothing to pass and nothing to keep in sync.
        // --quiet keeps warnings and drops the per-file report.
        command: ["kde-material-you", "--quiet"]

        stderr: StdioCollector {
            id: errors
        }

        onExited: exitCode => {
            root.failed = exitCode !== 0;
            root.lastError = errors.text.trim();

            if (root.failed) {
                console.warn(`[${root.pluginId}] kde-material-you exited with ${exitCode}: ${root.lastError}`);
            } else {
                // Only a run that succeeded is worth remembering; a failed one
                // should be retried on the next start.
                PluginConfig.set(root.pluginId, root.snapshotKey, root.snapshot);
            }

            if (root.rerunWhenDone) {
                root.rerunWhenDone = false;
                debounce.restart();
            }
        }
    }

    // `qs ipc call materialYou apply`, for a keybind or a script.
    IpcHandler {
        target: "materialYou"

        function apply(): void {
            root.apply();
        }

        function status(): string {
            if (root.busy)
                return "applying";
            if (root.failed)
                return `failed: ${root.lastError}`;
            return root.stale ? "stale" : "ok";
        }
    }
}
