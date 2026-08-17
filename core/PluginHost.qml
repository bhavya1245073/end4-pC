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
import qs.services

Scope {
    id: root

    // Registers the qs.* modules plugin code imports. Must be instantiated, not
    // just present on disk, or its imports are never compiled. See the file.
    PluginModuleAnchors {}

    // Compiles plugin and built-in widget files in the background, so switching a plugin
    // on - or opening the quick panel for the first time - does not pay for compiling it
    // on the UI thread. See core/ComponentCache.qml.
    Prewarm {}

    // The surface PluginDialogs.confirm/prompt/choose draw into. Core rather than a plugin:
    // a confirmation that only appears when some optional plugin is enabled is worse than no
    // confirmation, because the caller has already decided to ask.
    PluginDialogHost {}

    // The surface PluginToast.show() draws into, for the same reason: feedback that depends on
    // an unrelated plugin being switched on is worse than none.
    PluginToastHost {}

    // Singletons are created on first use, and an IpcHandler inside one does not exist
    // until the singleton does - so a shell nobody has touched has no `perf` or `plugins`
    // IPC target. Touching them here registers the targets. The profiler's sampling timer
    // stays off until asked. See core/Perf.qml and core/PluginCommands.qml.
    Component.onCompleted: {
        Perf.running;
        PluginCommands.objectName;
        // Same reason: the lifecycle coordinator owns the idle monitor, and nothing binds to
        // it until a plugin asks - so without this, idle suspension would only start working
        // once some plugin happened to read it.
        PluginLifecycle.awake;
    }

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

    // IPC targets plugins register, so a plugin can add its own commands:
    //
    //     qs -c end4-pC ipc call gifs open
    //
    // Loaded like a service, but with the plugin's id pushed in so a handler can default
    // its target to it. See core/PluginIpc.qml.
    Instantiator {
        model: PluginRegistry.installedIpc

        delegate: PluginLoader {
            required property var modelData

            pluginId: modelData.pluginId
            entry: PluginRegistry.isLoaded(modelData.pluginId) ? modelData.url : ""
            // The command name, resolved here rather than in the plugin: the manifest can name one,
            // and the plugin id is the default. Injected instead of being a property on PluginIpc,
            // because a property on an IpcHandler brings a change signal that IpcHandler warns about.
            inject: ({
                target: modelData.target ?? modelData.pluginId
            })
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

    // Undo and redo for everything any plugin recorded. Core rather than per-plugin: the user
    // has one idea of "what did I just do", and a per-plugin binding would make Ctrl+Z depend
    // on which surface happened to have focus. See core/PluginHistory.qml.
    //
    // Bound in the compositor config as `quickshell:undo` / `quickshell:redo`, like every other
    // shell shortcut, so the keys stay the user's choice.
    CompositorGlobalShortcut {
        name: "undo"
        description: "Undo the last plugin action"
        onPressed: PluginHistory.undo()
    }

    CompositorGlobalShortcut {
        name: "redo"
        description: "Redo the last undone plugin action"
        onPressed: PluginHistory.redo()
    }
}
