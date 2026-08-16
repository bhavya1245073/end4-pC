pragma Singleton
pragma ComponentBehavior: Bound

// Identity-stable derived lists.
//
// QML decides whether to re-run a binding, rebuild a Repeater or recreate an
// Instantiator's delegates by comparing the *identity* of a JS array, not its contents.
// A derived list therefore has a nasty property: it is recomputed whenever any of its
// dependencies changes, and the recomputation allocates a new array even when the
// result is character-for-character what it was before - and every consumer treats
// that as "everything changed".
//
// This is what made unrelated things expensive in this shell. `QuickToggleRegistry.all`
// depends on the plugin registry, so enabling a *bar* plugin produced a brand new
// quick-toggle array, which rebuilt all seventeen quick toggles - none of which had
// changed. Same story for the bar's widget table and the desktop widget list.
//
// Wrapping the result in `Stable.list()` fixes it at the source: if the new value is
// equal to the last one, the last one is handed back, identity intact, and no consumer
// re-runs. The comparison is a serialise of lists that hold a couple of dozen small
// objects, which costs far less than one avoided delegate rebuild.
//
//     readonly property var all: Stable.list("bar.all", (() => {
//         ...compute...
//     })())
//
// Keys are global, so name them after the property: "<registry>.<property>".

import QtQml

QtObject {
    id: root

    property var store: ({})
    property var signatures: ({})

    // Hits and misses, for the benchmark harness.
    property int hits: 0
    property int misses: 0

    function list(key: string, computed: var): var {
        const signature = JSON.stringify(computed);
        if (root.signatures[key] === signature) {
            root.hits++;
            return root.store[key];
        }
        root.signatures[key] = signature;
        root.store[key] = computed;
        root.misses++;
        return computed;
    }

    // For lists of plain strings, where a join is cheaper than a serialise.
    function ids(key: string, computed: var): var {
        const signature = computed.join("\u0000");
        if (root.signatures[key] === signature) {
            root.hits++;
            return root.store[key];
        }
        root.signatures[key] = signature;
        root.store[key] = computed;
        root.misses++;
        return computed;
    }

    // id -> entry map for a list, so a per-id lookup is not a scan. Rebuilt only when
    // the list's identity changes, which - given the above - means only when it really
    // changed.
    property var indexStore: ({})
    property var indexOf: ({})

    function index(key: string, entries: var): var {
        if (root.indexOf[key] === entries)
            return root.indexStore[key];
        const map = ({});
        for (const entry of entries)
            map[entry.id] = entry;
        root.indexOf[key] = entries;
        root.indexStore[key] = map;
        return map;
    }
}
