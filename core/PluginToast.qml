pragma Singleton

// Transient feedback: "Copied", "Saved", "Could not reach the API".
//
//     PluginToast.show("Copied")
//     PluginToast.success("Saved 3 files")
//     PluginToast.error("Could not reach the API")
//     PluginToast.notice("Offline - showing cached results")
//
// With an action, for anything undoable:
//
//     PluginToast.show({
//         text: qsTr("Shelf cleared"),
//         tone: "notice",
//         actionLabel: qsTr("Undo"),
//         onAction: () => restore()
//     })
//
// This singleton is the queue. PluginToastHost, instantiated once by PluginHost, is the
// window that draws `current`. A plugin never has to create a surface, and a toast keeps
// showing after the plugin's own popup has closed - which is the usual reason a
// hand-rolled "Copied!" badge is never seen: it is drawn inside the thing the click
// dismissed.
//
// ## Queueing
//
// One toast is visible at a time. Sending a second while one is up does not stack
// windows or truncate the first - it is queued and shown after it. `replace()` is there
// for progress-like sequences where only the latest matters ("Downloading" then "Done"),
// and drops the pending queue instead of making the user watch it drain.
//
// Identical consecutive toasts are coalesced: hold a copy shortcut down and you get one
// "Copied", not forty, because a queue that takes eight seconds to drain is a bug the
// user has to sit through.

import QtQuick
import Quickshell

Singleton {
    id: root

    // The toast being shown, or null. PluginToastHost binds to this.
    readonly property var current: root.__queue.length > 0 ? root.__queue[0] : null
    readonly property bool visible: root.current !== null
    readonly property int pending: Math.max(0, root.__queue.length - 1)

    property var __queue: []
    property int __nextId: 1

    // ------------------------------------------------------------------ show

    // Accepts a string or a descriptor:
    //
    //   text        the message (required)
    //   tone        "accent" (default) | "success" | "error" | "notice"
    //   icon        Material Symbol name; a tone-appropriate default is used otherwise
    //   durationMs  auto-dismiss delay; 2600, or 5000 when there is an action to click
    //   actionLabel button text
    //   onAction    called when the button is clicked, then the toast closes
    //   pluginId    attribution, for the log and for debugging
    function show(toast: var): int {
        const entry = root.__normalise(toast);
        if (!entry)
            return 0;

        // Coalesce a repeat of what is already showing, or of what is queued last.
        const last = root.__queue.length > 0 ? root.__queue[root.__queue.length - 1] : null;
        if (last && last.text === entry.text && last.tone === entry.tone && !last.actionLabel && !entry.actionLabel) {
            root.__bump(last.id);
            return last.id;
        }

        root.__queue = root.__queue.concat([entry]);
        return entry.id;
    }

    function success(text: string): int {
        return root.show({ text: text, tone: "success" });
    }

    function error(text: string): int {
        return root.show({ text: text, tone: "error" });
    }

    function notice(text: string): int {
        return root.show({ text: text, tone: "notice" });
    }

    // Clears anything queued and shows this instead. For a sequence where only the latest
    // state is worth reading.
    function replace(toast: var): int {
        const entry = root.__normalise(toast);
        if (!entry)
            return 0;
        root.__queue = [entry];
        return entry.id;
    }

    // ---------------------------------------------------------------- dismiss

    // Called by the host when the timer expires, when the toast is clicked away, or by a
    // plugin that no longer wants a toast it raised. Dismissing an id that is not showing
    // removes it from the queue instead, so a cancelled operation does not surface later.
    function dismiss(id: int): void {
        if (id <= 0) {
            root.__queue = root.__queue.slice(1);
            return;
        }
        root.__queue = root.__queue.filter(entry => entry.id !== id);
    }

    function dismissCurrent(): void {
        root.__queue = root.__queue.slice(1);
    }

    function clear(): void {
        root.__queue = [];
    }

    // Runs the current toast's action and closes it. The host calls this; the callback is
    // guarded because it comes from plugin code and a throw here would take the shell's
    // event loop with it.
    function activate(id: int): void {
        const entry = root.__queue.find(candidate => candidate.id === id);
        root.dismiss(id);
        if (!entry || typeof entry.onAction !== "function")
            return;
        try {
            entry.onAction();
        } catch (e) {
            console.warn(`[toast] action of "${entry.text}" threw:`, e);
        }
    }

    // ------------------------------------------------------------- internals

    function __normalise(toast: var): var {
        const source = (typeof toast === "string") ? { text: toast } : (toast ?? {});
        const text = String(source.text ?? "").trim();
        if (text.length === 0) {
            console.warn("[toast] show() with no text");
            return null;
        }

        const tone = ["accent", "success", "error", "notice"].includes(source.tone) ? source.tone : "accent";
        const actionLabel = String(source.actionLabel ?? "").trim();

        return {
            id: root.__nextId++,
            text: text,
            tone: tone,
            icon: String(source.icon ?? root.iconFor(tone)),
            // Something to click needs longer than something to read.
            durationMs: Math.max(600, source.durationMs ?? (actionLabel.length > 0 ? 5000 : 2600)),
            actionLabel: actionLabel,
            onAction: typeof source.onAction === "function" ? source.onAction : null,
            pluginId: String(source.pluginId ?? ""),
            at: Date.now(),
            repeats: 1
        };
    }

    function iconFor(tone: string): string {
        if (tone === "success")
            return "check_circle";
        if (tone === "error")
            return "error";
        if (tone === "notice")
            return "info";
        return "bolt";
    }

    // A coalesced repeat restarts the timer and shows a count, so holding a shortcut looks
    // like one toast counting up rather than a stuck one.
    function __bump(id: int): void {
        root.__queue = root.__queue.map(entry => {
            if (entry.id !== id)
                return entry;
            const copy = Object.assign({}, entry);
            copy.repeats = entry.repeats + 1;
            copy.at = Date.now();
            return copy;
        });
    }
}
