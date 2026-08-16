pragma Singleton
pragma ComponentBehavior: Bound

// Per-plugin settings store.
//
// Lives in ~/.config/illogical-impulse/plugins.json, deliberately separate from
// the shell's own config.json: plugins come and go, and a JsonAdapter would drop
// the keys of any plugin that happens to not be installed right now.
//
// File shape:
//   {
//     "clock": {
//       "enabled": true,
//       "settings": { "format": "HH:mm" },
//       "widgets": { "deskClock": { "enable": true, "x": 120, "y": 80 } }
//     },
//     "weather": { "enabled": false }
//   }
//
// Values missing from the file fall back to the `default` declared by the
// plugin's manifest, so a fresh install needs no file at all.
//
// ## Why `of()` hands back an object with real properties
//
// The obvious implementation is one big `effective` binding: a map of every plugin's
// settings with defaults merged in, and `of(id)` indexing into it. It is also
// quadratic in the worst way. `effective` depends on `data`, so *any* write - another
// plugin's setting, a plugin being enabled, a desktop widget being dragged one pixel -
// rebuilt the settings of all twenty plugins, coercing every declared key, and handed
// every plugin a brand new object. A new object identity means `settings` changed,
// which means every binding on `settings.anything` re-evaluated, in every plugin, on
// every write. Dragging a widget did that at pointer rate.
//
// Instead each plugin gets a long-lived object whose properties are generated from its
// manifest schema, and writes assign into it. Assigning a typed QML property that
// already holds that value emits nothing, so a write now notifies exactly the bindings
// that read the key that actually changed - usually one - and identity never changes.

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

