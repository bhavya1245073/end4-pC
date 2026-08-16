// Commands for the drop shelf.
//
//   qs -c end4-pC ipc call dropover show
//   qs -c end4-pC ipc call dropover count
//   qs -c end4-pC ipc call dropover copy
//   qs -c end4-pC ipc call dropover clear
//
// `showAt` is what the desktop menu row uses through its declarative `panel` action, and what a
// keybind would use to put the shelf under the cursor.

import qs.core

PluginIpc {
    target: "dropover"

    function show(): string {
        PanelRegistry.open("dropover", ({}));
        return `Drop shelf open with ${DropShelfState.count} item(s)`;
    }

    function showAt(x: real, y: real): string {
        PanelRegistry.open("dropover", { x: x, y: y });
        return `Drop shelf open at ${x}, ${y}`;
    }

    function hide(): string {
        PanelRegistry.close("dropover");
        return "Drop shelf closed";
    }

    function toggle(): string {
        PanelRegistry.toggle("dropover", ({}));
        return PanelRegistry.isOpen("dropover") ? "Drop shelf open" : "Drop shelf closed";
    }

    function count(): int {
        return DropShelfState.count;
    }

    function list(): string {
        return DropShelfState.items.join("\n");
    }

    function copy(): string {
        DropShelfState.copyAll();
        return `Copied ${DropShelfState.count} path(s) as text/uri-list`;
    }

    function clear(): string {
        const had = DropShelfState.count;
        DropShelfState.clear();
        return `Cleared ${had} item(s)`;
    }
}
