// A live view of a file, reloaded whenever it changes on disk.
//
//     PluginFsWatch {
//         path: "~/notes/todo.md"
//         onChanged: text => root.todo = text.split("\n")
//     }
//
//     PluginFsWatch {
//         path: "/sys/class/power_supply/BAT0/capacity"
//         onChanged: text => root.percent = parseInt(text)
//     }
//
// `text` is also a property, so a binding can read it directly without a handler:
//
//     StyledText { text: watcher.text }
//
// The watcher goes away with the object that declared it, which is the difference from
// PluginFs.watch(): a widget destroyed by toggling its plugin off cannot leave an inotify
// watch and a closure behind.
//
// `json` parses the contents when they look like JSON, so a state file is one property
// away: `watcher.json?.lastSync`.

import QtQuick
import Quickshell.Io
import qs.core

QtObject {
    id: root

    property string path: ""
    property bool enabled: true

    // Latest contents. Empty until the first load, or when the file is unreadable.
    readonly property string text: root.__text
    readonly property bool ok: root.__ok
    readonly property string error: root.__error

    // Parsed contents, or undefined when the file is not JSON. Computed lazily on read.
    readonly property var json: {
        if (!root.__ok || root.__text.length === 0)
            return undefined;
        try {
            return JSON.parse(root.__text);
        } catch (error) {
            return undefined;
        }
    }

    signal changed(string text)
    signal failed(string error)

    property string __text: ""
    property bool __ok: false
    property string __error: ""

    readonly property FileView __view: FileView {
        path: root.enabled ? PluginFs.expand(root.path) : ""
        printErrors: false
        watchChanges: true
        onFileChanged: this.reload()
        onLoaded: {
            root.__text = this.text();
            root.__ok = true;
            root.__error = "";
            root.changed(root.__text);
        }
        onLoadFailed: error => {
            root.__ok = false;
            root.__error = `${error}`;
            root.failed(root.__error);
        }
    }

    // Force a re-read, for a file whose mtime does not change when its contents do -
    // /proc and /sys are both like that.
    function reload(): void {
        root.__view.reload();
    }
}
