pragma Singleton

// The event bus: how two plugins that have never heard of each other talk.
//
// A plugin cannot import another plugin - it is loaded by URL and its singletons are
// private - so anything cross-plugin has to go through core. This is that channel, and
// it is also how core tells plugins about things core must not name: the desktop
// publishes "desktop:filesDropped" without knowing that a drop shelf exists.
//
// Two kinds of topic:
//
//   emit(topic, payload)      fire and forget. Subscribers present now get it.
//   publish(topic, value)     also *retained*: the value stays readable afterwards, so a
//                             subscriber that starts later still sees the current state,
//                             and a binding can read it directly.
//
// Reading a retained value in a binding is the point of `retained()`: it returns a live
// per-topic object, so a badge can be written as
//
//     text: PluginBus.retained("dropover:count").value ?? 0
//
// and it updates without polling, without the reader knowing who publishes it.
//
//     // publisher
//     PluginBus.publish("dropover:count", DropShelfState.items.length)
//
//     // subscriber
//     PluginBusListener { topic: "wallpaper:changed"; onReceived: data => ... }
//
// Handlers registered with on() must be released with off(), or they keep a destroyed
// object's closure alive. PluginBusListener does that automatically and is what plugin
// code should use; on()/off() exist for imperative cases.

import QtQuick
import Quickshell
import qs.services

Singleton {
    id: root

    // topic -> [ { id, callback } ]
    property var __handlers: ({})
    property int __nextId: 1

    // topic -> QtObject { value, at, sequence }. Created on demand by retained() and by
    // publish(), and never destroyed: a retained topic is a small, long-lived cell, and
    // handing out an object whose lifetime is shorter than its bindings is how dangling
    // reads happen.
    property var __cells: ({})

    // Bumped on every publish so `topics` and `retainedTopics` re-evaluate.
    property int __revision: 0

    // ------------------------------------------------------------------ send

    // Fire and forget. Returns the number of handlers that ran, which is what a caller
    // wants when the question is "did anything pick this up".
    function emit(topic: string, payload: var): int {
        if (!topic)
            return 0;
        return root.__dispatch(topic, payload);
    }

    // Fire, and keep the value for later readers.
    function publish(topic: string, value: var): int {
        if (!topic)
            return 0;
        const cell = root.cell(topic);
        cell.value = value;
        cell.at = Date.now();
        cell.sequence += 1;
        root.__revision += 1;
        return root.__dispatch(topic, value);
    }

    function __dispatch(topic: string, payload: var): int {
        const targets = [];
        const exact = root.__handlers[topic];
        if (exact && exact.length > 0)
            targets.push(...exact);

        // Prefix subscriptions. Kept as a separate pass rather than expanding topics at
        // subscribe time, because a publisher is free to invent topic names at runtime
        // ("notifications:app:firefox") and a wildcard has to catch those too.
        for (const pattern of root.__wildcards) {
            if (pattern.length > 0 && topic.startsWith(pattern))
                targets.push(...(root.__handlers[`${pattern}*`] ?? []));
        }

        if (targets.length === 0)
            return 0;

        // Copied first: a handler is allowed to subscribe or unsubscribe while running.
        let ran = 0;
        for (const entry of targets.slice()) {
            try {
                entry.callback(payload, topic);
                ran += 1;
            } catch (error) {
                console.warn(`[bus] handler for "${topic}" threw:`, error.message ?? error);
            }
        }
        return ran;
    }

    // Prefixes of the "foo:*" subscriptions currently registered, without the star.
    // Maintained on subscribe/unsubscribe so dispatch never scans every key.
    property var __wildcards: []

    function __reindexWildcards(): void {
        root.__wildcards = Object.keys(root.__handlers).filter(key => key.endsWith("*")).map(key => key.slice(0, -1));
    }

    // --------------------------------------------------------------- receive

    // Returns a token; pass it to off(). A topic ending in ":*" or "*" matches by prefix,
    // so "wallpaper:*" hears "wallpaper:changed" and "wallpaper:loading".
    function on(topic: string, callback: var): int {
        if (!topic || typeof callback !== "function")
            return 0;
        const id = root.__nextId++;
        const handlers = root.__handlers;
        if (!handlers[topic]) {
            handlers[topic] = [];
            if (topic.endsWith("*"))
                root.__reindexWildcards();
        }
        handlers[topic].push({ id: id, callback: callback });
        return id;
    }

    // Fires at most once, then unsubscribes itself.
    function once(topic: string, callback: var): int {
        if (!topic || typeof callback !== "function")
            return 0;
        let token = 0;
        token = root.on(topic, (payload, name) => {
            root.off(token);
            callback(payload, name);
        });
        return token;
    }

    function off(token: int): bool {
        if (!token)
            return false;
        const handlers = root.__handlers;
        for (const topic of Object.keys(handlers)) {
            const index = handlers[topic].findIndex(entry => entry.id === token);
            if (index === -1)
                continue;
            handlers[topic].splice(index, 1);
            if (handlers[topic].length === 0) {
                delete handlers[topic];
                if (topic.endsWith("*"))
                    root.__reindexWildcards();
            }
            return true;
        }
        return false;
    }

    // ---------------------------------------------------------------- retained

    // The live cell for a topic, created empty if nothing has published yet. Bind to
    // `.value`, not to the cell: the cell's identity never changes, which is what makes
    // the binding cheap.
    function retained(topic: string): var {
        return root.cell(topic);
    }

    // The current value, or `fallback` when the topic has never been published.
    function value(topic: string, fallback: var): var {
        const cell = root.__cells[topic];
        return (cell && cell.sequence > 0) ? cell.value : fallback;
    }

    function has(topic: string): bool {
        const cell = root.__cells[topic];
        return !!cell && cell.sequence > 0;
    }

    // Drops a retained value without destroying the cell, so existing bindings keep
    // working and simply read undefined.
    function clear(topic: string): void {
        const cell = root.__cells[topic];
        if (!cell)
            return;
        cell.value = undefined;
        cell.sequence = 0;
        root.__revision += 1;
    }

    function cell(topic: string): var {
        let existing = root.__cells[topic];
        if (existing)
            return existing;
        existing = cellComponent.createObject(root, { topic: topic });
        root.__cells[topic] = existing;
        return existing;
    }

    // ----------------------------------------------------------- introspection

    // Every topic anyone is listening to or has published on - `plugins bus` prints this,
    // which is the difference between a bus you can debug and a bus you cannot.
    readonly property var topics: {
        root.__revision;
        const names = new Set(Object.keys(root.__handlers));
        for (const name of Object.keys(root.__cells))
            names.add(name);
        return Array.from(names).sort();
    }

    function describe(topic: string): var {
        const cell = root.__cells[topic];
        return {
            topic: topic,
            listeners: (root.__handlers[topic] ?? []).length,
            retained: !!cell && cell.sequence > 0,
            publishes: cell ? cell.sequence : 0,
            at: cell ? cell.at : 0,
            value: cell ? cell.value : undefined
        };
    }

    readonly property Component cellComponent: Component {
        QtObject {
            property string topic: ""
            property var value: undefined
            property real at: 0
            property int sequence: 0
        }
    }
}
