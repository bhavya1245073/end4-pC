pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

Singleton {
    id: root

    // property string cliphistBinary: FileUtils.trimFileProtocol(`${Directories.home}/.cargo/bin/stash`)
    property string cliphistBinary: "cliphist"
    property real pasteDelay: 0.05
    property string pressPasteCommand: "ydotool key -d 1 29:1 47:1 47:0 29:0"
    property bool sloppySearch: Config.options?.search.sloppy ?? false
    property real scoreThreshold: 0.2
    property list<string> entries: []

    readonly property var preparedEntries: entries.map(a => ({
        name: Fuzzy.prepare(`${a.replace(/^\s*\S+\s+/, "")}`),
        entry: a
    }))

    function fuzzyQuery(search: string): var {
        if (search.trim() === "") {
            return entries;
        }
        if (root.sloppySearch) {
            const results = entries.slice(0, 100).map(str => ({
                entry: str,
                score: Levendist.computeTextMatchScore(str.toLowerCase(), search.toLowerCase())
            })).filter(item => item.score > root.scoreThreshold)
                .sort((a, b) => b.score - a.score)
            return results.map(item => item.entry)
        }

        return Fuzzy.go(search, preparedEntries, {
            all: true,
            key: "name"
        }).map(r => {
            return r.obj.entry
        });
    }

    function entryIsImage(entry) {
        return !!(/^\d+\t\[\[.*binary data.*\d+x\d+.*\]\]$/.test(entry))
    }

    function refresh() {
        readProc.buffer = []
        readProc.running = true
    }

    // Decode an entry and put it on the clipboard.
    //
    // The entry goes down cliphist.s stdin rather than into a shell command line. A clipboard entry
    // is the worst possible thing to interpolate into a shell string - it is arbitrary text the user
    // copied, quotes and newlines and backticks included - and escaping it correctly was one
    // StringUtils call away from a command injection.
    function copy(entry) {
        if (root.cliphistBinary.includes("cliphist")) { // Classic cliphist
            PluginUtils.pipe([root.cliphistBinary, "decode"], entry, decoded => PluginUtils.copy(decoded));
        } else { // Stash
            const entryNumber = entry.split("\t")[0];
            PluginUtils.run([root.cliphistBinary, "decode", entryNumber], decoded => PluginUtils.copy(decoded));
        }
    }

    // Decode, copy, then press the paste key.
    //
    // The keypress is a separate step rather than `&& wl-paste`: what the old command actually did
    // was print the clipboard to stdout, which pasted nothing. The key press is what pastes, and it
    // has to happen after the clipboard is set, which is why it is in the callback.
    function paste(entry) {
        const press = () => PluginUtils.exec(root.pressPasteCommand.split(" "));
        if (root.cliphistBinary.includes("cliphist")) { // Classic cliphist
            PluginUtils.pipe([root.cliphistBinary, "decode"], entry, decoded => {
                PluginUtils.copy(decoded);
                PluginTimer.after(root.pasteDelay * 1000, press);
            });
        } else { // Stash
            const entryNumber = entry.split("\t")[0];
            PluginUtils.run([root.cliphistBinary, "decode", entryNumber], decoded => {
                PluginUtils.copy(decoded);
                PluginTimer.after(root.pasteDelay * 1000, press);
            });
        }
    }

    // Paste several entries in order, oldest first.
    //
    // Sequenced with timers rather than a chain of `&& sleep && ...` in one shell command: each
    // entry is copied through a pipe, so no entry is ever quoted into a command line, and the delay
    // between them is the same one a single paste uses.
    function superpaste(count, isImage = false) {
        const targetEntries = entries.filter(entry => {
            if (!isImage) return true;
            return entryIsImage(entry);
        }).slice(0, count);

        const ordered = targetEntries.slice().reverse();
        const step = index => {
            if (index >= ordered.length)
                return;
            root.paste(ordered[index]);
            // Twice the paste delay: one for the clipboard to be set and the key press to land,
            // one for the receiving application to process it.
            PluginTimer.after(root.pasteDelay * 2000, () => step(index + 1));
        };
        step(0);
    }

    // The entry to delete goes down stdin, for the same reason copying does.
    function deleteEntry(entry) {
        PluginUtils.pipe([root.cliphistBinary, "delete"], entry, () => root.refresh());
    }

    function wipe() {
        root.entries = [];
        // Two steps rather than one shell line with a semicolon and a tilde in it: `rm -rf ~/...`
        // only works because a shell expands the tilde, and a path this destructive should not
        // depend on that.
        PluginUtils.run([root.cliphistBinary, "wipe"], () => {
            PluginFs.remove(`${PluginFs.cacheDir}/cliphist/db`, () => root.refresh());
        });
    }

    Connections {
        target: Quickshell
        function onClipboardTextChanged() {
            delayedUpdateTimer.restart()
        }
    }

    Timer {
        id: delayedUpdateTimer
        interval: Config.options.hacks.arbitraryRaceConditionDelay
        repeat: false
        onTriggered: {
            root.refresh()
        }
    }

    Process {
        id: readProc
        property list<string> buffer: []

        command: [root.cliphistBinary, "list"]

        stdout: SplitParser {
            onRead: (line) => {
                readProc.buffer.push(line)
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.entries = readProc.buffer
            } else {
                root.entries = []
                console.error("[Cliphist] Failed to refresh with code", exitCode, "and status", exitStatus)
            }
        }
    }

    IpcHandler {
        target: "cliphistService"

        function update(): void {
            root.refresh()
        }
    }
}