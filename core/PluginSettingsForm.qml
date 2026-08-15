// The GUI for one plugin's `settings` schema, generated from its manifest.

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root

    required property string pluginId

    readonly property var schema: PluginRegistry.get(root.pluginId)?.settings ?? []

    Layout.fillWidth: true
    spacing: 2
    visible: root.schema.length > 0

    Repeater {
        model: root.schema
        delegate: PluginSettingRow {
            // `index` is a required property of PluginSettingRow, so the
            // Repeater fills it in for us.
            required property var modelData
            pluginId: root.pluginId
            spec: modelData
            count: root.schema.length
        }
    }
}
