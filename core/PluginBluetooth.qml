pragma Singleton

// Bluetooth adapters and devices.
//
//     PluginBluetooth.available          // is there an adapter at all
//     PluginBluetooth.enabled
//     PluginBluetooth.toggle()
//     PluginBluetooth.devices            // [{ name, address, connected, paired, batteryPercent,
//                                        //    kind, connect(), disconnect(), forget() }]
//     PluginBluetooth.connectedDevices
//     PluginBluetooth.scanning
//     PluginBluetooth.scan(true)
//
// `kind` is derived from the device's Bluetooth class so a list can show a headphone icon for
// headphones without every plugin re-deriving it: "audio", "input", "phone", "computer",
// "watch", "display" or "other".
//
// `batteryPercent` is -1 when the device does not report battery, which most do not.

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.services

Singleton {
    id: root

    readonly property bool available: BluetoothStatus.available
    readonly property bool enabled: BluetoothStatus.enabled
    readonly property bool connected: BluetoothStatus.connected
    readonly property int connectedCount: BluetoothStatus.activeDeviceCount
    readonly property bool scanning: Bluetooth.defaultAdapter?.discovering ?? false
    readonly property string adapterName: Bluetooth.defaultAdapter?.name ?? ""

    readonly property var devices: BluetoothStatus.friendlyDeviceList.map(device => root.__shape(device))
    readonly property var connectedDevices: BluetoothStatus.connectedDevices.map(device => root.__shape(device))
    readonly property var pairedDevices: BluetoothStatus.pairedButNotConnectedDevices.map(device => root.__shape(device))

    // The one a media widget should show: the first connected audio device, or just the first
    // connected device.
    readonly property var primaryDevice: root.connectedDevices.find(device => device.kind === "audio") ?? root.connectedDevices[0] ?? null

    function __shape(device: var): var {
        return {
            name: device.name,
            address: device.address,
            connected: device.connected,
            paired: device.paired,
            trusted: device.trusted,
            blocked: device.blocked,
            batteryPercent: (device.batteryAvailable ?? false) ? Math.round((device.battery ?? 0) * 100) : -1,
            kind: root.__kindOf(device),
            icon: root.__iconOf(device),
            device: device,
            connect: () => device.connect(),
            disconnect: () => device.disconnect(),
            forget: () => device.forget(),
            toggle: () => device.connected ? device.disconnect() : device.connect()
        };
    }

    // Bluetooth's own icon name is the most reliable signal here - the class-of-device bits
    // are often wrong on cheap hardware, but the freedesktop icon name is what the device
    // itself claims to be.
    function __kindOf(device: var): string {
        const icon = `${device.icon ?? ""}`.toLowerCase();
        if (icon.includes("headset") || icon.includes("headphone") || icon.includes("audio") || icon.includes("speaker"))
            return "audio";
        if (icon.includes("keyboard") || icon.includes("mouse") || icon.includes("input") || icon.includes("gaming"))
            return "input";
        if (icon.includes("phone"))
            return "phone";
        if (icon.includes("computer"))
            return "computer";
        if (icon.includes("watch"))
            return "watch";
        if (icon.includes("display") || icon.includes("video"))
            return "display";
        return "other";
    }

    function __iconOf(device: var): string {
        switch (root.__kindOf(device)) {
        case "audio":
            return "headphones";
        case "input":
            return "keyboard";
        case "phone":
            return "smartphone";
        case "computer":
            return "computer";
        case "watch":
            return "watch";
        case "display":
            return "tv";
        default:
            return "bluetooth";
        }
    }

    // ---------------------------------------------------------------- control

    function toggle(): void {
        const adapter = Bluetooth.defaultAdapter;
        if (adapter)
            adapter.enabled = !adapter.enabled;
    }

    function setEnabled(enabled: bool): void {
        const adapter = Bluetooth.defaultAdapter;
        if (adapter)
            adapter.enabled = enabled;
    }

    function scan(enabled: bool): void {
        const adapter = Bluetooth.defaultAdapter;
        if (adapter)
            adapter.discovering = enabled;
    }

    function connectTo(address: string): bool {
        const found = root.devices.find(device => device.address === address);
        if (!found)
            return false;
        found.connect();
        return true;
    }

    function disconnectFrom(address: string): bool {
        const found = root.devices.find(device => device.address === address);
        if (!found)
            return false;
        found.disconnect();
        return true;
    }
}
