pragma Singleton

// Is anything using the microphone, the camera, or the screen right now.
//
//     PluginPrivacy.micInUse
//     PluginPrivacy.cameraInUse
//     PluginPrivacy.screenSharing
//     PluginPrivacy.micApps            // [{ name, id }]
//     PluginPrivacy.anyActive
//
// Microphone and screen capture come from PipeWire: a program that records is linked to a
// source, and that link is observable. The camera is not a PipeWire node when an application
// opens /dev/video* directly (most do), so it is detected by asking the kernel who has the
// device open - which is what `fuser` does, and it needs no privileges for your own
// processes.
//
// The shell's Privacy service assigns arrays to `bool` properties, which QML coerces to
// `true` for any array including an empty one - so it reads "microphone in use" forever. This
// is the corrected implementation and the reason plugins should use this facade instead.

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.core

Singleton {
    id: root

    // ---------------------------------------------------------------- pipewire

    // Every link group whose source is a capture device and whose target is an application.
    readonly property var __micLinks: Pipewire.linkGroups.values.filter(group =>
        group.source?.type === PwNodeType.AudioSource && group.target?.type === PwNodeType.AudioInStream)

    readonly property var __screenLinks: Pipewire.linkGroups.values.filter(group =>
        group.source?.type === PwNodeType.VideoSource)

    readonly property bool micInUse: root.__micLinks.length > 0
    readonly property bool screenSharing: root.__screenLinks.length > 0

    // [{ name, id }] - who is listening, so an indicator can name it.
    readonly property var micApps: root.__micLinks.map(group => ({
        name: root.__appName(group.target),
        id: group.target?.id ?? 0
    }))

    readonly property var screenApps: root.__screenLinks.map(group => ({
        name: root.__appName(group.target),
        id: group.target?.id ?? 0
    }))

    function __appName(node: var): string {
        if (!node)
            return "";
        return node.properties?.["application.name"]
            ?? node.properties?.["node.name"]
            ?? node.description
            ?? node.name
            ?? "";
    }

    // ------------------------------------------------------------------ camera

    // /dev/video* is opened directly by most applications, so PipeWire cannot see it, and
    // the kernel exposes no "in use" flag for a V4L2 device. Asking which processes hold the
    // device open is the only reliable answer, and `fuser` is what does that without
    // privileges for your own processes.
    //
    // When fuser is missing the camera indicator stays off rather than guessing, and says so
    // once. `cameraDetectable` lets a widget hide the indicator instead of showing a
    // permanent "off" that means "unknown".
    property bool cameraInUse: false
    property var cameraApps: []
    property bool cameraDetectable: true
    readonly property bool cameraAvailable: root.__cameraDevices.length > 0
    property var __cameraDevices: []

    function refreshCamera(): void {
        if (root.__cameraDevices.length === 0 || !root.cameraDetectable) {
            root.cameraInUse = false;
            root.cameraApps = [];
            return;
        }
        // fuser prints pids on stderr and the device name on stdout; -a keeps the device in
        // the output even when nothing has it open. Exit status 1 means "nobody", which is
        // the common case and not an error.
        PluginUtils.run(["fuser", "-a"].concat(root.__cameraDevices), (stdout, code, stderr) => {
            const output = `${stderr ?? ""}${stdout ?? ""}`;
            if (code !== 0 && code !== 1 && output.trim().length === 0) {
                root.cameraDetectable = false;
                console.log("[privacy] fuser is not available, so camera use cannot be detected");
                return;
            }
            // Strip the device names before looking for pids: "/dev/video0:" contains a 0.
            const pids = (output.replace(/\/dev\/\S+/g, " ").match(/\b\d+\b/g) ?? []).filter(pid => pid !== "0");
            if (pids.length === 0) {
                root.cameraInUse = false;
                root.cameraApps = [];
                return;
            }
            const apps = [];
            for (const pid of pids) {
                const name = PluginFs.readSync(`/proc/${pid}/comm`).trim();
                if (name.length > 0 && !apps.some(entry => entry.name === name))
                    apps.push({ name: name, id: parseInt(pid) });
            }
            root.cameraApps = apps;
            root.cameraInUse = apps.length > 0;
        });
    }

    // Cameras are discovered through /sys/class/video4linux rather than by listing /dev:
    // FolderListModel lists regular files, and a character device is not one, so /dev/video0
    // is invisible to it. sysfs also gives the human-readable name for free.
    function __discoverCameras(): void {
        PluginFs.list("/sys/class/video4linux", result => {
            if (!result.ok)
                return;
            const devices = [];
            const names = [];
            for (const entry of result.entries) {
                if (!/^video\d+$/.test(entry.name))
                    continue;
                // A UVC camera exposes extra metadata nodes that are never "in use" in the
                // way a user means. They are kept anyway: any holder of any node of the
                // camera counts as the camera being on, and telling capture nodes from
                // metadata nodes needs a VIDIOC_QUERYCAP ioctl QML cannot make.
                devices.push(`/dev/${entry.name}`);
                names.push(PluginFs.readSync(`/sys/class/video4linux/${entry.name}/name`).trim());
            }
            root.__cameraDevices = devices;
            root.cameraNames = names.filter(name => name.length > 0);
            root.refreshCamera();
        });
    }

    // What the cameras call themselves, for a tooltip.
    property var cameraNames: []

    // ----------------------------------------------------------------- summary

    readonly property bool anyActive: root.micInUse || root.cameraInUse || root.screenSharing

    // What to show in a single pill, most alarming first.
    readonly property string icon: root.screenSharing ? "screen_share" : root.cameraInUse ? "videocam" : root.micInUse ? "mic" : ""

    readonly property string summary: {
        const parts = [];
        if (root.screenSharing)
            parts.push("screen");
        if (root.cameraInUse)
            parts.push("camera");
        if (root.micInUse)
            parts.push("microphone");
        return parts.join(", ");
    }

    Component.onCompleted: root.__discoverCameras()

    // A camera open is a poll, not a signal. Two seconds is fast enough for an indicator and
    // costs one short-lived process; nothing runs when the machine has no camera.
    Timer {
        interval: 2000
        running: root.__cameraDevices.length > 0 && root.cameraDetectable
        repeat: true
        onTriggered: root.refreshCamera()
    }

    // Publishing on the bus means a plugin can react to the camera turning on without polling
    // anything itself.
    onAnyActiveChanged: PluginBus.publish("privacy:active", {
        mic: root.micInUse,
        camera: root.cameraInUse,
        screen: root.screenSharing
    })
}
