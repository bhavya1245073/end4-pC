pragma Singleton

// Time, without a Timer per idea.
//
//     const search = PluginTimer.debounce(text => run(text), 200)
//     onTextChanged: search(text)          // runs 200ms after typing stops
//
//     const save = PluginTimer.throttle(() => persist(), 1000)
//     onDragged: save()                    // at most once a second, first call immediate
//
//     PluginTimer.after(2500, () => hud.hide())
//     const handle = PluginTimer.every(60000, () => refresh())
//     handle.stop()
//
//     PluginTimer.cron("0 * * * *", () => hourly())      // minute hour dom month dow
//     PluginTimer.cron("*/15 * * * *", () => quarterly())
//     PluginTimer.at("07:30", () => goodMorning())
//
// Everything returns a handle with stop() and isRunning, and everything created here is
// owned by this singleton - so a widget that is destroyed mid-countdown does not take a
// live Timer with a dangling closure down with it. The counterpart is that a plugin which
// makes handles in a loop should keep and stop them; `PluginTimer.stats` shows how many
// are alive, and `plugins timers` prints it.
//
// Cron is evaluated once a minute against local time, on the minute, so a machine that
// was asleep does not replay every missed tick on wake - it picks up at the next minute
// boundary. Fields: minute, hour, day-of-month, month, day-of-week, each `*`, a number, a
// comma list, a range `a-b`, or a step `*/n`.

import QtQuick
import Quickshell

