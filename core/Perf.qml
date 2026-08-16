pragma Singleton
pragma ComponentBehavior: Bound

// Frame-stall profiler for the running shell.
//
// Everything else here can be measured in a probe, but a probe is not the shell: it has
// no settings window open, no compositor round trips for real layer-shell surfaces, and
// none of the GPU work of an actual frame. Two rounds of careful probe benchmarks said
// toggling a plugin cost 13ms, which did not match what the shell felt like - so the
// shell needs to be able to measure itself.
//
//     qs -c end4-pC ipc call perf start
//     ...do the thing that feels slow...
//     qs -c end4-pC ipc call perf report
//
// ## What it measures
//
// A timer set to fire every 8ms cannot fire on time if the UI thread is busy, so the
// gap between one tick and the next *is* the block, with no instrumentation of the code
// being measured. Gaps are bucketed rather than averaged: a mean hides exactly the
// hundred-millisecond outlier that a user notices, which is the only thing that matters.
//
// Off by default. The timer is cheap but not free, and something that samples the event
// loop has no business running in a shell nobody is profiling.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool running: false
    property string label: ""

    property real startedAt: 0
    property real lastBeat: 0

    property int ticks: 0
    property var gaps: []

    // Bucket edges in ms. 16 is one frame at 60Hz; past 100 the user calls it a hang.
    readonly property var buckets: [16, 33, 50, 100, 250, 500, 1000]

    function start(name: string) {
        root.label = name ?? "";
        root.ticks = 0;
        root.gaps = [];
        root.startedAt = Date.now();
        root.lastBeat = 0;
        root.running = true;
        heartbeat.start();
        console.log(`[perf] recording${root.label === "" ? "" : ` "${root.label}"`}`);
    }

    function stop() {
        root.running = false;
        heartbeat.stop();
    }

    function report(): string {
        const wall = Date.now() - root.startedAt;
        const counts = new Array(root.buckets.length + 1).fill(0);
        let worst = 0;
        let blocked = 0;

        for (const gap of root.gaps) {
            if (gap > worst)
                worst = gap;
            // Anything beyond the sampling interval is time the loop was not available.
            if (gap > 16)
                blocked += gap - 8;
            let placed = false;
            for (let i = 0; i < root.buckets.length; i++) {
                if (gap <= root.buckets[i]) {
                    counts[i]++;
                    placed = true;
                    break;
                }
            }
            if (!placed)
                counts[counts.length - 1]++;
        }

        const lines = [];
        lines.push(`[perf] ${root.label === "" ? "session" : root.label}: ${wall}ms wall, ${root.ticks} samples`);
        lines.push(`[perf] worst stall ${worst}ms, ~${Math.round(blocked)}ms blocked (${(100 * blocked / Math.max(1, wall)).toFixed(1)}% of wall)`);

        let previous = 0;
        for (let i = 0; i < root.buckets.length; i++) {
            if (counts[i] > 0)
                lines.push(`[perf]   ${previous}-${root.buckets[i]}ms: ${counts[i]}`);
            previous = root.buckets[i];
        }
        if (counts[counts.length - 1] > 0)
            lines.push(`[perf]   >${previous}ms: ${counts[counts.length - 1]}`);

        // The individual bad frames, which is what you actually chase.
        const bad = root.gaps.filter(gap => gap > 50).sort((a, b) => b - a).slice(0, 12);
        if (bad.length > 0)
            lines.push(`[perf]   stalls over 50ms: ${bad.join(", ")}`);

        const text = lines.join("\n");
        console.log(text);
        return text;
    }

    Timer {
        id: heartbeat
        interval: 8
        repeat: true
        running: false
        onTriggered: {
            const now = Date.now();
            if (root.lastBeat > 0)
                root.gaps.push(now - root.lastBeat);
            root.lastBeat = now;
            root.ticks++;
        }
    }

    IpcHandler {
        target: "perf"

        function start(label: string): string {
            root.start(label);
            return "recording";
        }

        function report(): string {
            return root.report();
        }

        function stop(): string {
            const text = root.report();
            root.stop();
            return text;
        }

        // Component cache state, since a cold cache is the usual reason something
        // loaded slowly.
        function cache(): string {
            const text = `[perf] warmed=${ComponentCache.warmed} failed=${ComponentCache.failed} queued=${ComponentCache.queue.length} primed=${ComponentCache.primed}`;
            console.log(text);
            return text;
        }

        // Identity-stability counters. Misses climbing while nothing is being installed
        // means a derived list is churning and rebuilding its consumers.
        function lists(): string {
            const text = `[perf] stable hits=${Stable.hits} misses=${Stable.misses}`;
            console.log(text);
            return text;
        }

        // Toggle a plugin from the command line, so a measurement does not depend on
        // clicking at the right moment.
        function plugin(id: string, enabled: bool): string {
            PluginRegistry.setEnabled(id, enabled);
            return `${id} -> ${enabled}`;
        }
    }
}
