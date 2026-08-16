pragma Singleton

// Volume, per-app streams, and the audio spectrum.
//
//     PluginAudio.volume                 // 0.0 .. 1.0 of the default sink (can exceed 1)
//     PluginAudio.setVolume(0.75)
//     PluginAudio.toggleMute()
//     PluginAudio.apps                   // [{ name, icon, volume, muted, setVolume(v), ... }]
//     PluginAudio.inputs / .outputs      // devices, with select()
//
//     PluginSpectrum { id: spectrum }    // then bind to spectrum.points
//
// Volume is normalised to 0..1 where 1 is 100%, with `maxVolume` for the overdrive range
// the shell allows. Per-app entries are plain objects with a setVolume function, so a
// mixer row does not need to know what a PwNode is.
//
// The spectrum is a real FFT from cava, and cava only runs while something is actually
// drawing it: PluginSpectrum acquires on creation and releases on destruction, and the
// process stops when the count hits zero or when there is nothing playing. Reading
// `PluginAudio.spectrum` without acquiring gives an empty list rather than silently
// starting a DSP process for a binding that may never be shown.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.services
import qs.modules.common

Singleton {
    id: root

    // ---------------------------------------------------------------- master

    readonly property bool ready: Audio.ready
    readonly property PwNode sink: Audio.sink
    readonly property PwNode source: Audio.source

    readonly property real volume: Audio.sink?.audio.volume ?? 0
    readonly property bool muted: Audio.sink?.audio.muted ?? false
    readonly property real maxVolume: Audio.hardMaxValue

    readonly property real inputVolume: Audio.source?.audio.volume ?? 0
    readonly property bool inputMuted: Audio.source?.audio.muted ?? false

    readonly property string sinkName: Audio.sink ? Audio.friendlyDeviceName(Audio.sink) : ""
    readonly property string sourceName: Audio.source ? Audio.friendlyDeviceName(Audio.source) : ""

    // Clamped to the shell's own maximum, so a plugin cannot set 500% by accident.
    function setVolume(value: real): void {
        if (!Audio.sink?.audio)
            return;
        Audio.sink.audio.muted = false;
        Audio.sink.audio.volume = Math.max(0, Math.min(root.maxVolume, value));
    }

    function changeVolume(delta: real): void {
        root.setVolume(root.volume + delta);
    }

    function setMuted(muted: bool): void {
        if (Audio.sink?.audio)
            Audio.sink.audio.muted = muted;
    }

    function toggleMute(): void {
        Audio.toggleMute();
    }

    function setInputVolume(value: real): void {
        if (!Audio.source?.audio)
            return;
        Audio.source.audio.volume = Math.max(0, Math.min(root.maxVolume, value));
    }

    function toggleInputMute(): void {
        Audio.toggleMicMute();
    }

    function playSound(name: string): void {
        Audio.playSystemSound(name);
    }

    // ------------------------------------------------------------- per-app

    // One entry per playing application. Plain objects: a mixer row binds to
    // `entry.volume` and calls `entry.setVolume(v)` without importing Pipewire.
    readonly property var apps: root.__streams(Audio.outputAppNodes)
    readonly property var recorders: root.__streams(Audio.inputAppNodes)

    function __streams(nodes: var): var {
        return (nodes ?? []).filter(node => !!node?.audio).map(node => ({
            id: node.id,
            name: Audio.appNodeDisplayName(node),
            icon: AppSearch.guessIcon(node.properties?.["application.name"] ?? node.name ?? ""),
            volume: node.audio.volume,
            muted: node.audio.muted,
            node: node,
            setVolume: value => { node.audio.volume = Math.max(0, Math.min(root.maxVolume, value)); },
            setMuted: value => { node.audio.muted = value; },
            toggleMute: () => { node.audio.muted = !node.audio.muted; }
        }));
    }

    // -------------------------------------------------------------- devices

    readonly property var outputs: root.__devices(Audio.outputDevices, true)
    readonly property var inputs: root.__devices(Audio.inputDevices, false)

    function __devices(nodes: var, isSink: bool): var {
        const current = isSink ? Audio.sink : Audio.source;
        return (nodes ?? []).map(node => ({
            id: node.id,
            name: Audio.friendlyDeviceName(node),
            active: node === current,
            node: node,
            select: () => isSink ? Audio.setDefaultSink(node) : Audio.setDefaultSource(node)
        }));
    }

    // ------------------------------------------------------------- spectrum

    // Latest magnitudes, 0..1, low frequencies first. Empty while nothing is subscribed.
    property var spectrum: []

    readonly property int bands: 50

    // How many PluginSpectrum instances are alive. cava is a real process doing real DSP;
    // it runs when at least one is, and not otherwise.
    property int spectrumSubscribers: 0

    readonly property bool spectrumRunning: cavaProcess.running

    function acquireSpectrum(): void {
        root.spectrumSubscribers += 1;
    }

    function releaseSpectrum(): void {
        root.spectrumSubscribers = Math.max(0, root.spectrumSubscribers - 1);
        if (root.spectrumSubscribers === 0)
            root.spectrum = [];
    }

    Process {
        id: cavaProcess
        // Nothing playing means a flat line, so there is no reason to keep a DSP process
        // and a 60Hz stdout stream alive for it.
        running: root.spectrumSubscribers > 0 && MprisController.activePlayer !== null
        command: ["cava", "-p", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/cava/raw_output_config.txt`]
        onRunningChanged: {
            if (!cavaProcess.running)
                root.spectrum = [];
        }
        stdout: SplitParser {
            onRead: data => {
                const points = data.split(";").map(value => parseFloat(value.trim())).filter(value => !isNaN(value));
                if (points.length > 0)
                    root.spectrum = points;
            }
        }
    }
}