Singleton {
    id: root

    // Live handles, so a leak is visible instead of mysterious.
    property var __handles: ({})
    property int __nextId: 1

    readonly property var stats: {
        root.__revision;
        const kinds = ({});
        for (const id of Object.keys(root.__handles)) {
            const kind = root.__handles[id].kind;
            kinds[kind] = (kinds[kind] ?? 0) + 1;
        }
        return { alive: Object.keys(root.__handles).length, byKind: kinds };
    }

    property int __revision: 0

    // ------------------------------------------------------------- one-shot

    // Runs `callback` once after `delayMs`. Returns a handle; stop() cancels it.
    function after(delayMs: int, callback: var): var {
        return root.__make("after", delayMs, false, callback);
    }

    // Runs on the next event loop turn - the way to escape "cannot assign during binding
    // evaluation" without inventing a Timer with interval 0.
    function next(callback: var): var {
        return root.__make("next", 0, false, callback);
    }

    // ------------------------------------------------------------- repeating

    function every(intervalMs: int, callback: var): var {
        return root.__make("every", intervalMs, true, callback);
    }

    // ------------------------------------------------------------- debounce

    // Returns a function. Calling it (re)starts the wait; the callback runs `waitMs` after
    // the last call, with the arguments of that last call.
    function debounce(callback: var, waitMs: int): var {
        const handle = root.__make("debounce", waitMs, false, null);
        handle.stop();
        return function () {
            const args = Array.prototype.slice.call(arguments);
            handle.callback = () => callback.apply(null, args);
            handle.restart();
        };
    }

    // First call runs immediately, then at most one call per `waitMs`. A trailing call is
    // kept and runs at the end of the window, so the last value is never dropped.
    function throttle(callback: var, waitMs: int): var {
        let last = 0;
        let pending = null;
        const handle = root.__make("throttle", waitMs, false, null);
        handle.stop();
        handle.callback = () => {
            if (pending === null)
                return;
            const args = pending;
            pending = null;
            last = Date.now();
            callback.apply(null, args);
        };
        return function () {
            const args = Array.prototype.slice.call(arguments);
            const now = Date.now();
            if (now - last >= waitMs) {
                last = now;
                pending = null;
                callback.apply(null, args);
                return;
            }
            pending = args;
            if (!handle.isRunning)
                handle.startFor(waitMs - (now - last));
        };
    }

    // ------------------------------------------------------------------ cron

    // Minute-resolution schedule. Returns a handle.
    function cron(expression: string, callback: var): var {
        const fields = root.__parseCron(expression);
        if (!fields) {
            console.warn(`[timer] not a cron expression: "${expression}"`);
            return root.__deadHandle();
        }
        const handle = root.__make("cron", 60000, true, null);
        handle.cron = expression;
        handle.callback = () => {
            const now = new Date();
            if (root.__cronMatches(fields, now))
                callback(now);
        };
        // Line up with the next minute boundary, then tick once a minute. Without this a
        // cron created at :30 would fire at :30 of every following minute and could miss a
        // minute entirely across a suspend.
        handle.alignToMinute();
        return handle;
    }

    // "07:30" or "7:30" local time, daily.
    function at(timeOfDay: string, callback: var): var {
        const parts = `${timeOfDay}`.split(":");
        const hour = parseInt(parts[0]);
        const minute = parseInt(parts[1] ?? "0");
        if (isNaN(hour) || isNaN(minute) || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
            console.warn(`[timer] not a time of day: "${timeOfDay}"`);
            return root.__deadHandle();
        }
        return root.cron(`${minute} ${hour} * * *`, callback);
    }

    function __parseCron(expression: string): var {
        const parts = `${expression ?? ""}`.trim().split(/\s+/);
        if (parts.length !== 5)
            return null;
        const ranges = [[0, 59], [0, 23], [1, 31], [1, 12], [0, 6]];
        const fields = [];
        for (let i = 0; i < 5; i++) {
            const set = root.__parseCronField(parts[i], ranges[i][0], ranges[i][1]);
            if (!set)
                return null;
            fields.push(set);
        }
        return fields;
    }

    // Returns null for anything unparseable, so a typo is reported rather than matching
    // everything - a cron that silently runs every minute is worse than one that does not
    // run at all.
    function __parseCronField(field: string, min: int, max: int): var {
        const values = [];
        for (const piece of `${field}`.split(",")) {
            const step = piece.split("/");
            const base = step[0];
            const stride = step.length > 1 ? parseInt(step[1]) : 1;
            if (step.length > 2 || isNaN(stride) || stride < 1)
                return null;

            let from;
            let to;
            if (base === "*") {
                from = min;
                to = max;
            } else if (base.includes("-")) {
                const bounds = base.split("-");
                from = parseInt(bounds[0]);
                to = parseInt(bounds[1]);
            } else {
                from = parseInt(base);
                to = from;
            }
            if (isNaN(from) || isNaN(to) || from < min || to > max || from > to)
                return null;
            for (let value = from; value <= to; value += stride)
                values.push(value);
        }
        return values;
    }

    function __cronMatches(fields: var, when: var): bool {
        return fields[0].includes(when.getMinutes())
            && fields[1].includes(when.getHours())
            && fields[2].includes(when.getDate())
            && fields[3].includes(when.getMonth() + 1)
            && fields[4].includes(when.getDay());
    }

    // -------------------------------------------------------------- internals

    function __make(kind: string, intervalMs: int, repeating: bool, callback: var): var {
        const id = root.__nextId++;
        const handle = handleComponent.createObject(root, {
            id_: id,
            kind: kind,
            interval: Math.max(0, intervalMs),
            repeating: repeating,
            callback: callback
        });
        root.__handles[id] = handle;
        root.__revision += 1;
        handle.released.connect(() => {
            delete root.__handles[id];
            root.__revision += 1;
        });
        if (callback !== null)
            handle.restart();
        return handle;
    }

    // A handle that does nothing, so a caller can always call stop() on what it got back
    // without checking for null first.
    function __deadHandle(): var {
        return handleComponent.createObject(root, { id_: 0, kind: "dead", interval: 0, repeating: false, callback: null });
    }

    // Stops and forgets everything. Used by `plugins reload`, where every plugin's
    // closures are about to become stale.
    function stopAll(): int {
        const ids = Object.keys(root.__handles);
        for (const id of ids)
            root.__handles[id].release();
        return ids.length;
    }

    readonly property Component handleComponent: Component {
        QtObject {
            id: handle

            property int id_: 0
            property string kind: ""
            property int interval: 0
            property bool repeating: false
            property var callback: null
            property string cron: ""

            readonly property bool isRunning: timer.running

            signal released

            function restart(): void {
                timer.interval = handle.interval;
                timer.repeat = handle.repeating;
                timer.restart();
            }

            // One-off wait different from `interval`, for throttle's trailing call.
            function startFor(delayMs: int): void {
                timer.interval = Math.max(0, delayMs);
                timer.repeat = false;
                timer.restart();
            }

            function stop(): void {
                timer.stop();
            }

            // Stop and drop out of the live-handle table. A handle that is released cannot
            // be restarted; make a new one.
            function release(): void {
                timer.stop();
                handle.callback = null;
                handle.released();
                handle.destroy();
            }

            // First tick on the next minute boundary, then every minute.
            function alignToMinute(): void {
                const now = new Date();
                timer.interval = Math.max(250, (60 - now.getSeconds()) * 1000 - now.getMilliseconds());
                timer.repeat = false;
                timer.restart();
            }

            readonly property Timer __timer: Timer {
                id: timer
                onTriggered: {
                    // A cron handle's first tick is the alignment one; from then on it
                    // repeats every minute.
                    if (handle.kind === "cron" && !timer.repeat) {
                        timer.interval = 60000;
                        timer.repeat = true;
                        timer.restart();
                    }
                    const fire = handle.callback;
                    if (typeof fire !== "function")
                        return;
                    try {
                        fire();
                    } catch (error) {
                        console.warn(`[timer] ${handle.kind} callback threw:`, error.message ?? error);
                    }
                    // A one-shot has done its job; drop it so `stats` stays honest.
                    if (!timer.repeat && handle.kind !== "debounce" && handle.kind !== "throttle" && handle.kind !== "cron")
                        handle.release();
                }
            }
        }
    }
}
