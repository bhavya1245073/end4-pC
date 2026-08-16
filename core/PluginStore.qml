// Declarative access to a plugin's persistent storage.
//
//     PluginStore { id: store }                   // inside a plugin widget: id inferred
//     PluginStore { id: store; pluginId: "weather" }
//
//     Component.onCompleted: if (store.loaded) store.set("lastSeen", Date.now())
//     text: store.get("city", "London")
//
// `pluginId` is inferred by walking up to the nearest object that has one - every widget
// base type (PluginBarWidget, PluginBackgroundWidget, PluginDesktopCard, PluginPopup)
// exposes it - so a widget normally needs no argument. Set it explicitly in a plugin
// service or anywhere the chain does not reach.

import QtQuick
import qs.core

QtObject {
    id: root

    property string pluginId: root.__inferred

    // The underlying store; `values` on it is what to bind to for a whole-object read.
    readonly property var store: PluginStorage.of(root.pluginId)

    // One property per read so bindings stay precise.
    readonly property var values: root.store.values

    // False until plugins.json has been read: a plugin that writes before this is true
    // writes on top of empty storage.
    readonly property bool loaded: PluginStorage.loaded

    function get(key: string, fallback: var): var { return root.store.get(key, fallback); }
    function has(key: string): bool { return root.store.has(key); }
    function set(key: string, value: var): void { root.store.set(key, value); }
    function merge(patch: var): void { root.store.merge(patch); }
    function update(key: string, transform: var): void { root.store.update(key, transform); }
    function remove(key: string): void { root.store.remove(key); }
    function keys(): var { return root.store.keys(); }
    function clear(): void { root.store.clear(); }

    function list(name: string): var { return root.store.list(name); }
    function count(name: string): int { return root.store.count(name); }
    function append(name: string, entry: var): void { root.store.append(name, entry); }
    function prepend(name: string, entry: var): void { root.store.prepend(name, entry); }
    function push(name: string, entry: var, limit: int): void { root.store.push(name, entry, limit); }
    function find(name: string, id: var): var { return root.store.find(name, id); }
    function upsert(name: string, entry: var): void { root.store.upsert(name, entry); }
    function removeFrom(name: string, id: var): void { root.store.removeFrom(name, id); }
    function removeWhere(name: string, predicate: var): void { root.store.removeWhere(name, predicate); }
    function clearList(name: string): void { root.store.clearList(name); }

    // Nearest ancestor with a non-empty `pluginId`. Computed once at creation: the parent
    // chain of a widget does not change, and a binding that walks it would re-run on every
    // reparent for no reason.
    readonly property string __inferred: {
        let node = root.parent;
        let hops = 0;
        while (node && hops < 24) {
            if (node.pluginId !== undefined && node.pluginId !== "")
                return node.pluginId;
            node = node.parent;
            hops += 1;
        }
        return "";
    }
}
