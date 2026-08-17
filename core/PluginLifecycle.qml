pragma Singleton

// When plugins should stop doing things.
//
// A GIF grid animating forty frames a second behind a lock screen, a weather widget
// polling an API while the session is idle, a chart repainting on a screen that is off -
// all of it costs battery and none of it is seen. This is the one place that knows the
// difference, so a plugin does not have to learn about lock screens, idle protocols and
// battery thresholds to be a good citizen.
//
// The whole contract for a plugin author is one property:
//
//     Timer { running: PluginLifecycle.awake && root.visible }
//     AnimatedImage { playing: PluginLifecycle.animate }
//
// `awake` is false while the screen is locked or the session is idle. `animate` is
// additionally false in power-saver mode, because animation is the first thing worth giving
// up and the last thing anyone misses.
//
// PluginTimer, PluginContentView and PluginSparkline already respect this, so a plugin
// built on those gets the contract without writing a line.
//
// ## Why both properties and signals
//
// A property covers "should I be running", which is most cases and is declarative - and a
// property's own change signal is the notification, so `onAwakeChanged` and
// `onPowerSaverChanged` work in a Connections block without this file declaring anything.
//
// The two explicit signals cover what a binding cannot express: releasing a decoded image
// cache, cancelling requests in flight, flushing state before the machine suspends. Both
// mechanisms, because each is wrong for the other's job.
//
// ## Idle comes from the compositor
//
// Through `ext-idle-notify`, the protocol the compositor already uses to drive hypridle -
// so "idle" here means exactly what it means to the rest of the session, including
// respecting idle inhibitors. A shell-side timer could not do that: it only sees input
// landing on the shell's own surfaces, so typing in a terminal for an hour would look idle.

import QtQuick
import Quickshell
import Quickshell.Wayland._IdleNotify
import qs
import qs.core
import qs.modules.common

Singleton {
    id: root

    // ------------------------------------------------------------------ state

    // The screen is locked. GlobalStates owns this; the lock screen sets it.
    readonly property bool locked: GlobalStates.screenLocked

    // No input for `idleSeconds`. Distinct from locked: an idle session may be unlocked with
    // the screen still on, where suspending a timer is right but tearing down state is not.
    readonly property bool idle: idleMonitor.isIdle

    // 0 disables idle suspension entirely.
    readonly property int idleSeconds: Config.options?.plugins?.idleSuspendSeconds ?? 180

    // Battery-saver: on battery and either below the threshold or explicitly asked for.
    readonly property bool powerSaver: root.forcePowerSaver
        || (PluginPower.hasBattery && !PluginPower.isPluggedIn
            && PluginPower.percent > 0
            && PluginPower.percent <= (Config.options?.plugins?.powerSaverPercent ?? 20))

    // For the settings GUI, and for exercising the contract without draining a battery.
    property bool forcePowerSaver: false

    // The two properties plugins bind to.
    readonly property bool awake: !root.locked && !root.idle
    readonly property bool animate: root.awake && !root.powerSaver

    // What to multiply a background poll interval by. A plugin polling every 30 s goes to
    // every 150 s in power-saver rather than stopping, because stale weather is better than
    // no weather. PluginTimer applies this for you.
    readonly property real pollFactor: root.powerSaver ? 5 : 1

    // ---------------------------------------------------------------- signals

    // Stop and release. Emitted on lock and on going idle.
    signal suspended();

    // Start again. Emitted on unlock and on activity.
    signal resumed();

    // The machine is about to sleep. Best effort by nature - the shell can be killed without
    // warning - which is why storage writes are coalesced in milliseconds rather than
    // deferred to here.
    signal aboutToSuspendSystem();

    IdleMonitor {
        id: idleMonitor

        enabled: root.idleSeconds > 0
        timeout: Math.max(15, root.idleSeconds)
        // An idle inhibitor is someone saying "do not treat this as idle" - a video player,
        // a long build. Ignoring it here would suspend plugins during exactly the sessions
        // the user is watching.
        respectInhibitors: true
    }

    property bool __wasAwake: true

    onAwakeChanged: {
        if (root.awake === root.__wasAwake)
            return;
        root.__wasAwake = root.awake;
        if (root.awake)
            root.resumed();
        else
            root.suspended();
    }

    // ---------------------------------------------------------------- system

    // Called by the shell's sleep hook.
    function notifySystemSuspend(): void {
        root.aboutToSuspendSystem();
        // Requests cannot survive a suspend, and their callbacks would land in a shell whose
        // idea of "now" is minutes old.
        PluginHttp.cancelAll();
    }

    // ------------------------------------------------------------ diagnostics

    function describe(): var {
        return {
            awake: root.awake,
            animate: root.animate,
            locked: root.locked,
            idle: root.idle,
            idleSeconds: root.idleSeconds,
            powerSaver: root.powerSaver,
            forcePowerSaver: root.forcePowerSaver,
            pollFactor: root.pollFactor
        };
    }
}
