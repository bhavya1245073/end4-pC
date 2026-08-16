// Instantiates everything plugins contribute at shell scope: their long-lived
// services and their windows.
//
// This is the whole of shell.qml's job besides bootstrapping - a plugin appears
// here purely by existing on disk with a manifest.
//
// ## Two reasons enabling a plugin used to freeze the shell for a minute
//
// **The model was reassigned.** An Instantiator over a plain JS array cannot tell one
// array from the next, so when the array is reassigned it destroys and recreates
// every delegate. The obvious model here is `PluginRegistry.panels`, which holds only
// active plugins - and that is the trap: it is reassigned whenever *any* plugin is
// toggled, so enabling one plugin tore down and rebuilt every other plugin's panels
// and services. The model is now every installed entry, which changes only when a
// plugin appears or disappears on disk, and the enabled state lives on the delegate.
//
// **`active` blocks.** Per LazyLoader's docs, setting `active: true` "will force the
// component to load to completion, blocking the UI". Every panel and service was
// therefore loaded synchronously, on the UI thread, at startup and on every toggle.
// `activeAsync` loads in the gaps between frames instead.
//
// The models also key off `PluginRegistry.isLoaded` rather than `isActive`. That one
// lags by an event-loop turn, so the frame acknowledging the click in the GUI gets
// painted before a heavy plugin starts loading. See the registry for why.
//
// Together: toggling a plugin now flips one boolean and loads or unloads exactly that
// plugin, without blocking. Note that a panel using `Variants` internally still
// blocks while *it* loads - Quickshell documents that Variants has no async support -
// but that is now one plugin's cost rather than nineteen.

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
        model: PluginRegistry.installedServices

        delegate: LazyLoader {
            required property var modelData

            source: modelData.url
            activeAsync: Config.ready && PluginRegistry.isLoaded(modelData.pluginId)
        }
    }

    // Windows. Each panel decides its own visibility; the loader only decides
    // whether the plugin providing it is switched on.
    Instantiator {
        model: PluginRegistry.installedPanels

        delegate: LazyLoader {
            required property var modelData

            source: modelData.url
            activeAsync: Config.ready && PluginRegistry.isLoaded(modelData.pluginId)
        }
    }

    // Keybinds declared in manifests. The registry was already collecting these and
    // nothing was acting on them, so a plugin could declare a shortcut that silently
    // did nothing.
    Instantiator {
        model: PluginRegistry.installedShortcuts

        delegate: Loader {
            required property var modelData

            active: PluginRegistry.isActive(modelData.pluginId)

            sourceComponent: PluginShortcut {
                descriptor: modelData
            }
        }
    }
}
