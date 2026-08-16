pragma ComponentBehavior: Bound

// Feeds ComponentCache everything the shell can be asked to load by URL.
//
// Two groups, warmed in this order:
//
//   1. What a plugin provides. A panel or service is compiled the first time its plugin
//      is switched on, and that compile is why a toggle stutters. Warming every
//      installed plugin's entries - including the disabled ones, which are precisely the
//      ones the user is about to enable - means the toggle only pays instantiation.
//
//   2. What the built-in registries can resolve. Bar widgets, desktop widgets and quick
//      toggles are all loaded by URL on demand, so the first time you add a widget or
//      open the quick panel you pay for compiling it. There is no reason for that to
//      happen while the user is watching.
//
// Deliberately started late and drained slowly - see ComponentCache. This is spare-time
// work; it must never compete with the startup it is trying to make cheaper.

import QtQuick
import qs.core
import qs.modules.common

Item {
    id: root

    // Everything a plugin declares that resolves to a file.
    readonly property var pluginKinds: [
        "panels",
        "services",
        "barWidgets",
        "desktopWidgets",
        "quickToggles",
        "settingsPages",
        "settingsSections",
        "launcherActions"
    ]

    function pluginUrls(): var {
        const urls = [];
        for (const kind of root.pluginKinds) {
            for (const entry of PluginRegistry.collectInstalled(kind)) {
                if (entry.url)
                    urls.push(entry.url);
                // A quick toggle may ship a second file for the classic panel style.
                if (entry.classicEntry)
                    urls.push(PluginRegistry.resolve(entry.pluginId, entry.classicEntry));
            }
        }
        return urls;
    }

    function builtinUrls(): var {
        const urls = [];
        for (const widget of BarWidgetRegistry.all) {
            const url = BarWidgetRegistry.url(widget.id);
            if (url)
                urls.push(url);
        }
        for (const widget of DesktopWidgetRegistry.all) {
            if (widget.url)
                urls.push(widget.url);
        }
        for (const toggle of QuickToggleRegistry.all) {
            const android = QuickToggleRegistry.androidUrl(toggle.id);
            if (android)
                urls.push(android);
            const classic = QuickToggleRegistry.classicUrl(toggle.id);
            if (classic)
                urls.push(classic);
        }
        return urls;
    }

    function run() {
        // Plugins first: they are the ones with a visible switch attached.
        ComponentCache.warmAll(root.pluginUrls());
        ComponentCache.warmAll(root.builtinUrls());
    }

    // Long enough after startup that the shell has painted and settled. Waiting on
    // PluginRegistry.ready alone is not enough - the first frames are the busiest.
    Timer {
        interval: 2500
        running: PluginRegistry.ready && Config.ready
        onTriggered: root.run()
    }

    // A plugin appearing on disk at runtime gets warmed too, once the burst settles.
    Connections {
        target: PluginRegistry
        function onInstalledCacheKeyChanged() {
            rewarm.restart();
        }
    }

    Timer {
        id: rewarm
        interval: 3000
        onTriggered: root.run()
    }
}
