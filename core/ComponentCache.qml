pragma Singleton
pragma ComponentBehavior: Bound

// Compiles QML off the critical path, so that loading something never means compiling it.
//
// ## What this is actually for
//
// Setting `Loader.source` does two things: it compiles the file (and everything it
// imports, transitively, unless already compiled) and then it instantiates it. The
// second is usually small. The first is not, and it is the part that lands on the UI
// thread the moment a user flips a switch or opens a panel for the first time.
//
// `Qt.createComponent(url, Component.Asynchronous)` does the compile on Qt's loader
// thread, and the result is cached by the engine per URL. So compiling a file here in
// advance means a later `Loader.source = url` finds the compiled unit already in the
// engine's type cache and only pays instantiation - which is the difference between a
// toggle that stutters and one that does not.
//
// The compiled Components are kept alive in `cache`, both so the engine cannot evict
// the entry and so callers can skip URL resolution entirely by using them directly.
//
// ## Why it is a queue and not a loop
//
// Warming everything at once is just moving the stall to startup. One file per pass
// with a timer between passes means the work lands in the gaps between frames. The
// queue is ordered: things the user can reach without opening anything (bar widgets,
// desktop widgets) come before things behind a click (quick toggles, settings pages).

import QtQuick
import QtQml
import Quickshell

Singleton {
    id: root

    // url -> Component, for everything compiled so far.
    property var cache: ({})

    // Urls queued but not yet compiled, and the one in flight.
    property var queue: []
    property string inFlight: ""

    // Counters, read by the settings GUI and the benchmark harness.
    property int warmed: 0
    property int failed: 0

    // Not a binding. `queue` is mutated in place by push and shift, and mutating the
    // array a `var` property holds emits nothing - so a `readonly property bool idle`
    // bound to `queue.length === 0` was evaluated once, while the queue was still empty,
    // and stayed true forever. The pump read it on its first tick and stopped, which is
    // how this cache spent a whole benchmark run reporting warmed=0 with 84 queued.
    function isIdle(): bool {
        return root.queue.length === 0 && root.inFlight === "";
    }

    // True once the first warming pass has drained. Until then a caller that wants a
    // component right now should expect a miss and load by URL as usual.
    property bool primed: false

    // ------------------------------------------------------------------- public

    // The compiled component for a url, or null if it has not been warmed yet. A caller
    // that gets null should fall back to loading by URL; it will still work, it just
    // pays the compile itself.
    function get(url: string): var {
        return root.cache[url] ?? null;
    }

    function isWarm(url: string): bool {
        return root.cache[url] !== undefined;
    }

    // Queue a url for compilation. Cheap and idempotent: already-warm and already-queued
    // urls are dropped.
    function warm(url: string) {
        if (!url || root.cache[url] !== undefined || root.inFlight === url)
            return;
        if (root.queue.includes(url))
            return;
        root.queue.push(url);
        pump.start();
    }

    // Queue a url ahead of everything else, for when the user has just done something
    // that means they are about to need it.
    function warmNow(url: string) {
        if (!url || root.cache[url] !== undefined || root.inFlight === url)
            return;
        const at = root.queue.indexOf(url);
        if (at >= 0)
            root.queue.splice(at, 1);
        root.queue.unshift(url);
        pump.start();
    }

    function warmAll(urls: var) {
        for (const url of urls)
            root.warm(url);
    }

    // Compile a url right now, on this thread, and cache it. For the case where the
    // alternative is showing nothing: paying the compile is better than a blank frame.
    function warmBlocking(url: string): var {
        const hit = root.cache[url];
        if (hit !== undefined)
            return hit;
        const component = Qt.createComponent(url, Component.PreferSynchronous);
        if (component.status === Component.Ready) {
            root.remember(url, component);
            return component;
        }
        if (component.status === Component.Error)
            console.warn(`[warm] ${url}: ${component.errorString()}`);
        return null;
    }

    // ----------------------------------------------------------------- internals

    function remember(url: string, component: var) {
        const next = Object.assign({}, root.cache);
        next[url] = component;
        root.cache = next;
        root.warmed++;
    }

    function step() {
        if (root.inFlight !== "" || root.queue.length === 0) {
            if (root.isIdle())
                root.primed = true;
            return;
        }

        const url = root.queue.shift();
        if (root.cache[url] !== undefined) {
            pump.restart();
            return;
        }

        root.inFlight = url;
        const component = Qt.createComponent(url, Component.Asynchronous);

        const settle = () => {
            if (component.status === Component.Loading)
                return;
            if (component.status === Component.Ready) {
                root.remember(url, component);
            } else {
                root.failed++;
                // Not a warning: plenty of files are only loadable with properties
                // injected by their host, and failing to *pre*compile one costs nothing
                // but the optimisation. The real load reports its own errors.
                console.debug(`[warm] skipped ${url}: ${component.errorString().trim()}`);
            }
            root.inFlight = "";
            pump.restart();
        };

        if (component.status === Component.Loading)
            component.statusChanged.connect(settle);
        else
            settle();
    }

    // One file per tick. The interval is short enough to drain twenty-odd files in well
    // under a second of wall clock, and long enough that each compile's instantiation
    // work has a frame to itself.
    Timer {
        id: pump
        interval: 16
        repeat: true
        running: false
        onTriggered: {
            if (root.isIdle()) {
                root.primed = true;
                this.stop();
                return;
            }
            root.step();
        }
    }
}