Singleton {
    id: root

    readonly property string path: `${Directories.shellConfig}/plugins.json`

    // Raw contents of plugins.json.
    property var data: ({})

    // True once plugins.json has been read, or found to be absent or unreadable.
    // Written only from this file.
    //
    // FileView loads asynchronously, so until this turns true every setting reads
    // as its manifest default. Binding to a value is unaffected - the binding
    // simply updates when the file lands - but a plugin that *acts* on its stored
    // state has to wait, or it will act on the defaults once at every startup.
    // See plugins/material-you-colors for the pattern.
    property bool loaded: false

    // pluginId -> settings object. Identity is stable for the lifetime of the plugin,
    // so `readonly property var settings: PluginConfig.of(id)` binds once.
    property var bags: ({})

    // pluginId -> the key list its bag was built for, so we can tell when a bag has
    // to be rebuilt rather than merely updated.
    property var bagKeys: ({})

    // ------------------------------------------------------------------ access

    // All settings of one plugin, defaults included. The returned object has one
    // property per setting, so `settings.format` is a precise dependency:
    //
    //     readonly property var settings: PluginConfig.of("clock")
    //     text: settings.format
    // Returned instead of null for a plugin with no bag yet, so that a widget reading
    // `settings.something` during startup gets undefined rather than a TypeError.
    readonly property QtObject emptyBag: QtObject {}

    function of(pluginId: string): var {
        return root.bags[pluginId] ?? root.emptyBag;
    }

    function value(pluginId: string, key: string): var {
        const bag = root.bags[pluginId];
        return bag ? bag[key] : undefined;
    }

    function set(pluginId: string, key: string, newValue: var) {
        root.mutate(pluginId, entry => {
            entry.settings = Object.assign({}, entry.settings);
            if (entry.settings[key] === newValue)
                return false;
            entry.settings[key] = newValue;
            return true;
        });
    }

    function reset(pluginId: string, key: string) {
        root.mutate(pluginId, entry => {
            if (entry.settings?.[key] === undefined)
                return false;
            entry.settings = Object.assign({}, entry.settings);
            delete entry.settings[key];
            return true;
        });
    }

    function resetAll(pluginId: string) {
        root.mutate(pluginId, entry => {
            if (entry.settings === undefined)
                return false;
            delete entry.settings;
            return true;
        });
    }

    function setEnabled(pluginId: string, enabled: bool) {
        root.mutate(pluginId, entry => {
            if (entry.enabled === enabled)
                return false;
            entry.enabled = enabled;
            return true;
        });
    }

    // ---------------------------------------------------------- widget state
    //
    // Desktop widgets need a home for their own toggle and drag position, which
    // is per *widget*, not per plugin. Kept beside the settings under
    // `"widgets": { "<widgetId>": { "enable": true, "x": 0, "y": 0 } }`.

    function widgetState(pluginId: string, widgetId: string): var {
        return root.data[pluginId]?.widgets?.[widgetId] ?? ({});
    }

    function widgetValue(pluginId: string, widgetId: string, key: string, fallback: var): var {
        const stored = root.widgetState(pluginId, widgetId)[key];
        return stored === undefined ? fallback : stored;
    }

    function setWidgetValue(pluginId: string, widgetId: string, key: string, newValue: var) {
        root.mutate(pluginId, entry => {
            const widgets = Object.assign({}, entry.widgets);
            const state = Object.assign({}, widgets[widgetId]);
            if (state[key] === newValue)
                return false;
            state[key] = newValue;
            widgets[widgetId] = state;
            entry.widgets = widgets;
            return true;
        });
    }

    function widgetEnabled(pluginId: string, widgetId: string, fallback: bool): bool {
        return root.widgetValue(pluginId, widgetId, "enable", fallback) === true;
    }

    function setWidgetEnabled(pluginId: string, widgetId: string, enabled: bool) {
        root.setWidgetValue(pluginId, widgetId, "enable", enabled);
    }

    // -------------------------------------------------------------- internals

    // Copy-on-write down the path being changed, and nothing else. `data` needs a new
    // identity to notify, but the nineteen plugins not being written keep theirs -
    // which is what lets the bag sync below skip them by identity instead of
    // re-coercing every key in the file. `change` returns false to abort the write.
    function mutate(pluginId: string, change: var) {
        const next = Object.assign({}, root.data);
        const entry = Object.assign({}, next[pluginId]);
        if (change(entry) === false)
            return;
        next[pluginId] = entry;
        root.data = next;
        writeTimer.restart();
    }

    // Which QML type to give a declared setting. A typed property is not a nicety: QML
    // compares the old and new value of a typed property and stays silent when they are
    // equal, and that is what keeps an unrelated write from waking up every binding.
    function qmlTypeOf(spec: var): string {
        switch (spec.type) {
        case "bool":
            return "bool";
        case "int":
            return "int";
        case "real":
            return "real";
        case "color":
            return "color";
        case "enum":
        case "string":
            return "string";
        default:
            return "var";
        }
    }

    // A setting key becomes a QML property name, so it has to be a plain identifier and
    // must not collide with what QtObject already has. A manifest that asks for
    // something else is ignored rather than taking the whole bag down with a syntax
    // error at createQmlObject time.
    readonly property var reservedKeys: ["objectName", "parent", "children", "data"]

    function validKey(key: string): bool {
        return /^[a-z_][A-Za-z0-9_]*$/.test(key) && !root.reservedKeys.includes(key);
    }

    function keysFor(plugin: var, stored: var): var {
        const keys = [];
        const seen = ({});
        for (const spec of plugin.settings) {
            if (!spec || !spec.key || seen[spec.key])
                continue;
            seen[spec.key] = true;
            if (!root.validKey(spec.key)) {
                console.warn(`[plugins] ${plugin.id}: setting key "${spec.key}" is not a usable property name, ignoring`);
                continue;
            }
            keys.push({
                key: spec.key,
                type: root.qmlTypeOf(spec),
                spec: spec
            });
        }
        // Keys the manifest never declared are still exposed, so a plugin can keep
        // runtime state here without schema churn.
        for (const key in stored) {
            if (seen[key] || !root.validKey(key))
                continue;
            seen[key] = true;
            keys.push({
                key: key,
                type: "var",
                spec: null
            });
        }
        return keys;
    }

    function buildBag(pluginId: string, keys: var): var {
        const lines = ["import QtQuick", "QtObject {"];
        for (const entry of keys)
            lines.push(`    property ${entry.type} ${entry.key}`);
        lines.push("}");
        return Qt.createQmlObject(lines.join("\n"), root, `PluginSettings_${pluginId}`);
    }

    // Brings every plugin's bag in line with `data`. Cheap by construction: a plugin
    // whose stored object is identical by identity to last time is skipped outright,
    // and for the rest, assigning an unchanged typed property notifies nobody.
    property var lastStored: ({})

    function syncBags() {
        let bags = root.bags;
        let created = false;

        for (const plugin of PluginRegistry.all) {
            const stored = root.data[plugin.id]?.settings ?? ({});
            let bag = bags[plugin.id];

            if (bag && root.lastStored[plugin.id] === stored)
                continue;
            root.lastStored[plugin.id] = stored;

            const keys = root.keysFor(plugin, stored);

            // Rebuild only when the shape changed - a new undeclared key appearing, or
            // the plugin's schema being reloaded. This is the one case where a plugin's
            // `settings` identity changes, and it is rare.
            const signature = keys.map(entry => `${entry.type} ${entry.key}`).join(",");
            if (!bag || root.bagKeys[plugin.id] !== signature) {
                if (bag)
                    bag.destroy();
                if (!created) {
                    bags = Object.assign({}, bags);
                    created = true;
                }
                bag = root.buildBag(plugin.id, keys);
                bags[plugin.id] = bag;
                root.bagKeys[plugin.id] = signature;
            }

            for (const entry of keys) {
                const raw = stored[entry.key];
                bag[entry.key] = entry.spec
                    ? (raw === undefined ? root.defaultOf(entry.spec) : root.coerce(entry.spec, raw))
                    : raw;
            }
        }

        // Drop bags of plugins that went away.
        for (const id in bags) {
            if (PluginRegistry.plugins[id])
                continue;
            if (!created) {
                bags = Object.assign({}, bags);
                created = true;
            }
            bags[id].destroy();
            delete bags[id];
            delete root.bagKeys[id];
            delete root.lastStored[id];
        }

        if (created)
            root.bags = bags;
    }

    onDataChanged: root.syncBags()

    Connections {
        target: PluginRegistry
        function onAllChanged() {
            root.syncBags();
        }
    }

    function defaultOf(spec: var): var {
        if (spec.default !== undefined)
            return spec.default;
        switch (spec.type) {
        case "bool":
            return false;
        case "int":
        case "real":
            return spec.min ?? 0;
        case "enum":
            return spec.options?.[0]?.value ?? "";
        default:
            return "";
        }
    }

    function coerce(spec: var, value: var): var {
        switch (spec.type) {
        case "bool":
            return value === true;
        case "int":
            return isNaN(parseInt(value)) ? root.defaultOf(spec) : parseInt(value);
        case "real":
            return isNaN(parseFloat(value)) ? root.defaultOf(spec) : parseFloat(value);
        case "enum":
            return (spec.options ?? []).some(option => option.value === value) ? value : root.defaultOf(spec);
        case "string":
        case "color":
            return String(value);
        default:
            return value;
        }
    }

    function load() {
        root.loaded = true;

        const raw = configFile.text();
        if (raw.trim().length === 0) {
            root.data = ({});
            return;
        }
        try {
            const parsed = JSON.parse(raw);
            root.data = (typeof parsed === "object" && parsed !== null) ? parsed : ({});
        } catch (error) {
            console.warn(`[plugins] ${root.path} is not valid JSON, ignoring: ${error.message}`);
        }
    }

    function save() {
        // Ignore the fileChanged our own write is about to cause, otherwise a
        // reload can land on top of an edit made in the meantime.
        root.selfWriting = true;
        selfWriteCooldown.restart();
        configFile.setText(JSON.stringify(root.data, null, 4) + "\n");
    }

    property bool selfWriting: false

    Timer {
        id: selfWriteCooldown
        interval: 400
        onTriggered: root.selfWriting = false
    }

    // Coalesces a burst of writes into one serialise-and-write. Dragging a widget
    // produces one call per pointer move, and JSON.stringify of the whole file per
    // move is not free.
    Timer {
        id: writeTimer
        interval: 150
        onTriggered: root.save()
    }

    FileView {
        id: configFile
        path: root.path
        printErrors: false
        watchChanges: true
        onFileChanged: {
            if (root.selfWriting)
                return;
            this.reload();
        }
        onLoaded: root.load()
        onLoadFailed: {
            // No file yet is the normal state on a fresh install: every plugin
            // starts on its manifest defaults.
            root.loaded = true;
            root.data = ({});
        }
    }
}
