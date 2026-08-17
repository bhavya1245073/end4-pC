pragma Singleton

// What the user is doing right now, so a plugin can act on it instead of asking.
//
// The difference this makes: a translator plugin opened with text selected translates that
// text rather than showing an empty box. A drop shelf opens on the monitor the pointer is
// on. A GIF picker pastes Discord-flavoured markup when Discord is focused and a bare URL
// when it is not. None of that is possible from inside a plugin's own surface, because a
// shell surface takes focus away from exactly the window the plugin needs to know about.
//
//     PluginContext.focusedApp.windowClass     // "discord"
//     PluginContext.selectedText               // what is highlighted, anywhere
//     PluginContext.clipboard.hasFiles
//     PluginContext.activeMonitor.name
//     PluginContext.activeWorkspace
//
// ## Focus is captured, not read live
//
// By the time a plugin's window is open, *it* is the focused window - so reading focus at
// that point returns the shell. `focusedApp` is therefore the last non-shell window that
// had focus, latched as focus moves. That is what every caller means by "the app I was
// just in", and it is the difference between a working paste target and pasting into
// oneself.
//
// ## The primary selection is polled, but only when asked
//
// There is no Wayland event for "the selection changed"; the protocol only lets a client
// read the primary selection when it asks. Polling it constantly would spawn a process a
// second forever, so `selectedText` is refreshed on demand: `refreshSelection()`, or
// automatically when something first binds to it after `selectionMaxAgeMs`. A plugin that
// wants it fresh at the moment of a keypress calls `refreshSelection()` and reads it in the
// callback.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.core
import qs.services

