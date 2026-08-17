// An IPC target owned by a plugin.
//
// Declare the file in the manifest:
//
//     "provides": {
//         "ipc": [{ "entry": "GifIpc.qml" }]
//     }
//
// and make its root a PluginIpc:
//
//     PluginIpc {
//         target: "gifs"
//
//         function open(): void {
//             GifPicker.open();
//         }
//
//         function search(query: string): void {
//             GifPicker.search(query);
//         }
//     }
//
// Every function declared on it becomes a command:
//
//     qs -c end4-pC ipc call gifs open
//     qs -c end4-pC ipc call gifs search "cat"
//
// which also means it is bindable from the compositor without any keybind support from
// the shell at all:
//
//     bind = SUPER, G, exec, qs -c end4-pC ipc call gifs open
//
// though `provides.shortcuts` is better for that - it gets you a `quickshell:` global,
// which the compositor dispatches without spawning a process. See PluginShortcut.
//
// ## Rules
//
// Annotate parameters and return types. Quickshell's IPC layer needs the types to
// marshal a call from the command line, and an unannotated function is not exposed.
// `void` is a real return type here; say so.
//
// `target` defaults to the plugin's id, so two plugins cannot silently collide, and the
// registry refuses a target that a built-in already owns.

import QtQuick
import Quickshell.Io

IpcHandler {
    id: root

    // `target` is injected by the host: the plugin id, or the manifest entry's `target` if it names
    // a nicer command. It is not a property declared here on purpose - IpcHandler inspects its own
    // members to decide what to expose, and a declared property brings a `<name>Changed` signal with
    // it, which it warns about on every load. One line of log noise per IPC plugin, every start.

    // Handlers are only reachable while the plugin is on; the host binds this.
    enabled: true

    // Registers with the shell so the same functions can be called *in-process* - by a
    // context menu row, a quick toggle, another part of the shell - instead of only from
    // the command line. Without this, anything inside the shell wanting to trigger a
    // plugin action had to spawn `qs ipc call`, which is a process per click.
    Component.onCompleted: PluginRegistry.registerIpc(root)
    Component.onDestruction: PluginRegistry.unregisterIpc(root)
}
