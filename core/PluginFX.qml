pragma Singleton

// Effects support: what can be done on this machine, and the bits an effect needs to find.
//
// The three effect components (PluginBackdropBlur, PluginGlowBorder, PluginMeshGradient) are
// types, not singleton members, because in QML a singleton cannot expose a component you
// instantiate. This holds what they share: the wallpaper item a client-side blur samples, the
// compositor rule that does it properly, and the one switch that turns expensive drawing off.
//
//     PluginFX.effectsAllowed        // false in power-saver mode
//     PluginFX.blurRule(namespace)   // the Hyprland line for a real backdrop blur
//     PluginFX.wallpaperItem         // what a blur samples

import QtQuick
import Quickshell
import qs.core
import qs.modules.common

Singleton {
    id: root

    // Blur, mesh gradients and glow all cost GPU time every frame they change. In power-saver
    // mode they are the first thing to go, and effects bind to this rather than each deciding
    // for itself.
    readonly property bool effectsAllowed: PluginLifecycle.animate
        && (Config.options?.plugins?.effects ?? true)

    // What a client-side blur samples: the shell's own wallpaper.
    //
    // Registered by the background module rather than looked up, because there is no path from
    // here to it - the background is created per screen inside a Variants, and reaching into
    // that from a singleton would be exactly the kind of coupling this plugin API exists to
    // remove. Background.qml calls registerWallpaper() when it is built.
    property Item wallpaperItem: null

    function registerWallpaper(item: Item): void {
        root.wallpaperItem = item;
    }

    function unregisterWallpaper(item: Item): void {
        if (root.wallpaperItem === item)
            root.wallpaperItem = null;
    }

    // The compositor rule for a genuine backdrop blur of everything behind a surface, including
    // other applications - which no client-side effect can do. Printed by
    // `qs ipc call plugins fx` so it can be pasted into a Hyprland config.
    function blurRule(namespace: string): string {
        const name = String(namespace ?? "quickshell:pluginWindow");
        return `layerrule = blur, ${name}\nlayerrule = ignorealpha 0.2, ${name}`;
    }

    // Whether the compositor is one whose blur rules mean anything, so a plugin can offer the
    // hint only where it applies.
    readonly property bool compositorBlurAvailable: PluginWM.compositor === "hyprland"

    function describe(): var {
        return {
            effectsAllowed: root.effectsAllowed,
            sampling: root.wallpaperItem !== null,
            compositor: PluginWM.compositor,
            compositorBlurAvailable: root.compositorBlurAvailable
        };
    }
}
