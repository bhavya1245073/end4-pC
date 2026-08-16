pragma Singleton

// Power actions, battery, and sleep inhibitors.
//
//     PluginPower.lock()
//     PluginPower.suspend()
//     PluginPower.percent            // 84
//     PluginPower.isCharging         // true
//     PluginPower.timeRemaining      // "2h 14m", or "" when unknown
//
//     const token = PluginPower.inhibit("Playing a video")
//     PluginPower.release(token)
//
// Inhibitors are real: each one is a `systemd-inhibit … sleep infinity` process, so the
// block is visible to `systemd-inhibit --list` and to anything else on the system, and it
// disappears if the shell dies rather than wedging the machine awake. Wayland idle
// inhibition (screen blanking) is separate and handled by `inhibitIdle`, because wanting
// the screen to stay on is not the same as wanting the machine to stay awake.
//
// Every destructive action asks for confirmation only if the caller does - this facade does
// what it is told.

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common.functions

Singleton {
    id: root

    // ------------------------------------------------------------- battery

    readonly property bool hasBattery: Battery.available
    readonly property real percent: Battery.percentage * 100
    readonly property bool isCharging: Battery.isCharging
    readonly property bool isLow: Battery.isLow
    readonly property bool isCritical: Battery.isCritical
    readonly property bool isPluggedIn: Battery.isPluggedIn

    // Watts, positive while discharging and negative while charging is how UPower reports
    // it; the sign is kept because a widget showing "drawing 12W" wants to know.
    readonly property real powerWatts: Battery.energyRate
    readonly property real healthPercent: Battery.health
    readonly property int chargeCycles: Battery.chargeCycles

    // "2h 14m" while discharging, "1h 05m to full" while charging, "" when the estimate is
    // not available yet - which it is not for the first minute or so after plugging in.
    readonly property string timeRemaining: {
        const seconds = root.isCharging ? Battery.timeToFull : Battery.timeToEmpty;
        if (!(seconds > 0))
            return "";
        const formatted = PluginUtils.formatDuration(seconds);
        return root.isCharging ? `${formatted} to full` : formatted;
    }

    // ------------------------------------------------------------- actions

    function lock(): void {
        Session.lock();
    }

    function suspend(): void {
        Session.suspend();
    }

    function hibernate(): void {
        Session.hibernate();
    }

    function reboot(): void {
        Session.reboot();
    }

    function rebootToFirmware(): void {
        Session.rebootToFirmware();
    }

    function powerOff(): void {
        Session.poweroff();
    }

    function logout(): void {
        Session.logout();
    }

    // ------------------------------------------------------------ inhibitors

    // token -> { id, reason, what, process }
    property var __inhibitors: ({})
    property int __nextToken: 1

    readonly property bool inhibited: Object.keys(root.__inhibitors).length > 0

    // [{ token, reason, what }] - so a status widget can say *why* the machine will not
    // sleep, which is the whole point of having a list.
    readonly property var inhibitors: {
        root.__revision;
        return Object.keys(root.__inhibitors).map(token => ({
            token: parseInt(token),
            reason: root.__inhibitors[token].reason,
            what: root.__inhibitors[token].what
        }));
    }

    property int __revision: 0

    // `what` follows systemd's vocabulary: any of sleep, idle, shutdown, handle-lid-switch,
    // colon separated. The default blocks suspend and idle, which is what "keep going" means
    // for a download or a presentation.
    function inhibit(reason: string, what: string): int {
        const token = root.__nextToken++;
        const kinds = what && what.length > 0 ? what : "sleep:idle";
        const process = inhibitorComponent.createObject(root, {
            reason: reason ?? "plugin request",
            what: kinds
        });
        root.__inhibitors[token] = { reason: reason ?? "plugin request", what: kinds, process: process };
        root.__revision += 1;
        return token;
    }

    function release(token: int): bool {
        const entry = root.__inhibitors[token];
        if (!entry)
            return false;
        entry.process.destroy();
        delete root.__inhibitors[token];
        root.__revision += 1;
        return true;
    }

    function releaseAll(): int {
        const tokens = Object.keys(root.__inhibitors);
        for (const token of tokens)
            root.release(parseInt(token));
        return tokens.length;
    }

    // Screen blanking, through the compositor rather than systemd.
    property alias inhibitIdle: root.__idleAlias
    property bool __idleAlias: Idle.inhibit
    onInhibitIdleChanged: Idle.toggleInhibit(root.inhibitIdle)

    readonly property Component inhibitorComponent: Component {
        QtObject {
            id: holder
            property string reason: ""
            property string what: ""

            // `sleep infinity` for as long as this object lives. systemd holds the lock
            // while the child runs, and drops it the moment the process goes away - which
            // includes the shell being killed, so a crash cannot leave the machine unable
            // to suspend.
            readonly property Process __process: Process {
                running: true
                command: ["systemd-inhibit", `--what=${holder.what}`, "--who=end4-pC", `--why=${holder.reason}`, "--mode=block", "sleep", "infinity"]
            }
        }
    }
}
