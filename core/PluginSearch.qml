pragma Singleton

// Owns the live search providers plugins contribute, and aggregates their answers
// for the launcher.
//
// The launcher's own service (services/LauncherSearch.qml) reads `results` and calls
// `query()`; everything about running providers, ordering, capping and staleness lives
// here so that host has one small hook rather than provider logic spread through a
// 560-line binding.
//
// ## Why providers are asked imperatively
//
// `search()` may start a network request or a process, and a QML binding must be a
// pure function of its dependencies - side effects in one run at unpredictable times,
// re-run when anything they touched changes, and are impossible to reason about. So
// the query is *pushed* into providers from a signal handler, and their answers are
// *pulled* back out through the `results` property they own. That also gives async
// providers a free path: assigning `results` later is picked up by the same binding.

import QtQuick
import QtQml
import Quickshell
import qs.modules.common

Singleton {
    id: root

    // Set by the launcher. Assigning "" resets every provider.
    property string query: ""

    // Bumped whenever any provider assigns `results`, so the aggregate below has
    // something to depend on. A binding cannot depend on a property of an object
    // reached through Instantiator.objectAt(), because that indexed access is not a
    // tracked dependency - the count changing notifies, the children's properties do
    // not.
    property int __revision: 0

    // Sync answers, keyed by provider index. Kept separate from each provider's own
    // `results` so a provider that returns rows *and* fetches more does not have to
    // merge them itself.
    property var __syncResults: ({})

    readonly property int providerCount: providers.count

    // Every provider's rows, in provider order, each capped at its own `limit` and
    // tagged with which plugin produced it.
    readonly property var results: {
        void root.__revision;

        const blocks = [];
        for (let i = 0; i < providers.count; i++) {
            const provider = providers.objectAt(i)?.item;
            if (!provider)
                continue;

            const sync = root.__syncResults[i] ?? [];
            const async = Array.isArray(provider.results) ? provider.results : [];
            // Sync first: a provider that answers instantly and also fetches should show
            // the instant answer above the slow one.
            const rows = sync.concat(async).slice(0, Math.max(0, provider.limit ?? 10));
            if (rows.length === 0)
                continue;

            blocks.push({
                order: provider.order ?? 50,
                rows: rows.map(row => Object.assign({ pluginId: provider.pluginId }, row))
            });
        }

        return blocks
            .sort((a, b) => a.order - b.order)
            .reduce((all, block) => all.concat(block.rows), []);
    }

    // Called by the launcher on every (debounced) keystroke.
    function run(text: string): void {
        root.query = text ?? "";
    }

    onQueryChanged: {
        const sync = {};

        for (let i = 0; i < providers.count; i++) {
            const provider = providers.objectAt(i)?.item;
            if (!provider)
                continue;

            const prefix = provider.prefix ?? "";
            const applies = root.query.length >= (provider.minLength ?? 1)
                && (prefix === "" || root.query.startsWith(prefix));

            if (!applies) {
                // Clear stale rows, or a provider keeps answering a query the user has
                // already deleted.
                if ((provider.results?.length ?? 0) > 0)
                    provider.reset();
                continue;
            }

            // The prefix is a trigger, not part of the question.
            const text = prefix === "" ? root.query : root.query.slice(prefix.length).trim();

            try {
                const rows = provider.search(text);
                if (Array.isArray(rows) && rows.length > 0)
                    sync[i] = rows;
            } catch (e) {
                // One bad provider must not break the launcher for everything else.
                console.warn(`[plugins] search provider ${provider.pluginId} threw:`, e);
            }
        }

        root.__syncResults = sync;
        root.__revision++;
    }

    Instantiator {
        id: providers

        model: PluginRegistry.installedSearchProviders

        delegate: PluginLoader {
            id: loader

            required property var modelData

            pluginId: modelData.pluginId
            entry: PluginRegistry.isLoaded(modelData.pluginId) ? modelData.url : ""
            inject: ({
                pluginId: modelData.pluginId
            })

            // Manifest fields override the file's defaults, so a provider's trigger can be
            // read without loading its QML - and changed without editing it.
            onLoaded: {
                if (modelData.prefix !== undefined)
                    loader.item.prefix = modelData.prefix;
                if (modelData.minLength !== undefined)
                    loader.item.minLength = modelData.minLength;
                if (modelData.order !== undefined)
                    loader.item.order = modelData.order;
                if (modelData.limit !== undefined)
                    loader.item.limit = modelData.limit;

                // A provider that appears mid-query should answer the current one rather
                // than wait for the next keystroke.
                if (root.query !== "")
                    root.onQueryChanged();
            }

            Connections {
                target: loader.item
                enabled: loader.item !== null

                function onResultsChanged() {
                    root.__revision++;
                }
            }
        }
    }
}
