// One action a plugin implements, reachable from everywhere.
//
//     PluginIntentHandler {
//         pluginId: "gif-picker"
//         action: "search"
//         onInvoked: args => GifState.search(args.query)
//     }
//
// Declare it in the plugin's manifest under `provides.actions` and put this anywhere the
// plugin already instantiates - its service is the natural home, because a service is
// loaded whenever the plugin is on.
//
// `args` arrives already validated against the manifest's schema: required arguments are
// present, numbers are numbers, paths are expanded. So the handler reads `args.query`
// without checking it, which is what declaring a schema is for.
//
// Return a value to hand it back to the caller - `qs ipc call intent call ...` prints it,
// and PluginIntent.call() returns it in `result`. Returning nothing is fine.
//
// Registration follows the object's lifetime: the action stops resolving when the plugin is
// switched off, rather than resolving to a handler whose plugin is gone.

import QtQuick
import qs.core

QtObject {
    id: root

    property string pluginId: ""
    property string action: ""

    readonly property string ref: `${root.pluginId}:${root.action}`

    // Called with the validated argument object. Assign a function, or use `onInvoked`.
    signal invoked(var args);

    // PluginIntent calls this. Split from the signal so a handler can return a value: a
    // signal emission cannot.
    property var handle: null

    function invoke(args: var): var {
        root.invoked(args);
        if (typeof root.handle === "function")
            return root.handle(args);
        return null;
    }

    Component.onCompleted: {
        if (!root.pluginId || !root.action) {
            console.warn(`[intent] a PluginIntentHandler with no pluginId ("${root.pluginId}")`
                + ` or action ("${root.action}") cannot be registered`);
            return;
        }
        PluginIntent.register(root.ref, root);
    }

    Component.onDestruction: {
        if (root.pluginId && root.action)
            PluginIntent.unregister(root.ref);
    }
}
