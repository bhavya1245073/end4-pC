// The GUI for one plugin's `settings` schema, generated from its manifest.
//
// A setting may carry an optional `"group"`. Entries that share one are rendered
// as a titled block, in the order the groups first appear; entries without one
// come first, ungrouped. Twenty rows in a single column is a wall to read, and a
// plugin should be able to say "these four are about Konsole" without shipping
// QML for it.

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root

    required property string pluginId

    readonly property var schema: PluginRegistry.get(root.pluginId)?.settings ?? []

    // [{ title: "" | "Konsole", entries: [spec, ...] }, ...]
    readonly property var groups: {
        const order = [];
        const byTitle = ({});

        for (const spec of root.schema) {
            const title = spec.group ?? "";
            if (byTitle[title] === undefined) {
                byTitle[title] = [];
                order.push(title);
            }
            byTitle[title].push(spec);
        }

        // The unnamed group is the plugin's "main" settings, so it leads.
        order.sort((a, b) => (a === "" ? -1 : b === "" ? 1 : 0));

        return order.map(title => ({
                    title: title,
                    entries: byTitle[title]
                }));
    }

    Layout.fillWidth: true
    spacing: 8
    visible: root.schema.length > 0

    Repeater {
        model: root.groups

        delegate: ContentSubsection {
            id: group

            required property var modelData

            readonly property var entries: group.modelData.entries

            title: group.modelData.title

            Repeater {
                model: group.entries
                delegate: PluginSettingRow {
                    // `index` is a required property of PluginSettingRow, so the
                    // Repeater fills it in for us.
                    required property var modelData
                    pluginId: root.pluginId
                    spec: modelData
                    // Rounds the ends of this group's block, not the whole form's.
                    count: group.entries.length
                }
            }
        }
    }
}
