pragma Singleton

// Whatever is playing, whichever player it is in.
//
//     PluginMedia.isPlaying
//     PluginMedia.title / .artist / .album / .artUrl
//     PluginMedia.positionSeconds / .lengthSeconds / .progress
//     PluginMedia.playPause() / .next() / .previous() / .seek(seconds)
//     PluginMedia.players            // [{ name, identity, isPlaying, select() }]
//
// MPRIS players lie in interesting ways - a browser advertises itself for every tab, a
// player reports a length of zero while loading, position only updates if you ask - and the
// shell's MprisController already deals with that. This is the plugin-facing shape of it:
// no nulls to check, `can*` flags for what the current player actually supports, and
// `progress` as a plain 0..1 so a bar is one binding.
//
// Position is polled while something is playing, because MPRIS does not push it. The poll
// stops when playback stops.

import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import qs.services
import qs.core

Singleton {
    id: root

    readonly property MprisPlayer player: MprisController.activePlayer
    readonly property bool available: !!root.player

    readonly property bool isPlaying: MprisController.isPlaying
    readonly property string title: root.player?.trackTitle ?? ""
    readonly property string artist: root.player?.trackArtist ?? ""
    readonly property string album: root.player?.trackAlbum ?? ""
    readonly property string artUrl: root.player?.trackArtUrl ?? ""
    readonly property string playerName: root.player?.identity ?? ""

    readonly property real lengthSeconds: (root.player?.length ?? 0) > 0 ? root.player.length : 0
    property real positionSeconds: 0

    // 0..1, clamped: a player that reports a position past its own length (they do) must not
    // push a progress bar out of its track.
    readonly property real progress: root.lengthSeconds > 0 ? Math.max(0, Math.min(1, root.positionSeconds / root.lengthSeconds)) : 0

    readonly property string positionFormatted: PluginUtils.formatDuration(root.positionSeconds)
    readonly property string lengthFormatted: root.lengthSeconds > 0 ? PluginUtils.formatDuration(root.lengthSeconds) : "--:--"

    readonly property bool canPlayPause: MprisController.canTogglePlaying
    readonly property bool canGoNext: MprisController.canGoNext
    readonly property bool canGoPrevious: MprisController.canGoPrevious
    readonly property bool canSeek: root.player?.canSeek ?? false
    readonly property bool canChangeVolume: MprisController.canChangeVolume

    readonly property real volume: root.player?.volume ?? 0
    readonly property bool shuffle: MprisController.hasShuffle
    readonly property bool shuffleSupported: MprisController.shuffleSupported
    readonly property var loopState: MprisController.loopState
    readonly property bool loopSupported: MprisController.loopSupported

    // Every real player, with a way to make one active.
    readonly property var players: MprisController.players.map(candidate => ({
        identity: candidate.identity,
        name: candidate.identity,
        isPlaying: candidate.isPlaying,
        title: candidate.trackTitle ?? "",
        artist: candidate.trackArtist ?? "",
        active: candidate === root.player,
        player: candidate,
        select: () => MprisController.setActivePlayer(candidate)
    }))

    // ----------------------------------------------------------------- control

    function playPause(): void { MprisController.togglePlaying(); }
    function next(): void { MprisController.next(); }
    function previous(): void { MprisController.previous(); }

    function play(): void {
        if (root.player && !root.isPlaying)
            MprisController.togglePlaying();
    }

    function pause(): void {
        if (root.player && root.isPlaying)
            MprisController.togglePlaying();
    }

    function pauseAll(): void {
        for (const candidate of MprisController.players) {
            if (candidate.isPlaying && candidate.canTogglePlaying)
                candidate.togglePlaying();
        }
    }

    function seek(seconds: real): void {
        if (root.canSeek && root.player)
            root.player.position = Math.max(0, Math.min(root.lengthSeconds, seconds));
    }

    // 0..1 of the track, for a click on a progress bar.
    function seekFraction(fraction: real): void {
        if (root.lengthSeconds > 0)
            root.seek(fraction * root.lengthSeconds);
    }

    function skip(seconds: real): void {
        root.seek(root.positionSeconds + seconds);
    }

    function setVolume(value: real): void {
        if (root.canChangeVolume && root.player)
            root.player.volume = Math.max(0, Math.min(1, value));
    }

    function setShuffle(enabled: bool): void { MprisController.setShuffle(enabled); }
    function setLoopState(state: var): void { MprisController.setLoopState(state); }

    function raise(): void {
        if (root.player?.canRaise)
            root.player.raise();
    }

    // ---------------------------------------------------------------- position

    // MPRIS position is a pull, not a push: nothing tells us it moved. Polling twice a
    // second is enough for a progress bar and stops the moment playback does.
    Timer {
        running: root.isPlaying && !!root.player
        interval: 500
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.player.positionChanged();
            root.positionSeconds = root.player.position;
        }
    }

    onPlayerChanged: root.positionSeconds = root.player?.position ?? 0
}
