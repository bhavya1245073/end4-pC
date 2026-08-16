// Renders the settings sections plugins have injected into one page.
//
// Drop this at the end of a core settings page:
//
//     PluginSections { page: "Interface" }
//
// and every active plugin that declared
//
//     "settingsSections": [{ "page": "Interface", "entry": "DockSettings.qml", "order": 30 }]
//
// appears there, in `order`. Switch the plugin off and its section goes with it,
// which is the whole point: a hardcoded settings section for a plugin that is not
// loaded is a row of controls wired to nothing.
//
// Each entry is a ContentSection (or anything that sizes itself), loaded lazily.
//
// The model is every *installed* section, not the active ones: a Repeater over a
// reassigned JS array rebuilds all of its delegates, so an active-derived model made
// toggling one plugin rebuild every section on the page. The enabled state is on the
// Loader's `active` instead, which both collapses the section to nothing and costs a
// boolean.

import QtQuick
import QtQuick.Layouts
import qs.modules.common

ColumnLayout {
    id: root

    // Host page name, matched against the manifest's `page`, case-insensitively.
    required property string page

    Layout.fillWidth: true
    spacing: 20

    Repeater {
        model: PluginRegistry.sectionsFor(root.page)

        delegate: Loader {
            required property var modelData

            Layout.fillWidth: true

            // Unloaded, not merely hidden, when the plugin is off: the controls would
            // be wired to a plugin that is not running.
            //
            // `isLoaded`, not `isActive`, and asynchronous: this section is on the very
            // page the user just clicked the switch on, so loading it synchronously in
            // the same turn is what made the switch appear to stick.
            active: PluginRegistry.isLoaded(modelData.pluginId)
            asynchronous: true

            // A section whose file is missing should not take the page down with it.
            source: active ? (modelData.url ?? "") : ""

            onStatusChanged: {
                if (status === Loader.Error)
                    console.warn(`[plugins] ${modelData.pluginId}: settings section ${modelData.entry} failed to load`);
            }
        }
    }
}
