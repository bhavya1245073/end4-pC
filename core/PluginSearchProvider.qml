// A live search provider for the launcher.
//
// Unlike `launcherActions`, which are static entries matched by name, a provider is
// asked about every query and answers with whatever it likes - so this is how you
// build a calculator, a unit converter, a dictionary, an emoji picker, a note search
// or a bookmark search.
//
//     // plugins/units/UnitsProvider.qml
//     import qs.core
//
//     PluginSearchProvider {
//         prefix: ""                       // "" = every query; ">" = only after ">"
//         minLength: 3
//
//         function search(query: string): var {
//             const m = query.match(/^([\d.]+)\s*(km|mi)$/i);
//             if (!m) return [];
//             const km = m[2].toLowerCase() === "mi" ? m[1] * 1.609 : m[1] / 1.609;
//             return [{
//                 name: `${km.toFixed(2)} ${m[2].toLowerCase() === "mi" ? "km" : "mi"}`,
//                 subtitle: "Unit conversion",
//                 icon: "straighten",
//                 onActivate: () => PluginUtils.copy(km.toFixed(2))
//             }];
//         }
//     }
//
// Return a list of plain objects. Fields, all optional but `name`:
//
//     name        the main line
//     subtitle    the dim second line (shown where a result's type usually is)
//     icon        a Material Symbol name, or an app icon name with iconIsApp: true
//     onActivate  called when the user picks it. Omit for a result that does nothing
//     order       lower sorts earlier among providers (default 50)
//
// ## Async results
//
// Return `[]` now and assign `results` when the answer arrives. The launcher watches
// that property, so a late assignment shows up without another keystroke:
//
//     function search(query: string): var {
//         PluginUtils.fetchJson(`https://api.example.com/?q=${encodeURIComponent(query)}`, res => {
//             if (res.ok && query === lastQuery)      // guard: answers can arrive out of order
//                 results = res.data.items.map(...)
//         });
//         return [];                                  // nothing yet
//     }
//
// ## Rules
//
// - **Return fast.** `search()` runs on the UI thread on every keystroke (debounced
//   200ms). Do file or network work asynchronously, never in the function body.
// - **Return `[]`, not null**, when you have no answer for a query.
// - **Do not do work you will throw away.** Check the cheap condition first: a regex
//   that cannot match, a prefix that is absent, a query below `minLength`.

import QtQuick
import Quickshell

QtObject {
    id: root

    // Set by the loader from the manifest; do not assign it.
    property string pluginId: ""

    // Only consulted when the query starts with this. Empty means every query, which
    // is right for a provider that can tell from the query itself whether it applies
    // (a calculator, a unit converter) and wrong for one that would otherwise answer
    // everything (a web lookup).
    property string prefix: ""

    // Below this many characters the provider is not called at all. Guards against a
    // provider answering "a" with two thousand rows.
    property int minLength: 1

    // Sort position of this provider's results as a block, relative to other
    // providers. Results keep their own relative order within the block.
    property int order: 50

    // Cap on how many results are taken from this provider, so one chatty provider
    // cannot push everything else off the list.
    property int limit: 10

    // Assign for async answers. Reset it to [] when a new query starts, or a stale
    // answer will be shown against the new query.
    property var results: []

    // Override this. The default returns nothing, which makes a provider that forgot
    // to implement it silently inert rather than an error on every keystroke.
    function search(query: string): var {
        return [];
    }

    // Called when the launcher closes or the query is cleared. Override to cancel
    // in-flight work.
    function reset(): void {
        root.results = [];
    }
}
