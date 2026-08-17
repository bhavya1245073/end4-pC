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
import "Memo.js" as Memo

Singleton {
    id: root

    // pluginId -> store object. Long-lived: identity is what makes `store.values.x` a
    // cheap binding, so stores are created once and never destroyed.
    //
    // The map lives in Memo.js rather than in a property here. A property would be read *and*
    // written by `of()`, and a plugin calling it from a binding - which is the documented way to
    // use it - would then be a dependency cycle: "Binding loop detected for property store", and
    // Qt drops the binding. See the note in core/Memo.js.

    // True once plugins.json has been read. A plugin that *acts* on stored state rather
    // than binding to it has to wait for this, or it acts on empty storage once per
    // startup and overwrites what was there.
    readonly property bool loaded: PluginConfig.loaded

    function of(pluginId: string): var {
        let existing = Memo.stores[pluginId];
        if (existing)
            return existing;
        existing = storeComponent.createObject(root, { pluginId: pluginId });
        Memo.stores[pluginId] = existing;
        return existing;
    }

    // ------------------------------------------------------------ collections
    //
    // A named list, as one object with the five verbs every list of favourites, pins, recents
    // and parked files needs:
    //
    //     readonly property var favourites: PluginStorage.collection("gif-picker", "favourites")
    //
    //     favourites.toggle({ id: url, url: url, at: Date.now() })
    //     favourites.has(url)
    //     favourites.list          // reactive: bind to it directly
    //     favourites.count
    //     favourites.clear()
    //
    // The store's own list functions do all of this already, and are the right tool when the
    // key is dynamic or the plugin wants several lists. This exists because `store.list(name)`
    // is a *function call* - QML re-runs it whenever anything in the store changes and cannot
    // tell that an unrelated key moved, so a favourites grid rebuilt on every write to any
    // key. `collection.list` is a property bound to one key, so a delegate reading it is
    // invalidated only when that key changes.
    //
    // Handles are cached per (plugin, key) and never destroyed: the identity is what makes
    // binding to `.list` cheap.

    function collection(pluginId: string, name: string): var {
        const key = `${pluginId}|${name}`;
        let existing = Memo.collections[key];
        if (existing)
            return existing;
        existing = collectionComponent.createObject(root, { pluginId: pluginId, name: name });
        Memo.collections[key] = existing;
        return existing;
    }

    readonly property Component collectionComponent: Component {
        QtObject {
            id: handle

            property string pluginId: ""
            property string name: ""

            readonly property var store: PluginStorage.of(handle.pluginId)

            // Bound to one key of one plugin's storage. This is the whole reason the handle
            // exists.
            readonly property var list: {
                const value = handle.store.values[handle.name];
                return Array.isArray(value) ? value : [];
            }

            readonly property int count: handle.list.length
            readonly property bool empty: handle.count === 0

            // How an entry is identified: its `id` field, or the value itself for a list of
            // plain strings. Both are common - favourites are objects, recent searches are
            // strings - and requiring objects would push the same three lines into every
            // plugin.
            function keyOf(item: var): var {
                if (item !== null && typeof item === "object")
                    return item.id ?? JSON.stringify(item);
                return item;
            }

            function has(idOrItem: var): bool {
                const key = handle.keyOf(idOrItem);
                return handle.list.some(entry => handle.keyOf(entry) === key);
            }

            function find(idOrItem: var): var {
                const key = handle.keyOf(idOrItem);
                return handle.list.find(entry => handle.keyOf(entry) === key) ?? null;
            }

            function indexOf(idOrItem: var): int {
                const key = handle.keyOf(idOrItem);
                return handle.list.findIndex(entry => handle.keyOf(entry) === key);
            }

            // Newest first, de-duplicated, capped. Prepends because every list like this is
            // read from the top.
            function add(item: var, limit: int): void {
                const key = handle.keyOf(item);
                handle.store.update(handle.name, current => {
                    const list = Array.isArray(current) ? current : [];
                    const kept = list.filter(entry => handle.keyOf(entry) !== key);
                    const next = [item].concat(kept);
                    const cap = limit ?? 0;
                    return cap > 0 ? next.slice(0, cap) : next;
                });
            }

            function append(item: var): void {
                const key = handle.keyOf(item);
                handle.store.update(handle.name, current => {
                    const list = Array.isArray(current) ? current : [];
                    return list.filter(entry => handle.keyOf(entry) !== key).concat([item]);
                });
            }

            function remove(idOrItem: var): void {
                const key = handle.keyOf(idOrItem);
                handle.store.update(handle.name, current => {
                    const list = Array.isArray(current) ? current : [];
                    return list.filter(entry => handle.keyOf(entry) !== key);
                });
            }

            // Returns whether the item is now in the list, so a caller can report "Added" or
            // "Removed" without asking again.
            function toggle(item: var): bool {
                const present = handle.has(item);
                if (present)
                    handle.remove(item);
                else
                    handle.add(item, 0);
                return !present;
            }

            // Replaces the matching entry, keeping its position - for editing an entry in
            // place, where add() would move it to the top.
            function update(item: var): void {
                const key = handle.keyOf(item);
                handle.store.update(handle.name, current => {
                    const list = Array.isArray(current) ? current : [];
                    const index = list.findIndex(entry => handle.keyOf(entry) === key);
                    if (index === -1)
                        return [item].concat(list);
                    const next = list.slice();
                    next[index] = item;
                    return next;
                });
            }

            function move(from: int, to: int): void {
                handle.store.update(handle.name, current => {
                    const list = Array.isArray(current) ? current.slice() : [];
                    if (from < 0 || from >= list.length || to < 0 || to >= list.length)
                        return list;
                    const [item] = list.splice(from, 1);
                    list.splice(to, 0, item);
                    return list;
                });
            }

            function removeWhere(predicate: var): void {
                handle.store.update(handle.name, current => {
                    const list = Array.isArray(current) ? current : [];
                    return list.filter(entry => !predicate(entry));
                });
            }

            function replaceAll(items: var): void {
                handle.store.set(handle.name, Array.isArray(items) ? items : []);
            }

            function clear(): void {
                handle.store.set(handle.name, []);
            }

            // Clears, and offers an undo. The destructive verb on a list of things the user
            // curated by hand should never be one-way.
            function clearWithUndo(label: string): void {
                const snapshot = handle.list.slice();
                if (snapshot.length === 0)
                    return;
                handle.clear();
                PluginHistory.recordWithToast({
                    label: label ?? qsTr("Cleared %1").arg(handle.name),
                    pluginId: handle.pluginId,
                    icon: "delete_sweep",
                    undo: () => handle.replaceAll(snapshot),
                    redo: () => handle.clear()
                });
            }
        }
    }

    // ------------------------------------------------------------------- sync
    //
    // PluginConfig.mutate copies on write down the path being changed, so an untouched
    // plugin's entry keeps its identity. Comparing identity per store is therefore enough
    // to push a change into exactly the store that changed.

    function __sync(): void {
        for (const pluginId of Object.keys(Memo.stores)) {
            const store = Memo.stores[pluginId];
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
