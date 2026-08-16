pragma Singleton

// Every OSD indicator the shell can show, built-in and plugin alike.
//
// The on-screen display used to carry a hardcoded list of three indicators, which
// meant a plugin could not add a HUD of its own - a pomodoro countdown, a build
// progress bar, a "microphone muted" flash - without editing the OSD.
//
// A plugin declares one in its manifest:
//
//     "osdIndicators": [
//         { "id": "pomodoro", "entry": "PomodoroOsd.qml", "timeout": 4000 }
//     ]
//
// and shows it from anywhere:
//
//     OsdRegistry.show("pomodoro")
//
// The indicator's QML draws only the content; the OSD owns the window, the placement,
// the timeout and the dismiss-on-hover behaviour, so an indicator is usually a row of
// an icon and a bar.
//
// Built-ins are rows in the same table (see `builtins` below) rather than a special
// case in the host, so the OSD reads one list and cannot tell which is which.

import QtQuick
import Quickshell
import qs.modules.common

Singleton {
    id: root

    // The shell's own indicators. Paths are relative to the OSD panel's own folder, so
    // they resolve exactly as they did when this list lived inside it.
    readonly property var builtins: [
        {
            id: "volume",
            entry: "indicators/VolumeIndicator.qml"
        },
        {
            id: "brightness",
            entry: "indicators/BrightnessIndicator.qml"
        },
        {
            id: "gamma",
            entry: "indicators/GammaIndicator.qml"
        }
    ]

    // Which indicator the OSD is currently showing.
    property string current: "volume"

    // Set by the OSD panel when it loads, so built-in entries resolve against the
    // panel's folder while plugin entries carry absolute URLs from the registry.
    property string builtinBase: ""

    readonly property var all: Stable.list("OsdRegistry.all", (() => {
        const entries = root.builtins.map(indicator => ({
            id: indicator.id,
            entry: indicator.entry,
            url: root.builtinBase === "" ? indicator.entry : `${root.builtinBase}/${indicator.entry}`,
            timeout: 0,
            builtin: true,
            pluginId: ""
        }));

        for (const indicator of PluginRegistry.osdIndicators) {
            if (!indicator.id || !indicator.url)
                continue;
            entries.push({
                id: indicator.id,
                entry: indicator.entry,
                url: indicator.url,
                // 0 means "use the user's configured OSD timeout".
                timeout: indicator.timeout ?? 0,
                builtin: false,
                pluginId: indicator.pluginId
            });
        }

        return entries;
    })())

    readonly property var ids: Stable.ids("OsdRegistry.ids", root.all.map(indicator => indicator.id))

    function find(id: string): var {
        return root.all.find(indicator => indicator.id === id) ?? null;
    }

    function urlFor(id: string): string {
        return root.find(id)?.url ?? "";
    }

    // Show an indicator. `id` must be registered; a typo is reported rather than
    // silently showing the volume OSD, which is what a bare assignment would do.
    function show(id: string): void {
        const indicator = root.find(id);
        if (!indicator) {
            console.warn(`[plugins] no OSD indicator "${id}" - registered:`, root.ids.join(", "));
            return;
        }
        root.current = id;
        root.requested(id, indicator.timeout);
    }

    // The OSD panel connects to this. A signal rather than the panel watching `current`,
    // because showing the same indicator twice in a row is two events and a property
    // assignment of the same value is none.
    signal requested(string id, int timeout)
}
