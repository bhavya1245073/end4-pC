pragma Singleton
pragma ComponentBehavior: Bound

// Identity-stable derived lists.
//
// QML decides whether to re-run a binding, rebuild a Repeater or recreate an
// Instantiator's delegates by comparing the **identity** of a JS array, not its
// contents. A derived list therefore has a nasty property: it is recomputed whenever any
// of its dependencies changes, and the recomputation allocates a new array even when the
// result is character-for-character what it was before - and every consumer treats that
// as "everything changed".
//
// This is what made unrelated things expensive in this shell. `QuickToggleRegistry.all`
// depends on the plugin registry, so enabling a *bar* plugin produced a brand new
// quick-toggle array, which rebuilt all seventeen quick toggles - none of which had
// changed. Same story for the bar's widget table and the desktop widget list.
//
// Wrapping the result fixes it at the source: if the new value is equal to the last one,
// the last one is handed back, identity intact, and no consumer re-runs.
//
//     readonly property var all: Stable.list("bar.all", (() => {
//         ...compute...
//     })())
//
// Keys are global, so name them after the property: "<registry>.<property>".
//
// The state lives in Memo.js, not in properties here, because a memo reads the cache it
// also writes and doing that with QML properties inside a binding is a dependency cycle.
// See the file.

import QtQml
import "Memo.js" as Memo

QtObject {
    id: root

    function list(key: string, computed: var): var {
        return Memo.stable(key, computed);
    }

    // For lists of plain strings, where a join is cheaper than a serialise.
    function ids(key: string, computed: var): var {
        return Memo.ids(key, computed);
    }

    // id -> entry map for a list, so a per-id lookup is not a scan.
    function index(key: string, entries: var): var {
        return Memo.index(key, entries);
    }

    // Cache effectiveness, for the profiler. Misses climbing while nothing is being
    // installed means a derived list is churning and rebuilding its consumers.
    function hits(): int {
        return Memo.stats().hits;
    }

    function misses(): int {
        return Memo.stats().misses;
    }
}
