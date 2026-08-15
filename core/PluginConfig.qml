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

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

Singleton {
    id: root

    readonly property string path: `${Directories.shellConfig}/plugins.json`

    // Raw contents of plugins.json.
    property var data: ({})

    // pluginId -> { key: value } with manifest defaults filled in.
    readonly property var effective: {
        const merged = ({});
        for (const plugin of PluginRegistry.all) {
            const stored = root.data[plugin.id]?.settings ?? ({});
            const values = ({});
            for (const spec of plugin.settings) {
                if (!spec || !spec.key)
                    continue;
                values[spec.key] = stored[spec.key] === undefined
                    ? root.defaultOf(spec)
                    : root.coerce(spec, stored[spec.key]);
            }
            // Keys the manifest never declared are still exposed, so a plugin
            // can keep runtime state here without schema churn.
            for (const key in stored) {
                if (values[key] === undefined)
                    values[key] = stored[key];
            }
            merged[plugin.id] = values;
        }
        return merged;
    }

    // ------------------------------------------------------------------ access

    // All settings of one plugin, defaults included. Rebinds on change, so
    // plugins can do: `readonly property var settings: PluginConfig.of("clock")`
    function of(pluginId: string): var {
        return root.effective[pluginId] ?? ({});
    }

    function value(pluginId: string, key: string): var {
        return root.effective[pluginId]?.[key];
    }

    function set(pluginId: string, key: string, newValue: var) {
        const data = root.clone();
        data[pluginId] = data[pluginId] ?? ({});
        data[pluginId].settings = data[pluginId].settings ?? ({});
        if (data[pluginId].settings[key] === newValue)
            return;
        data[pluginId].settings[key] = newValue;
        root.data = data;
        writeTimer.restart();
    }

    function reset(pluginId: string, key: string) {
        const data = root.clone();
        if (data[pluginId]?.settings?.[key] === undefined)
            return;
        delete data[pluginId].settings[key];
        root.data = data;
        writeTimer.restart();
    }

    function resetAll(pluginId: string) {
        const data = root.clone();
        if (!data[pluginId])
            return;
        delete data[pluginId].settings;
        root.data = data;
        writeTimer.restart();
    }

    function setEnabled(pluginId: string, enabled: bool) {
        const data = root.clone();
        data[pluginId] = data[pluginId] ?? ({});
        if (data[pluginId].enabled === enabled)
            return;
        data[pluginId].enabled = enabled;
        root.data = data;
        writeTimer.restart();
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
        const data = root.clone();
        data[pluginId] = data[pluginId] ?? ({});
        data[pluginId].widgets = data[pluginId].widgets ?? ({});
        data[pluginId].widgets[widgetId] = data[pluginId].widgets[widgetId] ?? ({});
        if (data[pluginId].widgets[widgetId][key] === newValue)
            return;
        data[pluginId].widgets[widgetId][key] = newValue;
        root.data = data;
        writeTimer.restart();
    }

    function widgetEnabled(pluginId: string, widgetId: string, fallback: bool): bool {
        return root.widgetValue(pluginId, widgetId, "enable", fallback) === true;
    }

    function setWidgetEnabled(pluginId: string, widgetId: string, enabled: bool) {
        root.setWidgetValue(pluginId, widgetId, "enable", enabled);
    }

    // -------------------------------------------------------------- internals

    function clone(): var {
        const copy = ({});
        for (const id in root.data) {
            copy[id] = Object.assign({}, root.data[id]);
            if (copy[id].settings)
                copy[id].settings = Object.assign({}, copy[id].settings);
            if (copy[id].widgets) {
                const widgets = ({});
                for (const widgetId in copy[id].widgets)
                    widgets[widgetId] = Object.assign({}, copy[id].widgets[widgetId]);
                copy[id].widgets = widgets;
            }
        }
        return copy;
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
        onLoadFailed: root.data = ({})
    }
}
