pragma Singleton

// Undo for the desktop.
//
// Clearing a drop shelf, deleting a note, removing a favourite, replacing a wallpaper -
// destructive actions a plugin performs in one click and cannot currently take back. A
// plugin records how to reverse what it just did:
//
//     PluginHistory.record({
//         label: qsTr("Cleared the shelf"),
//         pluginId: "dropover",
//         undo: () => DropShelfState.restore(snapshot),
//         redo: () => DropShelfState.clear()
//     })
//
// That is the whole integration. The user gets Ctrl+Z from anywhere, a toast confirming what
// was reversed, and a redo. The plugin needs no keybind, no undo stack and no UI.
//
// ## The snapshot has to be taken before the action
//
// `undo` is a closure, so it captures whatever the plugin passes it. Capturing a *reference*
// to the live list and then clearing that list gives an undo that restores an empty list -
// the classic version of this bug. Copy first:
//
//     const snapshot = shelf.items.slice()
//     shelf.clear()
//     PluginHistory.record({ label: "...", undo: () => shelf.restore(snapshot), ... })
//
// ## Why a single global stack
//
// Because the user has one idea of "what did I just do". A per-plugin stack means Ctrl+Z
// depends on which surface has focus, and shell surfaces take focus in ways the user did not
// ask for - so the same keypress would undo different things depending on where the pointer
// happened to be. One stack, ordered by time, is the only version that matches the mental
// model.
//
// Entries expire: an undo offered an hour later, for a closure holding objects that no longer
// exist, is worse than no undo. `maxAgeMs` is generous but finite.

import QtQuick
import Quickshell
import qs.core

Singleton {
    id: root

    readonly property int limit: 40
    readonly property real maxAgeMs: 15 * 60 * 1000

    // Newest first. Entries: { id, label, pluginId, icon, undo, redo, at }
    property var undoStack: []
    property var redoStack: []

    readonly property bool canUndo: root.__fresh(root.undoStack).length > 0
    readonly property bool canRedo: root.__fresh(root.redoStack).length > 0

    readonly property string nextUndoLabel: root.__fresh(root.undoStack)[0]?.label ?? ""
    readonly property string nextRedoLabel: root.__fresh(root.redoStack)[0]?.label ?? ""

    property int __nextId: 1

    // ----------------------------------------------------------------- record

    // Accepts a descriptor, or `record(label, { undo, redo })` for the shorter form.
    function record(labelOrEntry: var, maybeEntry: var): int {
        const source = (typeof labelOrEntry === "string")
            ? Object.assign({ label: labelOrEntry }, maybeEntry ?? {})
            : (labelOrEntry ?? {});

        const label = String(source.label ?? "").trim();
        if (label.length === 0) {
            console.warn("[history] record() needs a label - it is what the user is offered");
            return 0;
        }
        if (typeof source.undo !== "function") {
            console.warn(`[history] "${label}" has no undo function, so there is nothing to record`);
            return 0;
        }

        const entry = {
            id: root.__nextId++,
            label: label,
            pluginId: String(source.pluginId ?? ""),
            icon: String(source.icon ?? "undo"),
            undo: source.undo,
            redo: typeof source.redo === "function" ? source.redo : null,
            at: Date.now()
        };

        root.undoStack = [entry].concat(root.__fresh(root.undoStack)).slice(0, root.limit);
        // A new action invalidates the redo branch, as in every editor.
        root.redoStack = [];
        return entry.id;
    }

    // Records *and* offers an immediate undo in the toast, which is where most of these
    // belong: the moment after the click is when the user notices the mistake.
    function recordWithToast(labelOrEntry: var, maybeEntry: var): int {
        const id = root.record(labelOrEntry, maybeEntry);
        if (id === 0)
            return 0;
        const entry = root.undoStack[0];
        PluginToast.show({
            text: entry.label,
            tone: "notice",
            icon: entry.icon,
            actionLabel: qsTr("Undo"),
            onAction: () => root.undoEntry(id),
            pluginId: entry.pluginId
        });
        return id;
    }

    // ------------------------------------------------------------------- act

    function undo(): bool {
        const fresh = root.__fresh(root.undoStack);
        if (fresh.length === 0) {
            PluginToast.show({ text: qsTr("Nothing to undo"), tone: "notice", icon: "undo" });
            return false;
        }
        return root.undoEntry(fresh[0].id);
    }

    function redo(): bool {
        const fresh = root.__fresh(root.redoStack);
        if (fresh.length === 0) {
            PluginToast.show({ text: qsTr("Nothing to redo"), tone: "notice", icon: "redo" });
            return false;
        }
        return root.redoEntry(fresh[0].id);
    }

    // Undo one specific entry, not necessarily the newest - what the toast's own Undo button
    // uses, so clicking it after doing something else still reverses the thing it was offered
    // for rather than the latest action.
    function undoEntry(id: int): bool {
        const entry = root.undoStack.find(candidate => candidate.id === id);
        if (!entry)
            return false;

        root.undoStack = root.undoStack.filter(candidate => candidate.id !== id);

        if (!root.__run(entry.undo, entry, "undo"))
            return false;

        if (entry.redo)
            root.redoStack = [entry].concat(root.redoStack).slice(0, root.limit);

        PluginToast.show({
            text: qsTr("Undone: %1").arg(entry.label),
            tone: "success",
            icon: "undo",
            actionLabel: entry.redo ? qsTr("Redo") : "",
            onAction: entry.redo ? (() => root.redoEntry(entry.id)) : null,
            pluginId: entry.pluginId
        });
        return true;
    }

    function redoEntry(id: int): bool {
        const entry = root.redoStack.find(candidate => candidate.id === id);
        if (!entry || !entry.redo)
            return false;

        root.redoStack = root.redoStack.filter(candidate => candidate.id !== id);

        if (!root.__run(entry.redo, entry, "redo"))
            return false;

        root.undoStack = [entry].concat(root.undoStack).slice(0, root.limit);
        PluginToast.show({
            text: qsTr("Redone: %1").arg(entry.label),
            tone: "success",
            icon: "redo",
            pluginId: entry.pluginId
        });
        return true;
    }

    function clear(): void {
        root.undoStack = [];
        root.redoStack = [];
    }

    // Drops everything a plugin recorded. Called when a plugin is switched off: its closures
    // reference objects that are being torn down.
    function forget(pluginId: string): int {
        const before = root.undoStack.length + root.redoStack.length;
        root.undoStack = root.undoStack.filter(entry => entry.pluginId !== pluginId);
        root.redoStack = root.redoStack.filter(entry => entry.pluginId !== pluginId);
        return before - (root.undoStack.length + root.redoStack.length);
    }

    // ------------------------------------------------------------- diagnostics

    function list(): var {
        return {
            undo: root.__fresh(root.undoStack).map(entry => ({ id: entry.id, label: entry.label, pluginId: entry.pluginId, ageMs: Date.now() - entry.at })),
            redo: root.__fresh(root.redoStack).map(entry => ({ id: entry.id, label: entry.label, pluginId: entry.pluginId, ageMs: Date.now() - entry.at }))
        };
    }

    // --------------------------------------------------------------- internals

    function __fresh(stack: var): var {
        const cutoff = Date.now() - root.maxAgeMs;
        return stack.filter(entry => entry.at >= cutoff);
    }

    function __run(callback: var, entry: var, what: string): bool {
        try {
            callback();
            return true;
        } catch (e) {
            console.warn(`[history] ${what} of "${entry.label}" threw:`, e);
            PluginToast.error(qsTr("Could not %1 \u201c%2\u201d").arg(what).arg(entry.label));
            return false;
        }
    }
}
