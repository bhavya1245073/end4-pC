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
// The model is every *installed* section, not the active ones: a Repeater over a
// reassigned JS array rebuilds all of its delegates, so an active-derived model made
// toggling one plugin rebuild every section on the page.
//
// ## Loaded once, then only shown or hidden
//
// The obvious way to make a section disappear is to unload it - `active:
// isLoaded(pluginId)` - and that is what this did. It is also the single most expensive
// thing that happened when a plugin was toggled: measured in the real settings window,
// toggling a plugin that owns a section blocked the UI thread for 390ms and spent 48% of
// a five-second window blocked, while a plugin with no section cost 13ms. That is the
// difference the user could feel between one plugin and another, and it had nothing to do
// with the plugin.
//
// A settings section is a few dozen controls. Building them is not free, throwing them
// away and rebuilding them on a switch flip is waste, and `asynchronous: true` does not
// help nearly as much as it sounds - the incubator still does the work on this thread.
//
// So a section is built the first time its plugin is on, and after that toggling only
// changes `visible`. Qt Quick Layouts exclude invisible items, so a hidden section
// collapses exactly as if it were gone. The controls of a switched-off plugin are inert
// either way: they write to that plugin's stored settings, which is where they belong.

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
            id: section

            required property var modelData

            // Sticky: once built, it stays built. Flipping this back to false is what
            // used to cost 390ms every time the user touched a switch.
            property bool everLoaded: false

            Layout.fillWidth: true

            // `isLoaded`, not `isActive`: this section is on the very page the user just
            // clicked the switch on, so building it in the same turn as the click means
            // the frame acknowledging the click never gets painted.
            active: section.everLoaded || PluginRegistry.isLoaded(section.modelData.pluginId)
            asynchronous: true
            source: section.modelData.url ?? ""

            // `isActive`, not `isLoaded`: hiding should track the click immediately.
            visible: PluginRegistry.isActive(section.modelData.pluginId)

            onLoaded: section.everLoaded = true

            onStatusChanged: {
                if (section.status === Loader.Error)
                    console.warn(`[plugins] ${section.modelData.pluginId}: settings section ${section.modelData.entry} failed to load`);
            }
        }
    }
}
