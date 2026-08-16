pragma Singleton

// Modal dialogs, drawn by the shell rather than by another program.
//
//     PluginDialogs.confirm({ title: "Delete note", message: "This cannot be undone.",
//                             danger: true }, ok => { if (ok) remove() })
//
//     PluginDialogs.prompt({ title: "New note", placeholder: "Title" }, text => { ... })
//
//     PluginDialogs.choose({ title: "Sort by", options: ["Name", "Date", "Size"] }, index => ...)
//
//     PluginDialogs.openFile({ title: "Pick a wallpaper", filter: "image/png image/jpeg",
//                              directory: "~/Pictures" }, path => ...)
//
// The first three are shell-native: same surface, same typography, same animation as everything
// else, keyboard-first (Enter confirms, Escape cancels), and they cannot end up behind another
// window. The file picker is the exception - it uses the system dialog (kdialog), because
// reimplementing a file browser is a worse answer than using the one the user already knows.
//
// A callback always runs exactly once, with `false`, `""` or `-1` when the dialog was
// cancelled, so a caller never has to distinguish "cancelled" from "never answered".
//
// Only one dialog is up at a time; asking for a second one queues it.

import QtQuick
import Quickshell
import qs.core

Singleton {
    id: root

    // The dialog currently on screen, as { kind, options, callback }, or null.
    property var current: null

    // Waiting dialogs. A plugin that asks twice in one frame gets two dialogs, in order,
    // rather than one silently dropped.
    property var queue: []

    readonly property bool open: root.current !== null

    function confirm(options: var, callback: var): void {
        root.__enqueue("confirm", options ?? {}, callback);
    }

    function prompt(options: var, callback: var): void {
        root.__enqueue("prompt", options ?? {}, callback);
    }

    function choose(options: var, callback: var): void {
        root.__enqueue("choose", options ?? {}, callback);
    }

    // Informational, one button. Returns nothing useful; the callback fires on dismissal.
    function alert(options: var, callback: var): void {
        root.__enqueue("alert", options ?? {}, callback);
    }

    function __enqueue(kind: string, options: var, callback: var): void {
        const entry = { kind: kind, options: options, callback: callback ?? null };
        if (root.current === null) {
            root.current = entry;
            return;
        }
        root.queue = root.queue.concat([entry]);
    }

    // Called by the dialog surface. `result` is a bool, a string or an index depending on kind.
    function resolve(result: var): void {
        const entry = root.current;
        root.current = null;
        if (entry?.callback)
            entry.callback(result);
        if (root.queue.length > 0) {
            const next = root.queue[0];
            root.queue = root.queue.slice(1);
            // Next frame, so the closing animation of one dialog is not cut off by the opening
            // of the next.
            Qt.callLater(() => root.current = next);
        }
    }

    function cancel(): void {
        const kind = root.current?.kind ?? "";
        root.resolve(kind === "prompt" ? "" : kind === "choose" ? -1 : false);
    }

    // ------------------------------------------------------------- file pickers

    // options: { title, directory, filter, save }
    //
    // filter is a space-separated list of MIME types, which is what kdialog wants:
    //   "image/png image/jpeg"
    function openFile(options: var, callback: var): void {
        const opts = options ?? {};
        const directory = PluginFs.expand(opts.directory ?? "~");
        const command = ["kdialog"];
        if (opts.title)
            command.push("--title", opts.title);
        command.push(opts.save ? "--getsavefilename" : "--getopenfilename", directory);
        if (opts.filter)
            command.push(opts.filter);
        root.__runPicker(command, callback);
    }

    function saveFile(options: var, callback: var): void {
        root.openFile(Object.assign({}, options ?? {}, { save: true }), callback);
    }

    function openFolder(options: var, callback: var): void {
        const opts = options ?? {};
        const command = ["kdialog"];
        if (opts.title)
            command.push("--title", opts.title);
        command.push("--getexistingdirectory", PluginFs.expand(opts.directory ?? "~"));
        root.__runPicker(command, callback);
    }

    function __runPicker(command: var, callback: var): void {
        PluginUtils.run(command, (stdout, code) => {
            // kdialog exits 1 when the user cancels, which is not an error to report.
            const path = code === 0 ? `${stdout}`.trim() : "";
            if (typeof callback === "function")
                callback(path);
        });
    }
}
