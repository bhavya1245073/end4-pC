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
import "Memo.js" as Memo

Singleton {
    id: root

    // Bump when a breaking change is made to the manifest format or to the
    // properties injected into plugin components. Plugins declare the version
    // they were written against as `apiVersion`.
    readonly property int apiVersion: 1
    readonly property int minApiVersion: 1

    // Where plugins are looked for, in increasing precedence: a later path shadows an
    // earlier one, so a user copy of `battery` wins over the shipped one.
    //
    //   <shell>/plugins            what ships with the shell
    //   ~/.config/illogical-impulse/plugins   drop a folder in, no rebuild, no git
    //   $END4_PLUGIN_PATH          colon-separated, for a Nix config or a dev checkout
    //
    // The last of those is how out-of-tree plugins stay out of tree: the NixOS module
    // points at them instead of copying them into the shell derivation, and a devMode
    // checkout keeps working without symlinking anything into it.
    readonly property list<string> pluginPaths: {
        const paths = [`${Quickshell.shellDir}/plugins`, root.userPluginsDir];
        for (const extra of (Quickshell.env("END4_PLUGIN_PATH") ?? "").split(":")) {
            const trimmed = extra.trim();
            if (trimmed.length > 0 && !paths.includes(trimmed))
                paths.push(trimmed);
        }
        return paths;
    }

    // The one path that is writable and outlives a rebuild.
    readonly property string userPluginsDir: `${Quickshell.env("XDG_CONFIG_HOME") || `${Quickshell.env("HOME")}/.config`}/illogical-impulse/plugins`

    // The first path, kept as a property because the settings GUI offers to open it and
    // launcher actions resolve scripts against a plugin's own directory.
    readonly property string pluginsDir: root.pluginPaths[0]

    // id -> the directory that won. Written by rescan(), read by resolve() and by
    // PluginManifest, so a plugin's files always resolve against the path it came from.
    property var pluginDirs: ({})

    // id -> descriptor. Reassigned (never mutated) so bindings update.
    // Descriptor: { id, name, description, version, author, icon, dir, url,
    //               provides, settings, manifest }
    property var plugins: ({})

    // Ids of every directory found on any search path, whether or not its
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

    // Membership as a map, because `isActive` is called from bindings all over the bar,
    // the launcher and the settings GUI, and `Array.includes` on every one of them is a
    // scan. Rebuilt only when the id list itself changes.
    readonly property var activeSet: {
        const set = ({});
        for (const id of root.activeIds)
            set[id] = true;
        return set;
    }

    readonly property var loadedSet: {
        const set = ({});
        for (const id of root.loadedIds)
            set[id] = true;
        return set;
    }

    readonly property var active: root.all.filter(plugin => root.activeSet[plugin.id] === true)

    readonly property var panels: root.collect("panels")
    readonly property var services: root.collect("services")
    readonly property var ipc: root.collect("ipc")
    readonly property var barWidgets: root.collect("barWidgets")
    readonly property var desktopWidgets: root.collect("desktopWidgets")
    readonly property var launcherActions: root.collect("launcherActions")
    readonly property var shortcuts: root.collect("shortcuts")
    readonly property var quickToggles: root.collect("quickToggles")
    readonly property var searchProviders: root.collect("searchProviders")
    readonly property var contextMenuItems: root.collect("contextMenuItems")
    readonly property var osdIndicators: root.collect("osdIndicators")

    // The same lists over *installed* plugins, enabled or not.
    //
    // These exist so that things which instantiate one object per entry can use a
    // model that does not change when a plugin is toggled. An Instantiator or
    // Repeater over a plain JS array rebuilds every delegate when the array is
    // reassigned, so a model derived from `active` meant that enabling one plugin
    // destroyed and recreated every other plugin's panels and services - a freeze of
    // a minute or more, and entirely avoidable. Depend on these and put the enabled
    // state on the delegate's `active` instead, which is a cheap boolean flip.
    readonly property var installedPanels: root.collectInstalled("panels")
    readonly property var installedServices: root.collectInstalled("services")
    readonly property var installedIpc: root.collectInstalled("ipc")
    readonly property var installedShortcuts: root.collectInstalled("shortcuts")
    readonly property var installedDesktopWidgets: root.collectInstalled("desktopWidgets")
    readonly property var installedBarWidgets: root.collectInstalled("barWidgets")
    readonly property var installedQuickToggles: root.collectInstalled("quickToggles")
    readonly property var installedSearchProviders: root.collectInstalled("searchProviders")
    readonly property var installedContextMenuItems: root.collectInstalled("contextMenuItems")
    readonly property var installedOsdIndicators: root.collectInstalled("osdIndicators")

    // Same memo as `collect`, over installed plugins rather than active ones. Keyed on
    // the plugin table, which changes only when a plugin appears or disappears on disk -
    // so these lists keep their identity across a toggle, which is the whole reason they
    // exist. Computed from `plugins` rather than the `all` binding, for the coherence
    // reason above.
    function collectInstalled(kind: string): var {
        return Memo.cached("installed", root.installedKey, kind, () => root.collectFrom(root.pluginsByName(Object.keys(root.plugins)), kind));
    }

    // Changes only when a plugin appears or disappears on disk.
    readonly property string installedKey: Object.keys(root.plugins).sort().join(",")

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
        return root.collectInstalled("settingsSections")
            .filter(section => (section.page ?? "").toLowerCase() === wanted)
            .sort((a, b) => (a.order ?? 100) - (b.order ?? 100));
    }

    readonly property var settingsPages: root.collect("settingsPages")
        .sort((a, b) => (a.order ?? 100) - (b.order ?? 100))

    // Settings pages of *installed* plugins, enabled or not. The settings GUI
    // uses this rather than `settingsPages` so that toggling a plugin doesn't
    // rebuild - and scroll-reset - the page you are toggling it from. Pages of
    // disabled plugins are shown greyed out by the GUI instead.
    readonly property var installedSettingsPages: root.collectInstalled("settingsPages")
        .sort((a, b) => (a.order ?? 100) - (b.order ?? 100))

    // Flattens one `provides.<kind>` list across all active plugins, tagging
    // each entry with `pluginId` and resolving `entry` to an absolute `url`.
    //
    // Memoised on the active plugin list. `collect` is called from `find`, from
    // `sectionsFor`, and from three registries' `all` bindings, so without a cache the
    // same flatten-and-tag ran dozens of times for one toggle - each run allocating a
    // fresh array, whose new identity then invalidated whatever read it.
    //
    // Both the key and the value are derived from `plugins` and `activeIds` directly, and
    // deliberately not from the `active` binding. `active` is recomputed *from*
    // `activeIds`, so during the pass where `activeIds` has already changed and `active`
    // has not, keying on one while computing from the other caches a result from before
    // the change under the key from after it. That is permanent: the key never changes
    // again, so the stale value is returned forever. It shipped as zero plugin panels.
    //
    // The cache lives in Memo.js rather than in properties here: a memo reads what it
    // writes, and doing that with QML properties inside a binding is a dependency cycle.
    // Written the obvious way it produced "Binding loop detected for property panels"
    // and Qt dropped the binding.
    function collect(kind: string): var {
        return Memo.cached("active", `${root.installedKey}|${root.activeIds.join(",")}`, kind, () => root.collectFrom(root.pluginsByName(root.activeIds), kind));
    }

    // Descriptors for a list of ids, in the same name order as `all`, skipping ids with
    // no descriptor.
    function pluginsByName(ids: var): var {
        return ids
            .map(id => root.plugins[id])
            .filter(plugin => plugin !== undefined)
            .sort((a, b) => a.name.localeCompare(b.name));
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
        return `file://${root.dirOf(pluginId)}/${relativePath}`;
    }

    // The directory a plugin was found in. Falls back to the first search path so that a
    // caller asking about an unknown id gets a plausible path rather than "undefined".
    function dirOf(pluginId: string): string {
        return root.pluginDirs[pluginId] ?? `${root.pluginsDir}/${pluginId}`;
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
        return root.activeSet[pluginId] === true;
    }

    function setEnabled(pluginId: string, enabled: bool) {
        PluginConfig.setEnabled(pluginId, enabled);

        // A bar widget nothing has placed is invisible, so a plugin whose only
        // contribution is one used to switch on and appear to do nothing at all. If it
        // declared a `zone`, put it there - once, on the first enable. See
        // BarWidgetRegistry.autoPlace.
        //
        // Deferred because the widget's own settings write and this one would otherwise
        // race through PluginConfig's write coalescing.
        if (enabled)
            Qt.callLater(() => BarWidgetRegistry.autoPlace(pluginId));
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
        return root.loadedSet[pluginId] === true;
    }

    // True when every file a plugin provides has already been compiled, so switching it
    // on costs only instantiation. See core/ComponentCache.qml.
    function isWarm(pluginId: string): bool {
        const plugin = root.plugins[pluginId];
        if (!plugin)
            return true;
        for (const kind in plugin.provides) {
            const entries = plugin.provides[kind];
            if (!Array.isArray(entries))
                continue;
            for (const entry of entries) {
                if (entry.entry && !ComponentCache.isWarm(root.resolve(pluginId, entry.entry)))
                    return false;
            }
        }
        return true;
    }

    onActiveIdsChanged: {
        // The yield only has to be long enough to get a frame out. 80ms was sized for a
        // cold compile happening immediately afterwards; once the plugin is pre-compiled
        // the load is short enough that one frame of delay is plenty, and the toggle
        // stops feeling deferred.
        const cold = root.activeIds.some(id => !root.isWarm(id));
        loadTimer.interval = cold ? 80 : 16;
        loadTimer.restart();
    }

    Timer {
        id: loadTimer
        interval: 16
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
        // Later paths shadow earlier ones, so walk in order and let each overwrite.
        const dirs = ({});
        for (let scanner = 0; scanner < folderScanners.count; scanner++) {
            const folders = folderScanners.objectAt(scanner);
            if (!folders)
                continue;
            for (const name of folders.entries)
                dirs[name] = `${folders.base}/${name}`;
        }
        // Clearing here is safe: every manifest re-registers as the
        // Instantiator rebuilds its delegates from the new id list.
        root.pending = ({});
        root.plugins = ({});
        root.errors = [];
        root.pluginDirs = dirs;
        root.discovered = Object.keys(dirs).sort();
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
            dir: root.dirOf(pluginId),
            url: `file://${root.dirOf(pluginId)}`,
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

    // One folder watcher per search path. A missing directory is not an error - the user
    // plugin directory usually does not exist - it simply contributes nothing.
    Instantiator {
        id: folderScanners
        model: root.pluginPaths
        delegate: QtObject {
            id: scanner
            required property string modelData
            readonly property string base: modelData

            // Whether this search path exists.
            //
            // The check is a real stat rather than something inferred from the model, because
            // FolderListModel cannot be asked: pointed at a directory that does not exist it
            // reports zero entries, exactly like an empty one, and pointed at a bad path *after*
            // listing something else it keeps the old contents. Comparing each entry's own
            // filePath against the requested path was the previous attempt, and it fails the case
            // that matters most - the shell directory is usually a symlink, Qt canonicalises
            // filePath through it, and every plugin was rejected as "not on this path".
            property bool exists: false
            property bool checked: false

            function check(): void {
                PluginUtils.run(["test", "-d", scanner.base], (stdout, code) => {
                    scanner.exists = code === 0;
                    scanner.checked = true;
                    PluginRegistry.scheduleRescan();
                });
            }

            Component.onCompleted: scanner.check()

            readonly property var entries: {
                if (!scanner.exists)
                    return [];
                const found = [];
                for (let i = 0; i < folderModel.count; i++) {
                    const name = folderModel.get(i, "fileName") ?? "";
                    if (!name || name.startsWith(".") || name.startsWith("_"))
                        continue;
                    found.push(name);
                }
                return found;
            }

            readonly property FolderListModel __model: FolderListModel {
                id: folderModel
                folder: scanner.exists ? `file://${scanner.base}` : ""
                showDirs: true
                showFiles: false
                showDotAndDotDot: false
                showHidden: false
                sortField: FolderListModel.Name
                // Through the singleton, not the outer `rescanTimer` id: this file sets
                // `pragma ComponentBehavior: Bound`, so a delegate cannot see ids in the
                // enclosing scope, and the handler would fail silently - leaving discovery
                // stuck on whatever the first, empty scan found.
                onCountChanged: PluginRegistry.scheduleRescan()
            }
        }
        onObjectAdded: PluginRegistry.scheduleRescan()
        onObjectRemoved: PluginRegistry.scheduleRescan()
    }

    // Coalesces the incremental countChanged bursts a folder scan produces.
    function scheduleRescan(): void {
        rescanTimer.restart();
    }

    // One line per search path: whether it exists and how many plugin directories are on it.
    // Surfaced over IPC as `plugins scan`, because "my plugin is not showing up" has exactly three
    // causes - wrong path, path does not exist, directory has no manifest - and this separates them.
    function scannerReport(): string {
        const lines = [];
        for (let index = 0; index < folderScanners.count; index++) {
            const scanner = folderScanners.objectAt(index);
            if (!scanner)
                continue;
            lines.push(`${scanner.checked ? (scanner.exists ? "exists " : "missing") : "pending"} ${String(scanner.entries.length).padStart(3)} entries  ${scanner.base}`);
        }
        return lines.join("\n");
    }

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

    // ------------------------------------------------- live IPC dispatch
    //
    // Plugin IPC targets are reachable from the command line through Quickshell's own
    // IpcHandler machinery, but nothing in the shell could *call* one - so a context menu
    // row or a quick toggle wanting to trigger a plugin action had to spawn
    // `qs ipc call ...` and pay a process for it.
    //
    // Each PluginIpc registers itself here on completion. Keyed by target, which is the
    // name the command line uses too, so one plugin action has exactly one name whether
    // it is invoked from a menu, a keybind or a shell.
    property var ipcTargets: ({})

    function registerIpc(handler: var): void {
        if (!handler?.target)
            return;
        const next = Object.assign({}, root.ipcTargets);
        next[handler.target] = handler;
        root.ipcTargets = next;
    }

    function unregisterIpc(handler: var): void {
        if (!handler?.target || root.ipcTargets[handler.target] !== handler)
            return;
        const next = Object.assign({}, root.ipcTargets);
        delete next[handler.target];
        root.ipcTargets = next;
    }

    // Calls a plugin IPC function in-process. Returns false if the target, the function,
    // or the plugin providing it is not there - callers report that rather than failing
    // silently, because a typo in a manifest is otherwise invisible.
    function invokeIpc(target: string, name: string, args: var): bool {
        const handler = root.ipcTargets[target];
        if (!handler || typeof handler[name] !== "function")
            return false;
        try {
            handler[name].apply(handler, args ?? []);
        } catch (e) {
            console.warn(`[plugins] ipc ${target}.${name} threw:`, e);
        }
        return true;
    }

    Component.onCompleted: root.rescan()
}
