// A subscription to the audio spectrum, which is what makes cava run.
//
//     PluginSpectrum { id: spectrum }
//
//     Repeater {
//         model: spectrum.points.length
//         Rectangle { height: spectrum.points[index] * 40 }
//     }
//
// Declaring one starts the analyser; destroying it (or toggling the plugin off, or the
// widget scrolling out of a Loader) stops it. That is the whole reason this type exists
// rather than a plain `PluginAudio.spectrum` read: a 60Hz DSP process should not outlive
// the thing drawing it.
//
// `points` is low frequency first, each 0..1. `bars` resamples to a different count when a
// widget wants fewer bars than cava produces - averaging, not dropping, so a quiet band
// between two loud ones cannot disappear.

import QtQuick
import qs.core

QtObject {
    id: root

    // Set to resample; 0 means "give me exactly what cava produces".
    property int bars: 0

    property bool active: true

    readonly property var points: {
        const raw = PluginAudio.spectrum;
        if (root.bars <= 0 || raw.length === 0 || raw.length === root.bars)
            return raw;
        const out = [];
        const ratio = raw.length / root.bars;
        for (let i = 0; i < root.bars; i++) {
            const from = Math.floor(i * ratio);
            const to = Math.max(from + 1, Math.floor((i + 1) * ratio));
            let sum = 0;
            for (let j = from; j < to && j < raw.length; j++)
                sum += raw[j];
            out.push(sum / (to - from));
        }
        return out;
    }

    // The loudest band, for a single-value meter.
    readonly property real peak: root.points.length === 0 ? 0 : Math.max(...root.points)

    readonly property real average: root.points.length === 0 ? 0 : root.points.reduce((sum, value) => sum + value, 0) / root.points.length

    readonly property bool running: PluginAudio.spectrumRunning

    property bool __acquired: false

    function __sync(): void {
        if (root.active && !root.__acquired) {
            PluginAudio.acquireSpectrum();
            root.__acquired = true;
        } else if (!root.active && root.__acquired) {
            PluginAudio.releaseSpectrum();
            root.__acquired = false;
        }
    }

    onActiveChanged: root.__sync()
    Component.onCompleted: root.__sync()
    Component.onDestruction: {
        if (root.__acquired) {
            PluginAudio.releaseSpectrum();
            root.__acquired = false;
        }
    }
}
