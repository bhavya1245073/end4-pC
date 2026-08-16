pragma Singleton

// The one place that knows what bar widgets exist.
//
// This knowledge used to be spread over four files that each held a piece of it:
//
//   - BarConfig.qml         names and icons (in a settings page, of all places)
//   - BarContent.qml        url resolution, pill rules, pill colours
//   - VerticalBarContent.qml  its own copy of all three
//   - BarConfig.availableFor  a second, separate list of which ids may repeat
//
// The two bars' copies had drifted, as copies do: the vertical bar refused to paint a
// pill behind `media` and the horizontal one refused to paint one behind
// `activeWindow`, so the same widget looked different depending on which bar it was
// in. Nobody chose that. This file resolves it to the horizontal bar's rules, which
// are the ones that match getMaterialPillColor's intent - it assigns `media` a colour,
// which only means something if media gets a pill.
//
// Adding a built-in: drop the file in modules/ii/bar/ and add a line here. Adding one
// from a plugin: declare it under `provides.barWidgets`. A plugin reusing a built-in
// id replaces the built-in.

import QtQuick
import Quickshell
import qs.modules.common
import qs.services

Singleton {
    id: root

    // `id` doubles as the layout token stored in config and as the file name, in
    // camelCase; `leftSidebarButton` loads `modules/ii/bar/LeftSidebarButton.qml`.
    //
    //   pill        paint the Material pill behind it (corner style 3). Default true.
    //   pillColor   Appearance colour name for that pill. Default primaryContainer.
    //   repeatable  may appear more than once in a layout.
    readonly property var builtins: [
        { id: "leftSidebarButton",     name: Translation.tr("Left Sidebar Button"), icon: "left_panel_open",              pill: false },
        { id: "workspaces",            name: Translation.tr("Workspaces"),          icon: "steppers",                    pill: false },
        { id: "weatherBar",            name: Translation.tr("Weather"),             icon: "flare" },
        { id: "media",                 name: Translation.tr("Media"),               icon: "music_note",                  pillColor: "secondaryContainer" },
        { id: "resources",             name: Translation.tr("Resources"),           icon: "empty_dashboard",             pillColor: "tertiaryContainer" },
        { id: "systemIcons",           name: Translation.tr("System Icons"),        icon: "info",                        pillColor: "primary" },
        { id: "networkSpeed",          name: Translation.tr("Network Speed"),       icon: "network_check" },
        { id: "clockWidget",           name: Translation.tr("Clock"),               icon: "schedule" },
        { id: "utilButtons",           name: Translation.tr("Util Buttons"),        icon: "toggle_on" },
        { id: "sysTray",               name: Translation.tr("Tray"),                icon: "inbox",                       pillColor: "secondaryContainer" },
        { id: "batteryIndicator",      name: Translation.tr("Battery"),             icon: "battery_android_frame_full" },
        { id: "activeWindow",          name: Translation.tr("Active Window"),       icon: "subtitles",                   pill: false },
        { id: "powerButton",           name: Translation.tr("Power Button"),        icon: "power_settings_new",          pill: false },
        { id: "updatesCount",          name: Translation.tr("Updates"),             icon: "deployed_code_update" },
        { id: "docktoPanel",           name: Translation.tr("Dock to Panel"),       icon: "apps",                        pill: false },
        { id: "visualizer",            name: Translation.tr("Visualizer"),          icon: "graphic_eq",                  repeatable: true },
        { id: "hyprlandXkbIndicator",  name: Translation.tr("Keyboard Layout"),     icon: "keyboard" },
        { id: "divisor",               name: Translation.tr("Divider"),             icon: "horizontal_distribute",       pill: false, repeatable: true },
        { id: "launcherButton",        name: Translation.tr("Launcher Button"),     icon: "search" },
    ]

    // Built-ins plus every active plugin's bar widgets. A plugin reusing a built-in id
    // replaces it rather than appearing twice.
    //
    // Active rather than installed: unlike the desktop widget list, this is only read
    // by JS functions and a settings-page list, never used as an Instantiator model,
    // so reassigning it on toggle costs a binding re-evaluation rather than a rebuild
    // of every widget.
    readonly property var all: {
        const list = root.builtins.map(w => ({
            id: w.id,
            name: w.name,
            icon: w.icon,
            url: Qt.resolvedUrl("../modules/ii/bar/" + w.id.charAt(0).toUpperCase() + w.id.slice(1) + ".qml"),
            pluginId: "",
            pill: w.pill !== false,
            pillColor: w.pillColor ?? "primaryContainer",
            repeatable: w.repeatable === true,
        }));

        for (const w of PluginRegistry.barWidgets) {
            const entry = {
                id: w.id,
                name: w.name ?? w.id,
                icon: w.icon ?? "extension",
                url: w.url,
                pluginId: w.pluginId,
                pill: w.materialPill !== false,
                pillColor: w.pillColor ?? "primaryContainer",
                repeatable: w.multipleAllowed === true,
            };
            const existing = list.findIndex(c => c.id === entry.id);
            if (existing >= 0)
                list[existing] = entry;
            else
                list.push(entry);
        }
        return list;
    }

    function find(id: string) {
        return root.all.find(w => w.id === id) ?? null;
    }

    function url(id: string): string {
        return root.find(id)?.url ?? "";
    }

    function name(id: string): string {
        return root.find(id)?.name ?? id;
    }

    function repeatable(id: string): bool {
        return root.find(id)?.repeatable ?? false;
    }

    // Whether the widget itself wants a pill. Whether one is drawn also depends on the
    // bar's corner style, which is the bar's business, not the widget's.
    function wantsPill(id: string): bool {
        return root.find(id)?.pill ?? true;
    }

    function pillColor(id: string): color {
        return Appearance.getColorFromName(root.find(id)?.pillColor ?? "primaryContainer");
    }
}
