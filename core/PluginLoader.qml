// Loads one QML file belonging to a plugin, contained so that a broken plugin
// logs an error instead of taking the shell down with it.
//
// `inject` is applied as initial properties. Use Qt.binding() for values that
// must stay live:
//
//     PluginLoader {
//         pluginId: widget.pluginId
//         entry: widget.url
//         inject: ({ vertical: Qt.binding(() => root.vertical) })
//     }

import QtQuick

Loader {
    id: root

    property string pluginId: ""
    property string entry: ""
    property var inject: ({})

    function reloadEntry() {
        if (!root.entry) {
            root.source = "";
            return;
        }
        root.setSource(root.entry, root.inject);
    }

    onEntryChanged: root.reloadEntry()
    Component.onCompleted: root.reloadEntry()

    onStatusChanged: {
        if (root.status === Loader.Error)
            console.warn(`[plugins] ${root.pluginId}: could not load ${root.entry}`);
    }
}
