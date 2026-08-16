pragma Singleton
pragma ComponentBehavior: Bound

// Plugin discovery and registry.
//
// Every directory under `<shell root>/plugins/` that contains a `manifest.json`
// becomes a plugin. Nothing else is needed to install one: no Nix edits, no
// imports to add, no core file to touch.
//
// See docs/PLUGINS.md for the manifest format.

import QtQuick
import QtQml
import Quickshell
import Qt.labs.folderlistmodel
import qs.services

Singleton {
    id: root

    // Bump when a breaking change is made to the manifest format or to the
    // properties injected into plugin components. Plugins declare the version
    // they were written against as `apiVersion`.
    readonly property int apiVersion: 1
    readonly property int minApiVersion: 1

    readonly property string pluginsDir: `${Quickshell.shellDir}/plugins`

    // id -> descriptor. Reassigned (never mutated) so bindings update.
    // Descriptor: { id, name, description, version, author, icon, dir, url,
    //               provides, settings, manifest }
    property var plugins: ({})

    // Ids of every directory found under pluginsDir, whether or not its
    // manifest parsed successfully.
    property var discovered: []

    // [{ id, message }] - manifest problems, surfaced in the settings GUI.
    property var errors: []

    readonly property bool ready: discovered.length === 0
        || Object.keys(plugins).length + errors.length >= discovered.length

    // ------------------------------------------------------------------ lists

    readonly property var all: Object.keys(root.plugins)
        .map(id => root.plugins[id])
        .sort((a, b) => a.name.localeCompare(b.name))

    // Ids that are both switched on and supported on this system. Recomputed
    // only when the set actually changes, so writing an unrelated plugin
    // setting never tears down loaded plugin components.
    property var activeIds: []

    readonly property var active: root.all.filter(plugin => root.activeIds.includes(plugin.id))

    readonly property var panels: root.collect("panels")
    readonly property var services: root.collect("services")
    readonly property var barWidgets: root.collect("barWidgets")
    readonly property var desktopWidgets: root.collect("desktopWidgets")
    readonly property var launcherActions: root.collect("launcherActions")
    readonly property var shortcuts: root.collect("shortcuts")

    // The same lists over *installed* plugins, enabled or not.
    //
    // These exist so that things which instantiate one object per entry can use a
    // model that does not change when a plugin is toggled. An Instantiator or
    // Repeater over a plain JS array rebuilds every delegate when the array is
    // reassigned, so a model derived from `active` meant that enabling one plugin
    // destroyed and recreated every other plugin's panels and services - a freeze of
    // a minute or more, and entirely avoidable. Depend on these and put the enabled
    // state on the delegate's `active` instead, which is a cheap boolean flip.
    readonly property var installedPanels: root.collectFrom(root.all, "panels")
    readonly property var installedServices: root.collectFrom(root.all, "services")
    readonly property var installedShortcuts: root.collectFrom(root.all, "shortcuts")
    readonly property var installedDesktopWidgets: root.collectFrom(root.all, "desktopWidgets")

    // Sections a plugin injects into an existing settings page, rather than a whole
    // page of its own. This is what lets a plugin's settings live next to the related
    // built-in ones and, crucially, disappear when the plugin is switched off - a
    // hardcoded section for a plugin that is not running is a dead control.
    readonly property var settingsSections: root.collect("settingsSections")

    // Sections for one host page, in declared order. `page` matches the `page` field
    // in the manifest, case-insensitively. Installed rather than active, for the
    // model-stability reason above; the host hides the ones whose plugin is off.
    function sectionsFor(page: string): var {
        const wanted = page.toLowerCase();
        return root.collectFrom(root.all, "settingsSections")
            .filter(section => (section.page ?? "").toLowerCase() === wanted)
            .sort((a, b) => (a.order ?? 100) - (b.order ?? 100));
    }

    readonly property var settingsPages: root.collect("settingsPages")
        .sort((a, b) => (a.order ?? 100) - (b.order ?? 100))

    // Settings pages of *installed* plugins, enabled or not. The settings GUI
    // uses this rather than `settingsPages` so that toggling a plugin doesn't
    // rebuild - and scroll-reset - the page you are toggling it from. Pages of
    // disabled plugins are shown greyed out by the GUI instead.
    readonly property var installedSettingsPages: root.collectFrom(root.all, "settingsPages")
        .sort((a, b) => (a.order ?? 100) - (b.order ?? 100))

    // Flattens one `provides.<kind>` list across all active plugins, tagging
    // each entry with `pluginId` and resolving `entry` to an absolute `url`.
    function collect(kind: string): var {
        return root.collectFrom(root.active, kind);
    }

    function collectFrom(plugins: var, kind: string): var {
        const result = [];
        for (const plugin of plugins) {
            const entries = plugin.provides[kind];
            if (!Array.isArray(entries))
                continue;
            for (const entry of entries) {
                const tagged = Object.assign({}, entry);
                tagged.pluginId = plugin.id;
                tagged.pluginName = plugin.name;
                if (entry.entry)
                    tagged.url = root.resolve(plugin.id, entry.entry);
                result.push(tagged);
            }
        }
        return result;
    }

    function resolve(pluginId: string, relativePath: string): string {
        return `file://${root.pluginsDir}/${pluginId}/${relativePath}`;
    }

    function get(pluginId: string): var {
        return root.plugins[pluginId] ?? null;
    }

    // Looks up a single provided entry, e.g. find("barWidgets", "clock").
    function find(kind: string, id: string): var {
        return root.collect(kind).find(entry => entry.id === id) ?? null;
    }

    function barWidget(id: string): var {
        return root.barWidgets.find(widget => widget.id === id) ?? null;
    }

    function desktopWidget(id: string): var {
        return root.desktopWidgets.find(widget => widget.id === id) ?? null;
    }

    // ----------------------------------------------------------- enable state

    // What the user asked for, ignoring whether the plugin can run here.
    // Reads PluginConfig.data, so GUI bindings on it stay reactive.
    function isEnabled(pluginId: string): bool {
        const plugin = root.plugins[pluginId];
        if (!plugin)
            return false;
        const stored = PluginConfig.data[pluginId]?.enabled;
        if (stored === undefined)
            return plugin.manifest.enabledByDefault !== false;
        return stored === true;
    }

    function isActive(pluginId: string): bool {
        return root.activeIds.includes(pluginId);
    }

    function setEnabled(pluginId: string, enabled: bool) {
        PluginConfig.setEnabled(pluginId, enabled);
    }

    // Plugins may declare `requires.compositor: ["hyprland"]`, and are skipped
    // (with a note in the GUI) everywhere else.
    function isSupported(plugin: var): bool {
        const requires = plugin?.manifest?.requires;
        if (!requires)
            return true;
        if (Array.isArray(requires.compositor) && requires.compositor.length > 0)
            return requires.compositor.includes(WM.compositor);
        return true;
    }

    function unsupportedReason(plugin: var): string {
        const requires = plugin?.manifest?.requires;
        if (Array.isArray(requires?.compositor) && !requires.compositor.includes(WM.compositor))
            return Translation.tr("Only runs on %1").arg(requires.compositor.join(", "));
        return "";
    }

    function recomputeActive() {
        const ids = Object.keys(root.plugins)
            .filter(id => root.isEnabled(id) && root.isSupported(root.plugins[id]))
            .sort();
        if (ids.length === root.activeIds.length && ids.every((id, i) => id === root.activeIds[i]))
            return;
        root.activeIds = ids;
    }

    // Which plugins should have their components loaded. Follows `activeIds`, but one
    // event-loop turn later.
    //
    // Flipping the switch in the GUI updates `activeIds` synchronously, and if loading
    // started in that same turn the frame showing the switch in its new position never
    // got painted - so the switch appeared to stick for as long as the plugin took to
    // load, then snap over. A plugin panel is a window with `Variants` in it, which
    // Quickshell cannot load asynchronously, so that is seconds of blocked UI thread
    // and there is no making it instant. Yielding first at least means the click is
    // acknowledged before the cost is paid.
    //
    // Anything that only *reads* which plugins are on (the bar, the launcher, the GUI)
    // should use `activeIds` and stay immediate. This is for things that instantiate.
    property var loadedIds: []

    function isLoaded(pluginId: string): bool {
        return root.loadedIds.includes(pluginId);
    }

    onActiveIdsChanged: loadTimer.restart()

    Timer {
        id: loadTimer
        // Long enough to guarantee a paint, short enough to be invisible.
        interval: 80
        onTriggered: root.loadedIds = root.activeIds
    }

    onPluginsChanged: root.recomputeActive()

    Connections {
        target: PluginConfig
        function onDataChanged() {
            root.recomputeActive();
        }
    }

    // -------------------------------------------------------------- discovery

    function rescan() {
        const ids = [];
        for (let i = 0; i < pluginFolders.count; i++) {
            const name = pluginFolders.get(i, "fileName");
            if (!name || name.startsWith(".") || name.startsWith("_"))
                continue;
            ids.push(name);
        }
        // Clearing here is safe: every manifest re-registers as the
        // Instantiator rebuilds its delegates from the new id list.
        root.pending = ({});
        root.plugins = ({});
        root.errors = [];
        root.discovered = ids;
    }

    // Manifests arrive one at a time, each from its own FileView. Assigning
    // `root.plugins` per manifest meant twenty reassignments per scan, and every one
    // of them invalidated `all`, `active` and all eight provides lists - so anything
    // instantiating from those rebuilt twenty times over during startup. They are
    // collected here and published in one go instead.
    property var pending: ({})

    function register(pluginId: string, manifest: var) {
        if (typeof manifest !== "object" || manifest === null)
            return root.reportError(pluginId, Translation.tr("manifest.json is not an object"));
        if (manifest.id !== undefined && manifest.id !== pluginId)
            return root.reportError(pluginId, Translation.tr("manifest id \"%1\" does not match its folder name").arg(manifest.id));

        const declared = manifest.apiVersion ?? 1;
        if (declared > root.apiVersion || declared < root.minApiVersion)
            return root.reportError(pluginId, Translation.tr("needs plugin API v%1, this shell provides v%2").arg(declared).arg(root.apiVersion));

        root.pending[pluginId] = {
            id: pluginId,
            name: manifest.name ?? pluginId,
            description: manifest.description ?? "",
            version: manifest.version ?? "",
            author: manifest.author ?? "",
            icon: manifest.icon ?? "extension",
            dir: `${root.pluginsDir}/${pluginId}`,
            url: `file://${root.pluginsDir}/${pluginId}`,
            provides: manifest.provides ?? ({}),
            settings: Array.isArray(manifest.settings) ? manifest.settings : [],
            manifest: manifest
        };

        publishTimer.restart();
    }

    // Short, because it only has to outlast the burst of FileView loads. A plugin
    // whose manifest arrives late still lands, in its own second publish.
    Timer {
        id: publishTimer
        interval: 30
        onTriggered: root.plugins = Object.assign({}, root.pending)
    }

    function reportError(pluginId: string, message: string) {
        console.warn(`[plugins] ${pluginId}: ${message}`);
        root.errors = root.errors.concat([
            {
                id: pluginId,
                message: message
            }
        ]);
    }

    FolderListModel {
        id: pluginFolders
        folder: `file://${root.pluginsDir}`
        showDirs: true
        showFiles: false
        showDotAndDotDot: false
        showHidden: false
        sortField: FolderListModel.Name
        onCountChanged: rescanTimer.restart()
    }

    // Coalesces the incremental countChanged bursts a folder scan produces.
    Timer {
        id: rescanTimer
        interval: 20
        onTriggered: root.rescan()
    }

    Instantiator {
        model: root.discovered
        delegate: PluginManifest {
            required property string modelData
            pluginId: modelData
        }
    }

    Component.onCompleted: root.rescan()
}