Singleton {
    id: root

    // ------------------------------------------------------------ focused app

    // The live focused toplevel, which is the shell itself whenever a plugin surface has
    // focus. Plugins want `focusedApp` below instead.
    readonly property Toplevel liveToplevel: ToplevelManager.activeToplevel

    // Set of app ids belonging to this shell, so they are never latched as "the app the user
    // was in". Quickshell reports its own surfaces under its own app id.
    readonly property var ownAppIds: ["quickshell", "org.quickshell", ""]

    // The last real application to hold focus: { title, windowClass, address, pid, at }.
    property var focusedApp: ({ title: "", windowClass: "", address: "", pid: 0, at: 0 })

    readonly property var __focusWatch: {
        const toplevel = root.liveToplevel;
        if (!toplevel)
            return null;

        const appId = toplevel.appId ?? "";
        if (root.ownAppIds.includes(appId))
            return null;

        // Deferred: this runs inside a binding evaluation, and assigning a property that
        // other bindings read from inside one is how binding loops start.
        const captured = {
            title: toplevel.title ?? "",
            windowClass: appId,
            address: root.__addressOf(appId, toplevel.title ?? ""),
            pid: root.__pidOf(appId),
            at: Date.now()
        };
        Qt.callLater(() => root.focusedApp = captured);
        return null;
    }

    // Address and pid come from the window list, which the WM service already tracks - so
    // this costs a lookup rather than an hyprctl call.
    function __addressOf(appId: string, title: string): string {
        const match = PluginWM.windows.find(window => window.appId === appId && window.title === title)
            ?? PluginWM.windows.find(window => window.appId === appId);
        return match ? String(match.id ?? "") : "";
    }

    function __pidOf(appId: string): int {
        const match = PluginWM.windows.find(window => window.appId === appId);
        return match?.pid ?? 0;
    }

    // "Is the user in a terminal / in Discord / in a browser", asked without every plugin
    // hard-coding app id lists.
    function focusedIs(appIdFragment: string): bool {
        return (root.focusedApp.windowClass ?? "").toLowerCase().includes((appIdFragment ?? "").toLowerCase());
    }

    // ---------------------------------------------------------- selected text

    // The primary selection as of the last refresh, and how old that is.
    property string selectedText: ""
    property real selectionAt: 0
    readonly property real selectionAgeMs: root.selectionAt === 0 ? Infinity : Date.now() - root.selectionAt
    readonly property bool hasSelection: root.selectedText.length > 0

    // How long a captured selection is treated as current.
    readonly property int selectionMaxAgeMs: 4000

    // Refreshes the primary selection and calls back with it. Safe to call often - a refresh
    // already in flight is joined rather than duplicated.
    function refreshSelection(callback: var): void {
        if (typeof callback === "function")
            root.__selectionCallbacks = root.__selectionCallbacks.concat([callback]);
        if (selectionProcess.running)
            return;
        selectionProcess.running = true;
    }

    property var __selectionCallbacks: []

    Process {
        id: selectionProcess

        // The primary selection, not the clipboard: what is highlighted, which is what
        // "selected text" means to a user and what middle-click pastes.
        command: ["wl-paste", "--primary", "--no-newline", "--type", "text/plain"]

        stdout: StdioCollector {
            onStreamFinished: {
                root.selectedText = this.text ?? "";
                root.selectionAt = Date.now();
                root.__drainSelectionCallbacks();
            }
        }

        onExited: (code, status) => {
            // Exit 1 with no output means "nothing is selected", which is not a failure.
            if (code !== 0) {
                root.selectedText = "";
                root.selectionAt = Date.now();
                root.__drainSelectionCallbacks();
            }
        }
    }

    function __drainSelectionCallbacks(): void {
        const callbacks = root.__selectionCallbacks;
        root.__selectionCallbacks = [];
        for (const callback of callbacks) {
            try {
                callback(root.selectedText);
            } catch (e) {
                console.warn("[context] selection callback threw:", e);
            }
        }
    }

    // ------------------------------------------------------------- clipboard

    readonly property QtObject clipboard: QtObject {
        // Quickshell keeps a clipboard connection open, so text is free to read.
        readonly property string text: Quickshell.clipboardText ?? ""
        readonly property bool hasText: (Quickshell.clipboardText ?? "").length > 0

        // Whether the clipboard holds file paths. Derived from the text rather than from
        // MIME types, because reading the MIME list means spawning wl-paste, and this is
        // right for every case that matters: a file manager copy puts file:// URIs on the
        // clipboard as text too.
        readonly property bool hasFiles: {
            const value = Quickshell.clipboardText ?? "";
            if (value.length === 0)
                return false;
            return value.split("\n").every(line => line.trim().length === 0 || line.trim().startsWith("file://"));
        }

        readonly property var files: {
            if (!this.hasFiles)
                return [];
            return (Quickshell.clipboardText ?? "").split("\n")
                .map(line => line.trim())
                .filter(line => line.startsWith("file://"))
                .map(line => decodeURIComponent(line.replace(/^file:\/\//, "")));
        }
    }

    // --------------------------------------------------------------- displays

    // The monitor the user is on: whichever holds the focused window, falling back to the
    // compositor's focused monitor. Where a new floating window belongs.
    readonly property var activeMonitor: PluginWM.focusedMonitor

    readonly property int activeWorkspace: PluginWM.activeWorkspaceId
    readonly property string activeWorkspaceName: PluginWM.activeWorkspaceName

    // ------------------------------------------------------------------ shape

    // Everything at once, for a plugin that wants to snapshot the context at the moment it
    // was invoked rather than bind to it - which is usually what an action wants, because
    // by the time it runs the context has moved on.
    function snapshot(): var {
        return {
            focusedApp: Object.assign({}, root.focusedApp),
            selectedText: root.selectedText,
            selectionAgeMs: root.selectionAgeMs,
            clipboardText: root.clipboard.text,
            clipboardHasFiles: root.clipboard.hasFiles,
            clipboardFiles: root.clipboard.files,
            monitor: root.activeMonitor ? Object.assign({}, root.activeMonitor) : null,
            workspace: root.activeWorkspace,
            at: Date.now()
        };
    }
}
