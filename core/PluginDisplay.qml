pragma Singleton

// Screen brightness, gamma and night light.
//
//     PluginDisplay.brightness            // 0.0 .. 1.0 of the focused monitor
//     PluginDisplay.setBrightness(0.8)
//     PluginDisplay.step(+0.05)
//
//     PluginDisplay.nightLight.active
//     PluginDisplay.nightLight.temperature      // 4500 K
//     PluginDisplay.nightLight.setTemperature(3500)
//     PluginDisplay.nightLight.toggle()
//
//     PluginDisplay.monitors              // [{ name, brightness, isDdc, setBrightness(v) }]
//
// Brightness is per monitor and the mechanism differs - a laptop panel goes through
// backlight, an external one through DDC/CI over i2c, which is slow enough that it must not
// be animated. The shell's Brightness service already knows which is which; this exposes it
// per monitor with `isDdc` visible, because a plugin dragging a slider needs to know whether
// to throttle.
//
// `brightness` without a monitor argument means the focused one, which is what a keybind or
// an OSD means.

import QtQuick
import Quickshell
import qs.services
import qs.modules.common

Singleton {
    id: root

    // ------------------------------------------------------------ brightness

    readonly property var focusedMonitor: Brightness.getMonitorForScreen(Quickshell.screens.find(screen => screen.name === (WM.focusedMonitor?.name ?? "")) ?? Quickshell.screens[0] ?? null)

    readonly property real brightness: root.focusedMonitor?.brightness ?? 0
    readonly property bool available: !!root.focusedMonitor

    // [{ name, brightness, isDdc, ready, setBrightness(v), monitor }]
    readonly property var monitors: Brightness.monitors.map(monitor => ({
        name: monitor.screen?.name ?? "",
        brightness: monitor.brightness,
        isDdc: monitor.isDdc,
        ready: monitor.ready,
        monitor: monitor,
        setBrightness: value => monitor.setBrightness(Math.max(0, Math.min(1, value)))
    }))

    function setBrightness(value: real): void {
        root.focusedMonitor?.setBrightness(Math.max(0, Math.min(1, value)));
    }

    // Signed delta, clamped. `step(0.05)` is what a brightness-up key should do.
    function step(delta: real): void {
        if (!root.focusedMonitor)
            return;
        root.focusedMonitor.setBrightness(Math.max(0, Math.min(1, root.focusedMonitor.brightness + delta)));
    }

    function increase(): void {
        Brightness.increaseBrightness();
    }

    function decrease(): void {
        Brightness.decreaseBrightness();
    }

    function setBrightnessOn(monitorName: string, value: real): void {
        const found = root.monitors.find(entry => entry.name === monitorName);
        if (found)
            found.setBrightness(value);
    }

    // ------------------------------------------------------------ night light

    readonly property QtObject nightLight: QtObject {
        id: nightLightGroup

        readonly property bool active: Hyprsunset.temperatureActive
        readonly property bool automatic: Hyprsunset.automatic
        readonly property int temperature: Hyprsunset.colorTemperature
        readonly property string from: Hyprsunset.from
        readonly property string to: Hyprsunset.to

        // Kelvin. Clamped to a range that is actually usable - below 1000K the screen is
        // unreadable orange, above 20000K it is blue-white with no warming left to do.
        function setTemperature(kelvin: int): void {
            Config.options.light.night.colorTemperature = Math.max(1000, Math.min(20000, kelvin));
            if (nightLightGroup.active)
                Hyprsunset.enableTemperature();
        }

        function toggle(): void {
            Hyprsunset.toggleTemperature();
        }

        function enable(): void {
            Hyprsunset.enableTemperature();
        }

        function disable(): void {
            Hyprsunset.disableTemperature();
        }

        // Schedule, as "HH:mm" strings.
        function setSchedule(from: string, to: string): void {
            Config.options.light.night.from = from;
            Config.options.light.night.to = to;
        }

        function setAutomatic(enabled: bool): void {
            Config.options.light.night.automatic = enabled;
        }
    }

    // ------------------------------------------------------------------ gamma

    readonly property int gamma: Hyprsunset.gamma

    function setGamma(percent: int): void {
        Hyprsunset.setGamma(percent);
    }
}
