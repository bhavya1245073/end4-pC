pragma Singleton

// The one place that knows what quick toggles exist.
//
// The Android panel resolved `modelData.type` through a DelegateChooser with one
// DelegateChoice per toggle, and each of those seventeen blocks repeated the same
// eleven property assignments to hand the toggle its grid context. Adding a toggle
// meant writing that block; a plugin could not add one at all, because
// DelegateChoice children have to be there at compile time.
//
// Now a toggle is a row in a table: an id, the file for each panel style, and which
// dialog its expand arrow opens. Plugins add rows through `provides.quickToggles`.
//
// The classic panel used to be seven statically declared toggles, so it silently
// ignored anything not in that list. It reads this table too.

import QtQuick
import Quickshell
import qs.modules.common
import qs.services

Singleton {
    id: root

    readonly property url androidDir: Qt.resolvedUrl("../modules/ii/sidebarRight/quickToggles/androidStyle/")
    readonly property url classicDir: Qt.resolvedUrl("../modules/ii/sidebarRight/quickToggles/classicStyle/")

    //   android/classic  file name within the style directory; omit if that style has
    //                    no version of this toggle
    //   menu             which dialog the expand arrow opens
    //   requires         compositor this toggle needs, if any
    readonly property var builtins: [
        { id: "network",          android: "AndroidNetworkToggle.qml",          classic: "NetworkToggle.qml",     menu: "wifi" },
        { id: "bluetooth",        android: "AndroidBluetoothToggle.qml",        classic: "BluetoothToggle.qml",   menu: "bluetooth" },
        { id: "idleInhibitor",    android: "AndroidIdleInhibitorToggle.qml",    classic: "IdleInhibitor.qml" },
        { id: "easyEffects",      android: "AndroidEasyEffectsToggle.qml",      classic: "EasyEffectsToggle.qml" },
        { id: "nightLight",       android: "AndroidNightLightToggle.qml",       classic: "NightLight.qml",        menu: "nightLight" },
        { id: "darkMode",         android: "AndroidDarkModeToggle.qml" },
        { id: "cloudflareWarp",   android: "AndroidCloudflareWarpToggle.qml",   classic: "CloudflareWarp.qml" },
        { id: "gameMode",         android: "AndroidGameModeToggle.qml",         classic: "GameMode.qml",          requires: "hyprland" },
        { id: "screenSnip",       android: "AndroidScreenSnipToggle.qml" },
        { id: "colorPicker",      android: "AndroidColorPickerToggle.qml" },
        { id: "onScreenKeyboard", android: "AndroidOnScreenKeyboardToggle.qml" },
        { id: "mic",              android: "AndroidMicToggle.qml",              menu: "audioInput" },
        { id: "audio",            android: "AndroidAudioToggle.qml",            menu: "audioOutput" },
        { id: "notifications",    android: "AndroidNotificationToggle.qml" },
        { id: "powerProfile",     android: "AndroidPowerProfileToggle.qml" },
        { id: "musicRecognition", android: "AndroidMusicRecognition.qml" },
        // Routed to the night light dialog by the panel it replaced. That looks like a
        // copy-paste, but it is what shipped, so it is preserved rather than quietly
        // changed.
        { id: "antiFlashbang",    android: "AndroidAntiFlashbangToggle.qml",    menu: "nightLight" },
    ]

    // Built-ins plus every *installed* plugin's toggles, whether enabled or not.
    //
    // Installed rather than active, and identity-stabilised, for the same reason as the
    // other registries: this list is a Repeater model, so a new identity rebuilds every
    // toggle in the panel. Deriving it from the active set meant enabling any plugin
    // anywhere rebuilt all seventeen. Enabled state is applied by `availableFor` below.
    readonly property var all: Stable.list("quickToggles.all", (() => {
        const list = root.builtins.map(t => ({
            id: t.id,
            pluginId: "",
            android: t.android ? String(root.androidDir) + t.android : "",
            classic: t.classic ? String(root.classicDir) + t.classic : "",
            menu: t.menu ?? "",
            requires: t.requires ?? "",
        }));

        for (const t of PluginRegistry.installedQuickToggles) {
            const entry = {
                id: t.id,
                pluginId: t.pluginId,
                // A plugin supplies one file and it is used for whichever style is
                // showing; asking every plugin to draw two panel styles is not a
                // reasonable price of entry.
                android: t.url,
                classic: t.classicUrl ?? t.url,
                menu: t.menu ?? "",
                requires: t.requires ?? "",
            };
            const existing = list.findIndex(c => c.id === entry.id);
            if (existing >= 0)
                list[existing] = entry;
            else
                list.push(entry);
        }
        return list;
    })())

    // Toggles usable on this compositor, for the style asked for, from plugins that are
    // switched on. Stabilised per style, so toggling an unrelated plugin leaves the
    // panel's model untouched.
    function availableFor(style: string): var {
        return Stable.list(`quickToggles.available.${style}`, root.all.filter(t => {
            if (t.requires !== "" && WM.compositor !== t.requires)
                return false;
            if (t.pluginId !== "" && !PluginRegistry.isActive(t.pluginId))
                return false;
            return (style === "classic" ? t.classic : t.android) !== "";
        }));
    }

    function availableIds(style: string): var {
        return Stable.ids(`quickToggles.availableIds.${style}`, root.availableFor(style).map(t => t.id));
    }

    function find(id: string): var {
        return Stable.index("quickToggles.all", root.all)[id] ?? null;
    }

    function androidUrl(id: string): string {
        return root.find(id)?.android ?? "";
    }

    function classicUrl(id: string): string {
        return root.find(id)?.classic ?? "";
    }

    function menuFor(id: string): string {
        return root.find(id)?.menu ?? "";
    }
}
