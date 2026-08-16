pragma Singleton

// Files, without the ceremony.
//
//     PluginFs.read("~/.gitconfig", result => { if (result.ok) parse(result.text) })
//     PluginFs.readJson("~/.config/app/state.json", result => ...)
//     PluginFs.write("/tmp/note.txt", "hello", result => ...)
//     PluginFs.writeJson(PluginFs.expand("~/.cache/mine.json"), { a: 1 })
//     PluginFs.list("~/Pictures", result => result.entries.forEach(...))
//     PluginFs.exists("/etc/os-release", yes => ...)
//
// Every call is asynchronous and every callback gets the same shape:
//
//     { ok: bool, path: string, text: string, data: var, entries: [...], error: string }
//
// so a caller checks `ok` and never has to know which of the four failure modes it hit.
//
// Watching is separate, because a watch is a lifetime:
//
//     PluginFsWatch { path: "~/notes/todo.md"; onChanged: text => reload(text) }
//
// Writes are atomic (write to a temporary file, rename over the target), so a reader
// never sees a half-written file and a crash mid-write cannot lose the old contents.
//
// `~` is expanded here, not by a shell. Every path argument accepts it, including inside
// list() and watch().

import QtQuick
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property string configDir: Quickshell.env("XDG_CONFIG_HOME") || `${root.home}/.config`
    readonly property string cacheDir: Quickshell.env("XDG_CACHE_HOME") || `${root.home}/.cache`
    readonly property string dataDir: Quickshell.env("XDG_DATA_HOME") || `${root.home}/.local/share`
    readonly property string stateDir: Quickshell.env("XDG_STATE_HOME") || `${root.home}/.local/state`
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"

    // "~/x" and "$HOME/x" and "file:///x" all become "/home/you/x". A path that is
    // already absolute comes back untouched.
    function expand(path: string): string {
        let result = `${path ?? ""}`;
        if (result.startsWith("file://"))
            result = result.slice(7);
        if (result === "~")
            return root.home;
        if (result.startsWith("~/"))
            return root.home + result.slice(1);
        if (result.startsWith("$HOME"))
            return root.home + result.slice(5);
        return result;
    }

    function url(path: string): string {
        return `file://${root.expand(path)}`;
    }

    function dirname(path: string): string {
        const full = root.expand(path);
        const cut = full.lastIndexOf("/");
        return cut <= 0 ? "/" : full.slice(0, cut);
    }

    function basename(path: string): string {
        const full = root.expand(path);
        return full.slice(full.lastIndexOf("/") + 1);
    }

    function extension(path: string): string {
        const name = root.basename(path);
        const dot = name.lastIndexOf(".");
        return dot <= 0 ? "" : name.slice(dot + 1).toLowerCase();
    }

    function join(...parts): string {
        return parts.filter(part => part !== undefined && part !== null && `${part}`.length > 0)
            .map((part, index) => index === 0 ? `${part}`.replace(/\/+$/, "") : `${part}`.replace(/^\/+|\/+$/g, ""))
            .join("/");
    }

    // ------------------------------------------------------------------- read

    // callback({ ok, path, text, error })
    function read(path: string, callback: var): void {
        const full = root.expand(path);
        const view = oneShotReader.createObject(root, { path: full });
        view.finished.connect(result => {
            if (typeof callback === "function")
                callback(result);
            view.destroy();
        });
        view.start();
    }

    // callback({ ok, path, data, text, error }) - `ok` is false for unparseable JSON too,
    // with the parse message in `error`, which is the distinction callers actually need.
    function readJson(path: string, callback: var): void {
        root.read(path, result => {
            if (!result.ok)
                return callback ? callback(result) : undefined;
            try {
                result.data = JSON.parse(result.text);
            } catch (error) {
                result.ok = false;
                result.error = `not valid JSON: ${error.message}`;
            }
            if (callback)
                callback(result);
        });
    }

    // Lines, with the trailing newline's empty string dropped - the shape /proc and
    // /sys files come in.
    function readLines(path: string, callback: var): void {
        root.read(path, result => {
            result.lines = result.ok ? result.text.split("\n").filter((line, index, all) => index < all.length - 1 || line.length > 0) : [];
            if (callback)
                callback(result);
        });
    }

    // ------------------------------------------------------------------ write

    // Creates parent directories, writes atomically. callback({ ok, path, error })
    function write(path: string, text: string, callback: var): void {
        const full = root.expand(path);
        root.mkdir(root.dirname(full), () => {
            const view = oneShotWriter.createObject(root, { path: full, payload: text });
            view.finished.connect(result => {
                if (typeof callback === "function")
                    callback(result);
                view.destroy();
            });
            view.start();
        });
    }

    function writeJson(path: string, value: var, callback: var): void {
        root.write(path, JSON.stringify(value, null, 2) + "\n", callback);
    }

    // Read-modify-write. Not an O_APPEND write: FileView has no append mode, and doing it
    // this way keeps the atomic rename, so a log file cannot end up truncated.
    function append(path: string, text: string, callback: var): void {
        root.read(path, result => {
            const existing = result.ok ? result.text : "";
            root.write(path, existing + text, callback);
        });
    }

    // Rewrites a JSON file through a transform:
    //
    //     PluginFs.updateJson("~/.cache/x.json", current => Object.assign({}, current, { seen: true }))
    //
    // (Object.assign, not `{ ...current }`: Qt's JS engine has no object spread.)
    function updateJson(path: string, transform: var, callback: var): void {
        root.readJson(path, result => {
            const current = result.ok ? result.data : undefined;
            let updated;
            try {
                updated = transform(current);
            } catch (error) {
                if (callback)
                    callback({ ok: false, path: root.expand(path), error: `transform threw: ${error.message ?? error}` });
                return;
            }
            if (updated === undefined) {
                if (callback)
                    callback({ ok: true, path: root.expand(path), skipped: true });
                return;
            }
            root.writeJson(path, updated, callback);
        });
    }

    // ------------------------------------------------------------- filesystem
    //
    // argv, never a shell string: a path with a space or a quote in it is ordinary and
    // must not need escaping.

    function mkdir(path: string, callback: var): void {
        PluginUtils.run(["mkdir", "-p", root.expand(path)], (stdout, code) => {
            if (typeof callback === "function")
                callback({ ok: code === 0, path: root.expand(path), error: code === 0 ? "" : `mkdir exited ${code}` });
        });
    }

    function remove(path: string, callback: var): void {
        const full = root.expand(path);
        if (full === "/" || full === root.home || full.length < 4) {
            console.warn(`[fs] refusing to remove "${full}"`);
            if (typeof callback === "function")
                callback({ ok: false, path: full, error: "refused" });
            return;
        }
        PluginUtils.run(["rm", "-rf", "--", full], (stdout, code) => {
            if (typeof callback === "function")
                callback({ ok: code === 0, path: full, error: code === 0 ? "" : `rm exited ${code}` });
        });
    }

    function copy(from: string, to: string, callback: var): void {
        PluginUtils.run(["cp", "-a", "--", root.expand(from), root.expand(to)], (stdout, code) => {
            if (typeof callback === "function")
                callback({ ok: code === 0, path: root.expand(to), error: code === 0 ? "" : `cp exited ${code}` });
        });
    }

    function move(from: string, to: string, callback: var): void {
        PluginUtils.run(["mv", "--", root.expand(from), root.expand(to)], (stdout, code) => {
            if (typeof callback === "function")
                callback({ ok: code === 0, path: root.expand(to), error: code === 0 ? "" : `mv exited ${code}` });
        });
    }

    // callback(bool). A read that fails is the test, so this costs one open for a file
    // that exists - fine for the config-sized files this is used on.
    function exists(path: string, callback: var): void {
        PluginUtils.run(["test", "-e", root.expand(path)], (stdout, code) => {
            if (typeof callback === "function")
                callback(code === 0);
        });
    }

    // callback({ ok, path, entries: [{ name, path, isDir, size, suffix }], error })
    //
    // Uses FolderListModel rather than parsing ls output. The existence check in front of
    // it is not redundant: FolderListModel accepts a path that does not exist and reports
    // zero entries, so without it a typo returns "ok, empty" - and when it is pointed at a
    // bad path *after* listing something else it keeps the old contents, which is why each
    // entry's own path is checked below as well.
    function list(path: string, callback: var, options: var): void {
        const full = root.expand(path);
        PluginUtils.run(["test", "-d", full], (stdout, code) => {
            if (code !== 0) {
                if (typeof callback === "function")
                    callback({ ok: false, path: full, entries: [], error: "no such directory" });
                return;
            }
            const lister = oneShotLister.createObject(root, {
                base: full,
                nameFilters: options?.filters ?? [],
                showFiles: options?.files ?? true,
                showDirs: options?.dirs ?? true,
                showHidden: options?.hidden ?? false
            });
            lister.finished.connect(result => {
                if (typeof callback === "function")
                    callback(result);
                lister.destroy();
            });
            lister.start();
        });
    }

    // Contents right now, or "" if unreadable.
    //
    // This blocks the UI thread, and that is the point: /proc and /sys files are generated
    // on read and cost tens of microseconds, and an asynchronous read of them means every
    // consumer is one poll behind - a CPU meter that shows the previous sample forever.
    // Do not point it at anything on a real disk, at anything that can be on a network
    // mount, or at anything large.
    function readSync(path: string): string {
        const view = syncReader.createObject(root, { path: root.expand(path) });
        const text = view.read();
        view.destroy();
        return text;
    }

    // First line, trimmed - the shape of nearly every sysfs value.
    function readSyncNumber(path: string, fallback: real): real {
        const text = root.readSync(path).trim();
        if (text.length === 0)
            return fallback;
        const value = parseFloat(text);
        return isNaN(value) ? fallback : value;
    }

    readonly property Component syncReader: Component {
        QtObject {
            id: syncView
            property string path: ""

            function read(): string {
                try {
                    return view.text() ?? "";
                } catch (error) {
                    return "";
                }
            }

            readonly property FileView __view: FileView {
                id: view
                path: syncView.path
                printErrors: false
                blockLoading: true
            }
        }
    }

    // ---------------------------------------------------------------- watching

    // Imperative watch; returns a token for unwatch(). Prefer PluginFsWatch in a widget,
    // which cannot leak the watcher.
    property var __watchers: ({})
    property int __nextWatch: 1

    function watch(path: string, callback: var): int {
        const token = root.__nextWatch++;
        const watcher = watcherComponent.createObject(root, { path: root.expand(path) });
        watcher.changed.connect(text => callback(text));
        root.__watchers[token] = watcher;
        return token;
    }

    function unwatch(token: int): void {
        const watcher = root.__watchers[token];
        if (!watcher)
            return;
        watcher.destroy();
        delete root.__watchers[token];
    }

    // --------------------------------------------------------------- internals

    readonly property Component oneShotReader: Component {
        QtObject {
            id: reader
            property string path: ""
            signal finished(var result)

            function start(): void {
                // Assigning the path is what starts the load; the handlers below fire once.
                view.path = reader.path;
            }

            readonly property FileView __view: FileView {
                id: view
                printErrors: false
                onLoaded: reader.finished({ ok: true, path: reader.path, text: this.text(), error: "" })
                onLoadFailed: error => reader.finished({ ok: false, path: reader.path, text: "", error: `${error}` })
            }
        }
    }

    readonly property Component oneShotWriter: Component {
        QtObject {
            id: writer
            property string path: ""
            property string payload: ""
            signal finished(var result)

            function start(): void {
                view.path = writer.path;
                view.setText(writer.payload);
            }

            readonly property FileView __view: FileView {
                id: view
                printErrors: false
                atomicWrites: true
                onSaved: writer.finished({ ok: true, path: writer.path, error: "" })
                onSaveFailed: error => writer.finished({ ok: false, path: writer.path, error: `${error}` })
            }
        }
    }

    readonly property Component oneShotLister: Component {
        QtObject {
            id: lister
            property string base: ""
            property var nameFilters: []
            property bool showFiles: true
            property bool showDirs: true
            property bool showHidden: false
            signal finished(var result)

            function start(): void {
                model.folder = `file://${lister.base}`;
                // FolderListModel populates asynchronously and reports nothing when it is
                // done, so settle on the first tick where the count has stopped moving.
                settle.restart();
            }

            function collect(): void {
                const entries = [];
                const prefix = `${lister.base}/`;
                for (let i = 0; i < model.count; i++) {
                    const name = model.get(i, "fileName") ?? "";
                    const filePath = model.get(i, "filePath") ?? "";
                    // An entry whose own path is not under the requested directory means the
                    // model is still listing a previous folder.
                    if (filePath !== prefix + name)
                        continue;
                    entries.push({
                        name: name,
                        path: filePath,
                        isDir: model.get(i, "fileIsDir") === true,
                        size: model.get(i, "fileSize") ?? 0,
                        suffix: model.get(i, "fileSuffix") ?? ""
                    });
                }
                lister.finished({ ok: true, path: lister.base, entries: entries, error: "" });
            }

            readonly property FolderListModel __model: FolderListModel {
                id: model
                showDirs: lister.showDirs
                showFiles: lister.showFiles
                showHidden: lister.showHidden
                showDotAndDotDot: false
                sortField: FolderListModel.Name
                nameFilters: lister.nameFilters
                onCountChanged: settle.restart()
            }

            readonly property Timer __settle: Timer {
                id: settle
                interval: 40
                onTriggered: lister.collect()
            }
        }
    }

    readonly property Component watcherComponent: Component {
        QtObject {
            id: watcher
            property string path: ""
            signal changed(string text)

            readonly property FileView __view: FileView {
                path: watcher.path
                printErrors: false
                watchChanges: true
                onFileChanged: this.reload()
                onLoaded: watcher.changed(this.text())
            }
        }
    }
}
