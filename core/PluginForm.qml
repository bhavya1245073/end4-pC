// A form over values a plugin owns, using the same controls as the settings GUI.
//
//     PluginStore { id: store }
//
//     PluginForm {
//         fields: [
//             { key: "city", label: "City", type: "string", placeholder: "London" },
//             { key: "units", label: "Units", type: "enum", options: [
//                 { value: "metric", label: "°C" }, { value: "imperial", label: "°F" } ] },
//             { key: "refresh", label: "Refresh every", type: "int", min: 1, max: 120 },
//             { key: "alerts", label: "Severe weather alerts", type: "bool" }
//         ]
//         values: store.values
//         onFieldChanged: (key, value) => store.set(key, value)
//     }
//
// The field descriptors are exactly the manifest `settings` schema - same types, same keys, same
// `min`/`max`/`options`/`description` - so a plugin author learns one shape. The difference is
// where the value lives: a manifest setting goes to the settings GUI, a form field goes wherever
// the plugin puts it.
//
// Without a handler the form writes into `values` if it is a PluginStore, which covers the
// common case of a form editing persistent plugin state:
//
//     PluginForm { fields: [...]; store: myStore }

import QtQuick
import QtQuick.Layouts
import qs.core
import qs.modules.common

ColumnLayout {
    id: root

    // [{ key, label, type, description, icon, min, max, step, options, placeholder }]
    property var fields: []

    // Current values, keyed by field key. Read-only as far as the form is concerned.
    property var values: ({})

    // Optional: a PluginStore (or anything with set(key, value)) to write into automatically.
    property var store: null

    // Which plugin the rows belong to, for the settings-row fallback path. Inferred from the
    // store when there is one.
    property string pluginId: root.store?.pluginId ?? ""

    signal fieldChanged(string key, var value)

    spacing: 2

    function valueOf(key: string): var {
        if (root.values && root.values[key] !== undefined)
            return root.values[key];
        const field = (root.fields ?? []).find(candidate => candidate.key === key);
        return field?.default;
    }

    function commit(key: string, value: var): void {
        // Emitted first, so a handler can veto by writing something else afterwards, and so a
        // form with both a store and a handler notifies in a predictable order.
        root.fieldChanged(key, value);
        if (root.store && typeof root.store.set === "function")
            root.store.set(key, value);
    }

    Repeater {
        model: root.fields

        delegate: PluginSettingRow {
            required property var modelData
            required property int index

            Layout.fillWidth: true
            pluginId: root.pluginId
            spec: modelData
            index: index
            count: root.fields.length

            // The row renders a control for `spec.type` and calls write() - the value itself
            // comes from and goes to the form, not to plugins.json.
            read: () => root.valueOf(modelData.key)
            write: value => root.commit(modelData.key, value)
        }
    }
}
