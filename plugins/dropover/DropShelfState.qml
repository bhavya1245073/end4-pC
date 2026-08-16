pragma Singleton

// What the drop shelf is holding.
//
// Plugin-local: this used to be a core singleton (modules/common/widgets/DropShelf.qml), which meant
// the shell carried a list of one plugin's files and two globals for where its window sits. Core now
// knows only that *something* may want files dropped on the desktop, and says so on the bus.
//
// The count is published as `dropover:count`, which is what the desktop menu's badge binds to - the
// menu therefore shows a live count without a line of code that mentions this plugin.

import QtQuick
import Quickshell
import qs.core
import qs.modules.common.functions

Singleton {
    id: root

    property var items: []
    property int maxItems: 30

    readonly property int count: root.items.length

    function addItems(urls) {
        const kept = root.items.slice();
        for (const url of urls) {
            const path = FileUtils.trimFileProtocol(decodeURIComponent(url.toString()));
            if (!kept.includes(path) && kept.length < root.maxItems)
                kept.push(path);
        }
        root.items = kept;
    }

    function show(urls, x, y) {
        root.addItems(urls);
        PanelRegistry.open("dropover", { x: x, y: y });
    }

    function remove(path) {
        root.items = root.items.filter(candidate => candidate !== path);
    }

    // A file manager pastes a drop of files when the clipboard offers text/uri-list, not plain
    // text - so this needs a typed copy rather than PluginUtils.copy.
    function copyAll() {
        if (root.items.length === 0)
            return;
        PluginUtils.copyTyped(root.items.map(path => `file://${path}`).join("\n"), "text/uri-list");
    }

    function clear() {
        root.items = [];
        PanelRegistry.close("dropover");
    }

    function hide() {
        PanelRegistry.close("dropover");
    }

    // Files dropped on the desktop. Core publishes this without knowing a shelf exists; the shelf
    // picks it up by subscribing, which is the whole of the decoupling.
    readonly property PluginBusListener __drops: PluginBusListener {
        topic: "desktop:filesDropped"
        onReceived: payload => root.show(payload.urls ?? [], payload.x ?? 0, payload.y ?? 0)
    }

    // Every change, so the desktop menu badge and anything else interested stays current without
    // polling or importing this file.
    onCountChanged: PluginBus.publish("dropover:count", root.count)
    Component.onCompleted: PluginBus.publish("dropover:count", root.count)
}
