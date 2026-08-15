// Instantiates everything plugins contribute at shell scope: their long-lived
// services and their windows.
//
// This is the whole of shell.qml's job besides bootstrapping - a plugin appears
// here purely by existing on disk with a manifest.

import QtQuick
import QtQml
import Quickshell
import qs.modules.common

Scope {
    id: root

    // Non-visual, always-on objects (timers, watchers, IPC handlers).
    Instantiator {
        model: PluginRegistry.services
        delegate: LazyLoader {
            required property var modelData
            source: modelData.url
            active: Config.ready
        }
    }

    // Windows. Each panel decides its own visibility; the loader only decides
    // whether the plugin providing it is switched on.
    Instantiator {
        model: PluginRegistry.panels
        delegate: LazyLoader {
            required property var modelData
            source: modelData.url
            active: Config.ready
        }
    }
}
