.pragma library

// Memo state for identity-stable derived lists.
//
// This is a JS library rather than properties on a singleton for one specific reason: a
// memo has to read the cache it also writes, and doing that with QML properties inside a
// binding is a dependency cycle. Qt detects it, reports "Binding loop detected", and
// drops a binding - so `PluginRegistry.panels` and `QuickToggleRegistry.all` both
// silently stopped updating the first time this was written with `property var` caches.
//
// Variables in a `.pragma library` script are plain JS with no property system attached,
// so reading and writing them during a binding is invisible and safe. The library is
// shared by every file that imports it, which is what makes the cache global.

// Handle caches for stores and collections.
//
// These are plain JS variables, not properties on the singleton, for the same reason the memo
// caches below are: `PluginStorage.of(id)` has to read the cache it also writes, and a QML
// property read-then-written during a binding evaluation is a dependency cycle. Written the
// obvious way - `property var stores` reassigned inside `of()` - every plugin that did the
// natural thing
//
//     readonly property var store: PluginStorage.of("tasks")
//
// got "Binding loop detected for property store" and Qt dropped the binding, so the plugin's
// state silently stopped updating.
var stores = ({});
var collections = ({});
var scopes = ({});

var store = ({});
var signatures = ({});
var indexStore = ({});
var indexKeyed = ({});

var hits = 0;
var misses = 0;

// Returns the previous array when the new one is equal, so consumers that compare by
// identity - which is all of them - do not see a change that was not one.
function stable(key, computed) {
    var signature = JSON.stringify(computed);
    if (signatures[key] === signature) {
        hits++;
        return store[key];
    }
    signatures[key] = signature;
    store[key] = computed;
    misses++;
    return computed;
}

// Cheaper comparison for arrays of plain strings.
function ids(key, computed) {
    var signature = computed.join("\u0000");
    if (signatures[key] === signature) {
        hits++;
        return store[key];
    }
    signatures[key] = signature;
    store[key] = computed;
    misses++;
    return computed;
}

// id -> entry map for a list, so a per-id lookup is not a scan. Keyed on the list's
// identity, which - given `stable` above - changes only when the list really changed.
function index(key, entries) {
    if (indexKeyed[key] === entries)
        return indexStore[key];
    var map = ({});
    for (var i = 0; i < entries.length; i++)
        map[entries[i].id] = entries[i];
    indexKeyed[key] = entries;
    indexStore[key] = map;
    return map;
}

// Generic keyed cache, for values that are not lists. `bucket` is invalidated wholesale
// when `key` changes.
var buckets = ({});
var bucketKeys = ({});

function cached(bucket, key, slot, compute) {
    if (bucketKeys[bucket] !== key) {
        bucketKeys[bucket] = key;
        buckets[bucket] = ({});
    }
    var hit = buckets[bucket][slot];
    if (hit !== undefined) {
        hits++;
        return hit;
    }
    var computed = compute();
    buckets[bucket][slot] = computed;
    misses++;
    return computed;
}

function stats() {
    return { hits: hits, misses: misses };
}
