pragma Singleton

// The one place that knows what desktop widgets exist.
//
// Before this existed, a desktop widget had to be spelled out in three places that
// had no idea about each other: a hand-written FadeLoader in Background.qml, a row in
// WidgetsSubmenu's `widgetList`, and a card in BackgroundConfig. Plugin widgets were
// only ever added to two of them, so a plugin's desktop widget could not be switched
// on from the desktop right-click menu at all - it simply was not in the list.
//
// Now built-ins and plugin widgets are the same kind of thing: an id, a name, an
// icon, and a URL to load. Every consumer iterates this one list, so a widget that
// appears here appears everywhere, and a plugin that contributes one is
// indistinguishable from a built-in.
//
// Adding a built-in: drop the file under modules/ii/background/widgets/ and add a
// line to `builtins`. Adding one from a plugin: declare it under
// `provides.desktopWidgets` in the manifest. Neither requires touching a host.

import QtQuick
import Quickshell
import qs.modules.common
import qs.services

Singleton {
    id: root

    // `id` must match the widget's own `configEntryName`, because that is what it
    // reads its position and enabled state from.
    readonly property var builtins: [
        { id: "visualizer",  name: Translation.tr("Visualizer"),      icon: "graphic_eq",        path: "visualizer/VisualizerWidget.qml" },
        { id: "customImage", name: Translation.tr("Custom Image"),    icon: "image",             path: "images/CustomImage.qml" },
        { id: "weather",     name: Translation.tr("Weather"),         icon: "partly_cloudy_day", path: "weather/WeatherWidget.qml" },
        { id: "clock",       name: Translation.tr("Clock"),           icon: "schedule",          path: "clock/ClockWidget.qml", showWhenLocked: true },
        { id: "media",       name: Translation.tr("Media"),           icon: "music_note",        path: "media/MediaWidget.qml" },
        { id: "images",      name: Translation.tr("Image Converter"), icon: "photo_library",     path: "images/ImageConverterWidget.qml" },
        { id: "resources",   name: Translation.tr("Resources"),       icon: "monitor_heart",     path: "resources/ResourcesWidget.qml" },
        { id: "calendar",    name: Translation.tr("Calendar"),        icon: "calendar_month",    path: "calendar/CalendarWidget.qml" },
        { id: "worldClock",  name: Translation.tr("World Clock"),     icon: "public",            path: "worldclock/WorldClockWidget.qml" },
        { id: "userCard",    name: Translation.tr("User Card"),       icon: "person",            path: "usercard/UserCardWidget.qml" },
        { id: "notes",       name: Translation.tr("Notes"),           icon: "note_stack_add",    path: "notes/NotesWidget.qml" },
    ]

    // Built-ins first, in the order above, then plugin widgets grouped by plugin.
    //
    // Derived from `installedDesktopWidgets`, not the active list, so that toggling
    // any plugin does not reassign this and make every Repeater over it rebuild every
    // delegate. Whether a given widget's plugin is switched on is a per-entry
    // question - see `available()`.
    readonly property var all: Stable.list("desktop.all", (() => {
        const out = root.builtins.map(w => ({
            id: w.id,
            name: w.name,
            icon: w.icon,
            url: String(Qt.resolvedUrl("../modules/ii/background/widgets/" + w.path)),
            pluginId: "",
            showWhenLocked: w.showWhenLocked ?? false,
            enabledByDefault: false,
        }));

        for (const w of PluginRegistry.installedDesktopWidgets) {
            out.push({
                id: w.id,
                name: w.name ?? w.id,
                icon: w.icon ?? "extension",
                url: w.url,
                pluginId: w.pluginId,
                showWhenLocked: false,
                enabledByDefault: w.enabledByDefault !== false,
            });
        }
        return out;
    })())

    function find(id: string): var {
        return Stable.index("desktop.all", root.all)[id] ?? null;
    }

    // Whether the widget can be shown at all, as opposed to whether the user has
    // asked for it. A built-in always can; a plugin's can only once its plugin is
    // loaded.
    //
    // `isLoaded` rather than `isActive`: this gates instantiation, and loading a
    // widget in the same event-loop turn as the click that asked for it means the
    // frame acknowledging the click never gets painted.
    function available(entry): bool {
        return entry.pluginId === "" || PluginRegistry.isLoaded(entry.pluginId);
    }

    // Same question, but for GUI switches, which should track the click immediately
    // rather than lag the load.
    function installed(entry): bool {
        return entry.pluginId === "" || PluginRegistry.isActive(entry.pluginId);
    }

    function enabled(entry): bool {
        if (entry.pluginId === "")
            return Config.options.background.widgets[entry.id]?.enable ?? false;
        return PluginConfig.widgetEnabled(entry.pluginId, entry.id, entry.enabledByDefault);
    }

    function setEnabled(entry, on: bool) {
        if (entry.pluginId === "") {
            const cfg = Config.options.background.widgets[entry.id];
            if (cfg)
                cfg.enable = on;
            return;
        }
        PluginConfig.setWidgetEnabled(entry.pluginId, entry.id, on);
    }

    function toggle(entry) {
        root.setEnabled(entry, !root.enabled(entry));
    }
}
