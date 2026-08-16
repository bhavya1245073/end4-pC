pragma Singleton

// Persistent per-plugin state that is not a *setting*.
//
// Settings are declared in a manifest, appear in the GUI and have defaults. Storage is
// for what a plugin accumulates while running: the city someone typed, a list of
// bookmarks, the last sync time, which tab was open. Nothing declares it, nobody sees it
// in the settings page, and it survives restarts.
//
//     readonly property var store: PluginStorage.of("weather")
//
//     store.set("city", "Tokyo")
//     store.get("city", "London")         // "Tokyo"
//     store.append("history", { at: Date.now(), temp: 21 })
//     store.list("history")               // [ { at, temp }, ... ]
//     store.removeWhere("history", entry => entry.temp < 0)
//
// Bindings work, and precisely: `store.values.city` re-evaluates when *this* plugin's
// storage changes and not when another plugin writes something.
//
// It lives in plugins.json beside settings and widget state, under "storage", so there
// is exactly one file, one watcher and one coalesced writer for everything a plugin
// remembers. That also sets the size expectation: this is for kilobytes of state, not a
// database. Anything larger belongs in a file of the plugin's own through PluginFs.

import QtQuick
import Quickshell
import qs.core

Singleton {
    id: root

    // pluginId -> store object. Long-lived: identity is what makes `store.values.x` a
    // cheap binding, so stores are created once and never destroyed.
    property var stores: ({})

    // True once plugins.json has been read. A plugin that *acts* on stored state rather
    // than binding to it has to wait for this, or it acts on empty storage once per
    // startup and overwrites what was there.
    readonly property bool loaded: PluginConfig.loaded

    function of(pluginId: string): var {
        let existing = root.stores[pluginId];
        if (existing)
            return existing;
        existing = storeComponent.createObject(root, { pluginId: pluginId });
        root.stores[pluginId] = existing;
        // Object.assign so the change is visible to anything iterating `stores`; the
        // individual store objects keep their identity.
        root.stores = Object.assign({}, root.stores);
        return existing;
    }

    // ------------------------------------------------------------------- sync
    //
    // PluginConfig.mutate copies on write down the path being changed, so an untouched
    // plugin's entry keeps its identity. Comparing identity per store is therefore enough
    // to push a change into exactly the store that changed.

    function __sync(): void {
        for (const pluginId of Object.keys(root.stores)) {
            const store = root.stores[pluginId];
            const stored = PluginConfig.data[pluginId]?.storage;
            if (store.__raw === stored)
                continue;
            store.__raw = stored;
            store.values = (typeof stored === "object" && stored !== null) ? stored : ({});
        }
    }

    // A binding, not a Connections: `data` is reassigned wholesale by mutate() and by the
    // file loading, and both have to reach the stores.
    readonly property var __watch: {
        PluginConfig.data;
        Qt.callLater(root.__sync);
        return null;
    }

    readonly property Component storeComponent: Component {
        QtObject {
            id: store

            property string pluginId: ""

            // The whole storage object for this plugin. Bind to a key of it
            // (`values.city`), not to the object, unless the whole thing is what changed.
            property var values: ({})

            // The exact object last seen in plugins.json, for identity comparison.
            property var __raw: undefined

            // --------------------------------------------------------- key/value

            function get(key: string, fallback: var): var {
                const current = store.values[key];
                return current === undefined ? fallback : current;
            }

            function has(key: string): bool {
                return store.values[key] !== undefined;
            }

            function set(key: string, value: var): void {
                store.__write(next => {
                    if (JSON.stringify(next[key]) === JSON.stringify(value))
                        return false;
                    next[key] = value;
                    return true;
                });
            }

            // Several keys at once, one write and one notification.
            function merge(patch: var): void {
                store.__write(next => {
                    let changed = false;
                    for (const key of Object.keys(patch ?? {})) {
                        if (JSON.stringify(next[key]) === JSON.stringify(patch[key]))
                            continue;
                        next[key] = patch[key];
                        changed = true;
                    }
                    return changed;
                });
            }

            function remove(key: string): void {
                store.__write(next => {
                    if (next[key] === undefined)
                        return false;
                    delete next[key];
                    return true;
                });
            }

            function keys(): var {
                return Object.keys(store.values).sort();
            }

            function clear(): void {
                store.__write(next => {
                    if (Object.keys(next).length === 0)
                        return false;
                    for (const key of Object.keys(next))
                        delete next[key];
                    return true;
                });
            }

            // Read-modify-write in one step, so two callers in the same frame cannot lose
            // each other's change:
            //
            //     store.update("count", current => (current ?? 0) + 1)
            function update(key: string, transform: var): void {
                store.__write(next => {
                    const updated = transform(next[key]);
                    if (JSON.stringify(next[key]) === JSON.stringify(updated))
                        return false;
                    next[key] = updated;
                    return true;
                });
            }

            // -------------------------------------------------------- collections
            //
            // A collection is an array under an ordinary key. `id` is whatever the caller
            // puts in an `id` field; entries without one can still be removed by predicate.

            function list(name: string): var {
                const value = store.values[name];
                return Array.isArray(value) ? value : [];
            }

            function count(name: string): int {
                return store.list(name).length;
            }

            function append(name: string, entry: var): void {
                store.__write(next => {
                    const list = Array.isArray(next[name]) ? next[name].slice() : [];
                    list.push(entry);
                    next[name] = list;
                    return true;
                });
            }

            function prepend(name: string, entry: var): void {
                store.__write(next => {
                    const list = Array.isArray(next[name]) ? next[name].slice() : [];
                    list.unshift(entry);
                    next[name] = list;
                    return true;
                });
            }

            // Appends, and drops the oldest entries past `limit`. For histories, which is
            // the collection everyone writes and nobody prunes.
            function push(name: string, entry: var, limit: int): void {
                store.__write(next => {
                    const list = Array.isArray(next[name]) ? next[name].slice() : [];
                    list.push(entry);
                    while (limit > 0 && list.length > limit)
                        list.shift();
                    next[name] = list;
                    return true;
                });
            }

            function find(name: string, id: var): var {
                return store.list(name).find(entry => entry?.id === id) ?? null;
            }

            // Replaces the entry with this id, or appends when there is none.
            function upsert(name: string, entry: var): void {
                store.__write(next => {
                    const list = Array.isArray(next[name]) ? next[name].slice() : [];
                    const index = list.findIndex(candidate => candidate?.id === entry?.id);
                    if (index === -1)
                        list.push(entry);
                    else if (JSON.stringify(list[index]) === JSON.stringify(entry))
                        return false;
                    else
                        list[index] = entry;
                    next[name] = list;
                    return true;
                });
            }

            function removeFrom(name: string, id: var): void {
                store.__write(next => {
                    const list = Array.isArray(next[name]) ? next[name] : [];
                    const kept = list.filter(entry => entry?.id !== id);
                    if (kept.length === list.length)
                        return false;
                    next[name] = kept;
                    return true;
                });
            }

            function removeWhere(name: string, predicate: var): void {
                store.__write(next => {
                    const list = Array.isArray(next[name]) ? next[name] : [];
                    const kept = list.filter(entry => !predicate(entry));
                    if (kept.length === list.length)
                        return false;
                    next[name] = kept;
                    return true;
                });
            }

            function clearList(name: string): void {
                store.__write(next => {
                    if (!Array.isArray(next[name]) || next[name].length === 0)
                        return false;
                    next[name] = [];
                    return true;
                });
            }

            // --------------------------------------------------------- internals

            // One write path, so every mutation goes through the same copy-on-write and
            // the same coalesced file write. `change` returns false to abort.
            function __write(change: var): void {
                if (!store.pluginId) {
                    console.warn("[storage] write with no pluginId - set PluginStore.pluginId");
                    return;
                }
                PluginConfig.mutate(store.pluginId, entry => {
                    const next = Object.assign({}, entry.storage);
                    if (change(next) === false)
                        return false;
                    entry.storage = next;
                    return true;
                });
            }
        }
    }
}
