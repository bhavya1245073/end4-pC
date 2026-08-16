pragma Singleton

// Wi-Fi, ethernet, and VPNs.
//
//     PluginNetwork.online
//     PluginNetwork.type                  // "wifi" | "ethernet" | "none"
//     PluginNetwork.ssid                  // "Home-5G"
//     PluginNetwork.signalPercent         // 92
//     PluginNetwork.networks              // [{ ssid, signalPercent, saved, active, connect() }]
//     PluginNetwork.connect(ssid, password)
//     PluginNetwork.toggleWifi()
//
//     PluginNetwork.vpns                  // [{ name, type, connected, toggle() }]
//     PluginNetwork.vpnConnected
//
// Throughput is not here - that is PluginSystem.network, which reads the kernel counters.
// This is about links and credentials.
//
// The VPN list is built from NetworkManager plus WireGuard interfaces that were brought up
// outside it (wg-quick, systemd, Tailscale), because those do not appear as NM connections
// and a "VPN on?" indicator that misses them is worse than none. Refreshed on a slow timer
// and immediately after any change this facade makes.

import QtQuick
import Quickshell
import qs.services
import qs.core

Singleton {
    id: root

    // ------------------------------------------------------------------ links

    readonly property bool online: Network.wifiStatus === "connected" || Network.ethernet
    readonly property string type: Network.ethernet ? "ethernet" : (Network.wifi && Network.networkName.length > 0 ? "wifi" : "none")

    readonly property bool wifiEnabled: Network.wifiEnabled
    readonly property bool wifiScanning: Network.wifiScanning
    readonly property bool connecting: Network.wifiConnecting

    readonly property string ssid: Network.networkName
    readonly property int signalPercent: Network.networkStrength
    readonly property string ipAddress: Network.ipAddress
    readonly property string publicIpAddress: Network.publicIpAddress
    readonly property string gateway: Network.gateway
    readonly property string macAddress: Network.macAddress
    readonly property string interfaceName: Network.networkInterface
    readonly property string icon: Network.materialSymbol

    // [{ ssid, signalPercent, secure, active, connect(), forget() }]
    //
    // "Saved" is not in the shell's access point model and nmcli would have to be asked
    // separately for it, so it is deliberately absent rather than reported as a guess: a
    // connect() with no password works for a saved network and prompts for one otherwise,
    // which is the behaviour that actually matters.
    readonly property var networks: Network.friendlyWifiNetworks.map(access => ({
        ssid: access.ssid,
        bssid: access.bssid,
        signalPercent: access.strength,
        frequency: access.frequency,
        active: access.active ?? false,
        secure: access.isSecure ?? false,
        accessPoint: access,
        connect: password => password === undefined || password === ""
            ? Network.connectToWifiNetwork(access)
            : Network.changePassword(access, password),
        forget: () => PluginUtils.run(["nmcli", "connection", "delete", access.ssid], () => root.refreshVpns())
    }))

    function toggleWifi(): void {
        Network.toggleWifi();
    }

    function enableWifi(enabled: bool): void {
        Network.enableWifi(enabled);
    }

    function rescan(): void {
        Network.rescanWifi();
    }

    // `password` may be omitted for an open or already-saved network.
    function connect(ssid: string, password: string): bool {
        const found = root.networks.find(entry => entry.ssid === ssid);
        if (!found)
            return false;
        found.connect(password);
        return true;
    }

    function disconnect(): void {
        Network.disconnectWifiNetwork();
    }

    // ------------------------------------------------------------------- vpn

    // [{ id, name, type, connected, source, toggle(), up(), down() }]
    property var vpns: []

    readonly property bool vpnConnected: root.vpns.some(entry => entry.connected)
    readonly property var activeVpns: root.vpns.filter(entry => entry.connected)

    function refreshVpns(): void {
        // Two sources, because they do not overlap:
        //
        //   nmcli   VPN and WireGuard connections NetworkManager knows about, active or not
        //   /sys    interfaces brought up outside NetworkManager - wg-quick, Tailscale,
        //           systemd-networkd - which have no NM connection to list
        PluginUtils.run(["nmcli", "-t", "-f", "NAME,TYPE,DEVICE,ACTIVE", "connection", "show"], (stdout, code) => {
            const entries = [];
            if (code === 0) {
                for (const line of stdout.split("\n")) {
                    // nmcli -t escapes a colon inside a field as "\:", so split on the
                    // unescaped ones only.
                    const fields = line.split(/(?<!\\):/);
                    if (fields.length < 4)
                        continue;
                    const kind = fields[1];
                    if (kind !== "vpn" && kind !== "wireguard")
                        continue;
                    const name = fields[0].replace(/\\:/g, ":");
                    const connected = fields[3] === "yes";
                    entries.push({
                        id: name,
                        name: name,
                        type: kind,
                        connected: connected,
                        source: "networkmanager",
                        device: fields[2],
                        up: () => PluginUtils.run(["nmcli", "connection", "up", name], () => root.refreshVpns()),
                        down: () => PluginUtils.run(["nmcli", "connection", "down", name], () => root.refreshVpns()),
                        toggle: () => PluginUtils.run(["nmcli", "connection", connected ? "down" : "up", name], () => root.refreshVpns())
                    });
                }
            }
            root.__addForeignTunnels(entries);
        });
    }

    // WireGuard and Tailscale interfaces that NetworkManager does not own. `wg` needs root
    // to show peers, but the interface's existence and its type are readable from sysfs by
    // anyone, and that is all an indicator needs.
    function __addForeignTunnels(entries: var): void {
        PluginFs.list("/sys/class/net", result => {
            if (result.ok) {
                for (const entry of result.entries) {
                    const uevent = PluginFs.readSync(`/sys/class/net/${entry.name}/uevent`);
                    const isWireguard = uevent.includes("DEVTYPE=wireguard");
                    const isTailscale = entry.name.startsWith("tailscale");
                    if (!isWireguard && !isTailscale)
                        continue;
                    if (entries.some(known => known.device === entry.name))
                        continue;
                    const up = PluginFs.readSync(`/sys/class/net/${entry.name}/operstate`).trim();
                    const connected = up === "up" || up === "unknown";
                    entries.push({
                        id: entry.name,
                        name: entry.name,
                        type: isTailscale ? "tailscale" : "wireguard",
                        connected: connected,
                        source: "interface",
                        device: entry.name,
                        // Not managed by NetworkManager, so there is nothing safe to toggle
                        // from here: bringing a wg-quick tunnel up needs its config and root.
                        up: () => console.warn(`[network] ${entry.name} is not managed by NetworkManager`),
                        down: () => console.warn(`[network] ${entry.name} is not managed by NetworkManager`),
                        toggle: () => console.warn(`[network] ${entry.name} is not managed by NetworkManager`)
                    });
                }
            }
            root.vpns = entries;
        });
    }

    Component.onCompleted: root.refreshVpns()

    // A VPN going up or down is not something NetworkManager pushes to us here, and
    // checking twice a minute costs one short-lived process.
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.refreshVpns()
    }
}
