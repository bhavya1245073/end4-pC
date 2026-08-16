pragma Singleton
pragma ComponentBehavior: Bound

// Session and compositor state: the handful of things that are true of the *shell*, not of any
// one feature.
//
// This file used to hold thirty-odd booleans, one per feature - `overviewOpen`, `oskOpen`,
// `dropShelfOpen`, `wallpaperSelectorTarget`, `visualizerPoints`. That made core the registry of
// every feature that existed, so adding a panel meant editing core, and a plugin could not have
// one at all. Those live where they belong now:
//
//   panels open/closed, and their arguments   PanelRegistry.state(id)
//   the audio spectrum                        PluginAudio / PluginSpectrum
//   what a hot corner does                    PanelRegistry.ids, resolved at use
//
// What is left is genuinely global: whether the screen is locked, whether Super is held, which
// settings page the settings window is showing.

import qs.modules.common
import qs.services
import qs.core
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Singleton {
    id: root

    // ------------------------------------------------------------- lock screen

    property bool screenLocked: false
    property bool screenLockContainsCharacters: false
    property bool screenUnlockFailed: false

    // ---------------------------------------------------------------- keyboard

    // Super held down: the bar shows workspace numbers while it is, and the launcher decides
    // whether releasing Super should open it.
    property bool superDown: false
    property bool superReleaseMightTrigger: true
    property bool workspaceShowNumbers: false

    // A desktop widget has taken the keyboard, so global keys must not act on it.
    property bool desktopWidgetKeyboardFocus: false

    // ----------------------------------------------------------------- settings

    // Which page the settings window is showing, and the page's instance for the search box to
    // talk to. Not a panel state - the panel is `PanelRegistry.state("settings")` - but *within*
    // that window, which page.
    property string settingsPage: ""
    property Item currentPageInstance: null

    // ---------------------------------------------------------------- hot corners

    // What a screen corner can do, built from the panel registry rather than a hardcoded list, so
    // a plugin's panel is assignable to a corner the moment it exists.
    readonly property var hotCornerOptions: {
        const options = [{ displayName: Translation.tr("None"), value: "none" }];
        for (const panel of PanelRegistry.all) {
            if (panel.persistent === true)
                continue;
            options.push({ displayName: panel.label ?? panel.id, value: panel.id });
        }
        return options;
    }

    // A corner's configured action. Accepts a panel id, and still understands the old
    // `somethingOpen` property names so an existing config keeps working.
    function toggleState(name) {
        if (!name || name === "none")
            return;
        PanelRegistry.toggle(root.panelIdFor(name), ({}));
    }

    // Configuration written before panels had ids stored things like "overviewOpen". Mapped here
    // rather than migrated in place, because a config file is the user's and rewriting it to suit
    // an internal rename is rude.
    readonly property var legacyStateNames: ({
        "overviewOpen": "overview",
        "sessionOpen": "sessionScreen",
        "oskOpen": "onScreenKeyboard",
        "mediaControlsOpen": "mediaControls",
        "wallpaperSelectorOpen": "wallpaperSelector",
        "dropShelfOpen": "dropover",
        "desktopMenuOpen": "desktopMenu",
        "regionSelectorOpen": "regionSelector",
        "screenTranslatorOpen": "screenTranslator",
        "overlayOpen": "overlay",
        "settingsOpen": "settings",
        "sidebarLeftOpen": "sidebarLeft",
        "sidebarRightOpen": "sidebarRight"
    })

    function panelIdFor(name) {
        return root.legacyStateNames[name] ?? name;
    }

    // ---------------------------------------------------------------------- bar

    // Kept here rather than as a panel state because it is not a window the user opens: the bar is
    // always there, and this is the flicker-free way to rebuild it after a layout change.
    property bool barOpen: true

    function refreshBar() {
        if (!root.barOpen)
            return;
        root.barOpen = false;
        barRefreshTimer.restart();
    }

    Timer {
        id: barRefreshTimer
        interval: 200
        repeat: false
        onTriggered: root.barOpen = true
    }

    // ------------------------------------------------------------------ wiring

    // Opening the right sidebar is how notifications are read, so it clears them.
    Connections {
        target: PanelRegistry.state("sidebarRight")
        function onOpenChanged(): void {
            if (!PanelRegistry.state("sidebarRight").open)
                return;
            Notifications.timeoutAll();
            Notifications.markAllRead();
        }
    }

    CompositorGlobalShortcut {
        name: "workspaceNumber"
        description: "Hold to show workspace numbers, release to show icons"
        onPressed: root.superDown = true
        onReleased: root.superDown = false
    }

    IpcHandler {
        target: "background"

        function toggleCenteredWallpaper(): void {
            Config.options.background.centeredWallpaper = !Config.options.background.centeredWallpaper;
        }
    }

    CompositorGlobalShortcut {
        name: "centeredWallpaperToggle"
        description: "Toggles centered wallpaper"
        onPressed: Config.options.background.centeredWallpaper = !Config.options.background.centeredWallpaper
    }
}
