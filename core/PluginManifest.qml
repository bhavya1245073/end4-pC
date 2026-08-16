// Reads and validates a single plugins/<id>/manifest.json.
//
// One of these exists per discovered plugin directory; PluginRegistry
// instantiates them and receives the parsed manifest through register().

import QtQuick
import Quickshell.Io
import qs.services

QtObject {
    id: root

    required property string pluginId

    readonly property string path: `${PluginRegistry.dirOf(root.pluginId)}/manifest.json`

    function parse() {
        const raw = manifestFile.text();
        if (raw.trim().length === 0) {
            PluginRegistry.reportError(root.pluginId, Translation.tr("manifest.json is empty"));
            return;
        }
        let manifest;
        try {
            manifest = JSON.parse(raw);
        } catch (error) {
            PluginRegistry.reportError(root.pluginId, Translation.tr("manifest.json is not valid JSON: %1").arg(error.message));
            return;
        }
        PluginRegistry.register(root.pluginId, manifest);
    }

    property FileView manifestFile: FileView {
        path: root.path
        printErrors: false
        watchChanges: true
        onFileChanged: this.reload()
        onLoaded: root.parse()
        onLoadFailed: error => PluginRegistry.reportError(root.pluginId, Translation.tr("manifest.json could not be read (%1)").arg(error))
    }
}
