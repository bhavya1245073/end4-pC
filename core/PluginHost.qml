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

    // Registers the qs.* modules plugin code imports. Must be instantiated, not
    // just present on disk, or its imports are never compiled. See the file.
    PluginModuleAnchors {}

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

    // Keybinds declared in manifests. The registry was already collecting these and
    // nothing was acting on them, so a plugin could declare a shortcut that silently
    // did nothing.
    Instantiator {
        model: PluginRegistry.shortcuts
        delegate: PluginShortcut {
            required property var modelData
            descriptor: modelData
        }
    }
}
