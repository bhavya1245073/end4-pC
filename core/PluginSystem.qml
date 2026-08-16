pragma Singleton

// Hardware telemetry, read from the kernel rather than parsed out of other programs.
//
//     PluginSystem.cpu.usagePercent          // 14.5
//     PluginSystem.cpu.tempCelsius           // 61
//     PluginSystem.cpu.frequencyGhz          // 3.81
//     PluginSystem.cpu.perCore               // [ 12.0, 40.5, ... ]
//     PluginSystem.memory.usedPercent        // 26.2
//     PluginSystem.memory.usedFormatted      // "4.2 GiB"
//     PluginSystem.gpu.usagePercent          // 27.6   (gpu.hasUsage tells you first)
//     PluginSystem.network.downloadFormatted // "1.4 MiB/s"
//     PluginSystem.disks.root.usedPercent    // 42.0
//     PluginSystem.cpu.history               // last 60 samples, for PluginSparkline
//
// Everything is a property, so a widget binds and never polls.
//
// ## What it costs
//
// /proc and /sys reads are synchronous here and take about 70µs each. One poll reads
// /proc/stat, /proc/meminfo, /proc/loadavg, /proc/net/dev and a handful of one-line sysfs
// files: well under a millisecond, every `interval` (2s by default). Disks are different -
// they need df, a real process - so they refresh on their own slower `diskInterval` (30s).
// Nothing polls while `paused` is true.
//
// ## Capability flags, not zeros
//
// Not every machine can answer every question. An Intel integrated GPU has no VRAM and no
// busy-percent counter; a desktop has no battery; a VM has no temperature sensor. Each
// group therefore says what it knows - `gpu.hasUsage`, `gpu.hasVram`, `cpu.hasTemp` - so a
// widget can hide a row instead of drawing a confident 0.0 that is really "no idea".
//
// GPU load on Intel is derived from RC6 residency: the driver reports how long the GPU
// spent in its deepest idle state, and busy is what is left. It is a real measurement,
// slightly coarser than the per-engine counters that need root.

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

Singleton {
    id: root

    // ------------------------------------------------------------------ knobs

    property int interval: 2000
    property int diskInterval: 30000
    property bool paused: false

    // Samples kept for the sparkline-style properties.
    property int historyLength: 60

    // ------------------------------------------------------------------- cpu

    readonly property QtObject cpu: QtObject {
        id: cpuGroup

        property real usagePercent: 0
        property real tempCelsius: 0
        property bool hasTemp: false
        property real frequencyGhz: 0
        property real maxFrequencyGhz: 0
        property int cores: 0
        property string model: ""
        property real load1: 0
        property real load5: 0
        property real load15: 0

        // Per-logical-core usage, same units as usagePercent.
        property var perCore: []

        // Oldest first. Reassigned, never mutated: a binding on an array that is changed in
        // place does not re-evaluate.
        property var history: []

        readonly property string usageFormatted: `${cpuGroup.usagePercent.toFixed(0)}%`
        readonly property string tempFormatted: cpuGroup.hasTemp ? `${cpuGroup.tempCelsius.toFixed(0)}°C` : "--"
        readonly property string frequencyFormatted: cpuGroup.frequencyGhz > 0 ? `${cpuGroup.frequencyGhz.toFixed(2)} GHz` : "--"
    }

    // ---------------------------------------------------------------- memory

    readonly property QtObject memory: QtObject {
        id: memoryGroup

        property real totalBytes: 0
        property real usedBytes: 0
        property real availableBytes: 0
        property real cachedBytes: 0
        property real usedPercent: 0

        property real swapTotalBytes: 0
        property real swapUsedBytes: 0
        property real swapPercent: 0

        property var history: []

        readonly property string usedFormatted: PluginUtils.formatBytes(memoryGroup.usedBytes)
        readonly property string totalFormatted: PluginUtils.formatBytes(memoryGroup.totalBytes)
        readonly property string availableFormatted: PluginUtils.formatBytes(memoryGroup.availableBytes)
        readonly property string swapUsedFormatted: PluginUtils.formatBytes(memoryGroup.swapUsedBytes)
        readonly property string swapTotalFormatted: PluginUtils.formatBytes(memoryGroup.swapTotalBytes)
        readonly property bool hasSwap: memoryGroup.swapTotalBytes > 0
    }

    // ------------------------------------------------------------------- gpu

    readonly property QtObject gpu: QtObject {
        id: gpuGroup

        property bool available: false
        property string name: ""
        property string driver: ""

        property real usagePercent: 0
        property bool hasUsage: false

        property real tempCelsius: 0
        property bool hasTemp: false
        // True when the temperature is the CPU package's, because the GPU shares the die
        // and has no sensor of its own.
        property bool tempIsShared: false

        property real frequencyMhz: 0
        property real maxFrequencyMhz: 0
        property bool hasFrequency: false

        property real vramUsedBytes: 0
        property real vramTotalBytes: 0
        property real vramPercent: 0
        property bool hasVram: false

        property var history: []

        readonly property string usageFormatted: gpuGroup.hasUsage ? `${gpuGroup.usagePercent.toFixed(0)}%` : "--"
        readonly property string tempFormatted: gpuGroup.hasTemp ? `${gpuGroup.tempCelsius.toFixed(0)}°C` : "--"
        readonly property string vramUsedFormatted: gpuGroup.hasVram ? PluginUtils.formatBytes(gpuGroup.vramUsedBytes) : "--"
        readonly property string vramTotalFormatted: gpuGroup.hasVram ? PluginUtils.formatBytes(gpuGroup.vramTotalBytes) : "--"
        readonly property string frequencyFormatted: gpuGroup.hasFrequency ? `${gpuGroup.frequencyMhz.toFixed(0)} MHz` : "--"
    }

    // --------------------------------------------------------------- network

    readonly property QtObject network: QtObject {
        id: networkGroup

        property real downloadBytesPerSecond: 0
        property real uploadBytesPerSecond: 0
        property real totalReceivedBytes: 0
        property real totalSentBytes: 0
        property bool isOnline: false
        property string primaryInterface: ""

        // [{ name, up, receivedBytes, sentBytes, downloadBytesPerSecond, uploadBytesPerSecond, wireless }]
        property var interfaces: []

        property var downloadHistory: []
        property var uploadHistory: []

        readonly property string downloadFormatted: `${PluginUtils.formatBytes(networkGroup.downloadBytesPerSecond)}/s`
        readonly property string uploadFormatted: `${PluginUtils.formatBytes(networkGroup.uploadBytesPerSecond)}/s`
        readonly property string totalReceivedFormatted: PluginUtils.formatBytes(networkGroup.totalReceivedBytes)
        readonly property string totalSentFormatted: PluginUtils.formatBytes(networkGroup.totalSentBytes)
    }

    // ----------------------------------------------------------------- disks

    readonly property QtObject disks: QtObject {
        id: disksGroup

        // [{ device, mount, filesystem, totalBytes, usedBytes, freeBytes, usedPercent,
        //    totalFormatted, usedFormatted, freeFormatted }]
        property var list: []

        readonly property var root: disksGroup.byMount("/")

        function byMount(mount: string): var {
            return disksGroup.list.find(entry => entry.mount === mount) ?? ({
                device: "",
                mount: mount,
                filesystem: "",
                totalBytes: 0,
                usedBytes: 0,
                freeBytes: 0,
                usedPercent: 0,
                totalFormatted: "--",
                usedFormatted: "--",
                freeFormatted: "--"
            });
        }

        // The mount a path is on, which is the question a "is there room for this" check
        // actually asks.
        function forPath(path: string): var {
            const full = PluginFs.expand(path);
            let best = null;
            for (const entry of disksGroup.list) {
                if (!full.startsWith(entry.mount))
                    continue;
                if (!best || entry.mount.length > best.mount.length)
                    best = entry;
            }
            return best ?? disksGroup.byMount("/");
        }
    }

    // ------------------------------------------------------------ discovery

    // Sensor and device paths found once at startup. Hardware does not come and go, and
    // rescanning /sys every two seconds to learn the same answer would be waste.
    property string cpuTempPath: ""
    property string cpuFreqPath: ""
    property string gpuCardPath: ""
    property string gpuBusyPath: ""
    property string gpuRc6Path: ""
    property string gpuFreqPath: ""
    property string gpuMaxFreqPath: ""
    property string gpuTempPath: ""
    property string gpuVramUsedPath: ""
    property string gpuVramTotalPath: ""
    property bool discovered: false

    function discover(): void {
        root.__discoverCpu();
        root.__discoverHwmon();
        root.__discoverGpu();
        root.discovered = true;
    }

    function __discoverCpu(): void {
        const info = PluginFs.readSync("/proc/cpuinfo");
        root.cpu.model = (info.match(/model name\s*:\s*(.+)/)?.[1] ?? "").trim();
        root.cpu.cores = (info.match(/^processor\s*:/gm) ?? []).length;

        // Scaling driver first: /proc/cpuinfo's "cpu MHz" is per-core and jumps about,
        // while cpufreq gives a stable current frequency in kHz.
        if (PluginFs.readSync("/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq").length > 0)
            root.cpuFreqPath = "/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq";

        const maxKhz = PluginFs.readSyncNumber("/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq", 0);
        if (maxKhz > 0)
            root.cpu.maxFrequencyGhz = maxKhz / 1000000;
        else
            root.cpu.maxFrequencyGhz = parseFloat(root.cpu.model.match(/@\s*([0-9.]+)\s*GHz/)?.[1] ?? "0");
    }

    // hwmon is a flat list of numbered directories whose `name` file says what the sensor
    // is. Walking it is how the CPU package temperature is found without shelling out to
    // `sensors` and grepping its human-readable output.
    property var hwmonByName: ({})

    function __discoverHwmon(): void {
        const found = ({});
        // Up to 32 is generous: this machine has 10, and a server with more can be handled
        // by a plugin that knows its own hardware.
        for (let index = 0; index < 32; index++) {
            const base = `/sys/class/hwmon/hwmon${index}`;
            const name = PluginFs.readSync(`${base}/name`).trim();
            if (name.length === 0)
                continue;
            if (!found[name])
                found[name] = [];
            found[name].push(base);
        }
        root.hwmonByName = found;

        // In preference order: the die sensor, then the AMD equivalents, then the ACPI
        // thermal zone, which is usually the chassis and better than nothing.
        for (const candidate of ["coretemp", "k10temp", "zenpower", "cpu_thermal", "acpitz", "acpitz_0"]) {
            const bases = found[candidate];
            if (!bases)
                continue;
            const path = root.__hwmonInput(bases[0], ["Package id 0", "Tctl", "Tdie", "CPU"]);
            if (path) {
                root.cpuTempPath = path;
                root.cpu.hasTemp = true;
                return;
            }
        }
    }

    // The tempN_input whose label matches one of `preferred`, else temp1_input.
    function __hwmonInput(base: string, preferred: var): string {
        for (let index = 1; index <= 24; index++) {
            const label = PluginFs.readSync(`${base}/temp${index}_label`).trim();
            if (label.length > 0 && preferred.some(want => label.startsWith(want)))
                return `${base}/temp${index}_input`;
        }
        return PluginFs.readSync(`${base}/temp1_input`).length > 0 ? `${base}/temp1_input` : "";
    }

    function __discoverGpu(): void {
        // /sys/class/drm/cardN. The number is not always 0 - this machine's is card1 - so
        // the first card that has a device directory wins.
        for (let index = 0; index < 8; index++) {
            const card = `/sys/class/drm/card${index}`;
            const vendor = PluginFs.readSync(`${card}/device/vendor`).trim();
            if (vendor.length === 0)
                continue;

            root.gpuCardPath = card;
            root.gpu.available = true;
            root.gpu.driver = root.__gpuDriver(card);
            root.gpu.name = root.__gpuName(vendor, PluginFs.readSync(`${card}/device/device`).trim(), root.gpu.driver);

            // AMD: a ready-made busy percentage and VRAM counters.
            if (PluginFs.readSync(`${card}/device/gpu_busy_percent`).length > 0) {
                root.gpuBusyPath = `${card}/device/gpu_busy_percent`;
                root.gpu.hasUsage = true;
            }
            if (PluginFs.readSync(`${card}/device/mem_info_vram_total`).length > 0) {
                root.gpuVramUsedPath = `${card}/device/mem_info_vram_used`;
                root.gpuVramTotalPath = `${card}/device/mem_info_vram_total`;
                root.gpu.hasVram = true;
                root.gpu.vramTotalBytes = PluginFs.readSyncNumber(root.gpuVramTotalPath, 0);
            }

            // Intel: RC6 residency, the time the render engine spent in its deepest idle
            // state. Busy is the rest of the wall clock, which is a real measurement even
            // though it cannot say *which* engine was busy.
            if (!root.gpu.hasUsage) {
                for (const rc6 of [`${card}/gt/gt0/rc6_residency_ms`, `${card}/power/rc6_residency_ms`]) {
                    if (PluginFs.readSync(rc6).length === 0)
                        continue;
                    root.gpuRc6Path = rc6;
                    root.gpu.hasUsage = true;
                    break;
                }
            }

            for (const freq of [`${card}/gt_act_freq_mhz`, `${card}/gt/gt0/rps_act_freq_mhz`, `${card}/device/pp_dpm_sclk`]) {
                if (PluginFs.readSync(freq).length === 0 || freq.endsWith("pp_dpm_sclk"))
                    continue;
                root.gpuFreqPath = freq;
                root.gpuMaxFreqPath = `${card}/gt_max_freq_mhz`;
                root.gpu.hasFrequency = true;
                root.gpu.maxFrequencyMhz = PluginFs.readSyncNumber(root.gpuMaxFreqPath, 0);
                break;
            }

            // A discrete card has its own hwmon; an integrated one shares the CPU's.
            for (const sensor of ["amdgpu", "nouveau", "radeon", "i915", "xe"]) {
                const bases = root.hwmonByName[sensor];
                if (!bases)
                    continue;
                const path = root.__hwmonInput(bases[0], ["edge", "junction", "GPU"]);
                if (path) {
                    root.gpuTempPath = path;
                    root.gpu.hasTemp = true;
                    break;
                }
            }
            if (!root.gpu.hasTemp && root.cpu.hasTemp) {
                root.gpuTempPath = root.cpuTempPath;
                root.gpu.hasTemp = true;
                root.gpu.tempIsShared = true;
            }
            return;
        }
    }

    function __gpuDriver(card: string): string {
        // The driver is a symlink; its target's last component is the module name. FileView
        // cannot read a link, but uevent spells it out.
        const uevent = PluginFs.readSync(`${card}/device/uevent`);
        return (uevent.match(/DRIVER=(.+)/)?.[1] ?? "").trim();
    }

    function __gpuName(vendorId: string, deviceId: string, driver: string): string {
        const vendors = ({ "0x8086": "Intel", "0x1002": "AMD", "0x10de": "NVIDIA", "0x1af4": "Virtio" });
        const vendor = vendors[vendorId.toLowerCase()] ?? vendorId;
        // The model name lives in pci.ids, which is not guaranteed to be installed; driver
        // plus device id is honest and always available.
        return driver.length > 0 ? `${vendor} ${driver} (${deviceId})` : `${vendor} ${deviceId}`;
    }

    // ------------------------------------------------------------------ poll

    property var __lastCpu: null
    property var __lastPerCore: ({})
    property var __lastNet: ({})
    property real __lastRc6: -1
    property real __lastPollAt: 0

    function refresh(): void {
        if (!root.discovered)
            root.discover();
        root.__pollCpu();
        root.__pollMemory();
        root.__pollGpu();
        root.__pollNetwork();
        root.__lastPollAt = Date.now();
    }

    function __pollCpu(): void {
        const stat = PluginFs.readSync("/proc/stat");
        if (stat.length === 0)
            return;

        for (const line of stat.split("\n")) {
            if (!line.startsWith("cpu"))
                break;
            const parts = line.trim().split(/\s+/);
            const label = parts[0];
            const values = parts.slice(1).map(Number);
            if (values.length < 5)
                continue;
            const total = values.reduce((sum, value) => sum + value, 0);
            const idle = values[3] + (values[4] ?? 0);

            if (label === "cpu") {
                const previous = root.__lastCpu;
                if (previous) {
                    const totalDelta = total - previous.total;
                    const idleDelta = idle - previous.idle;
                    if (totalDelta > 0)
                        root.cpu.usagePercent = Math.max(0, Math.min(100, (1 - idleDelta / totalDelta) * 100));
                }
                root.__lastCpu = { total: total, idle: idle };
            } else {
                const previous = root.__lastPerCore[label];
                const index = parseInt(label.slice(3));
                if (previous) {
                    const totalDelta = total - previous.total;
                    const idleDelta = idle - previous.idle;
                    const perCore = root.cpu.perCore.slice();
                    while (perCore.length <= index)
                        perCore.push(0);
                    perCore[index] = totalDelta > 0 ? Math.max(0, Math.min(100, (1 - idleDelta / totalDelta) * 100)) : 0;
                    root.cpu.perCore = perCore;
                }
                root.__lastPerCore[label] = { total: total, idle: idle };
            }
        }

        if (root.cpuTempPath)
            root.cpu.tempCelsius = PluginFs.readSyncNumber(root.cpuTempPath, 0) / 1000;

        if (root.cpuFreqPath)
            root.cpu.frequencyGhz = PluginFs.readSyncNumber(root.cpuFreqPath, 0) / 1000000;

        const load = PluginFs.readSync("/proc/loadavg").trim().split(/\s+/);
        if (load.length >= 3) {
            root.cpu.load1 = parseFloat(load[0]) || 0;
            root.cpu.load5 = parseFloat(load[1]) || 0;
            root.cpu.load15 = parseFloat(load[2]) || 0;
        }

        root.cpu.history = root.__pushHistory(root.cpu.history, root.cpu.usagePercent);
    }

    function __pollMemory(): void {
        const info = PluginFs.readSync("/proc/meminfo");
        if (info.length === 0)
            return;
        const kb = key => Number(info.match(new RegExp(`${key}:\\s*(\\d+)`))?.[1] ?? 0) * 1024;

        const total = kb("MemTotal");
        const available = kb("MemAvailable");
        root.memory.totalBytes = total;
        root.memory.availableBytes = available;
        root.memory.cachedBytes = kb("Cached");
        root.memory.usedBytes = Math.max(0, total - available);
        root.memory.usedPercent = total > 0 ? (root.memory.usedBytes / total) * 100 : 0;

        const swapTotal = kb("SwapTotal");
        const swapFree = kb("SwapFree");
        root.memory.swapTotalBytes = swapTotal;
        root.memory.swapUsedBytes = Math.max(0, swapTotal - swapFree);
        root.memory.swapPercent = swapTotal > 0 ? (root.memory.swapUsedBytes / swapTotal) * 100 : 0;

        root.memory.history = root.__pushHistory(root.memory.history, root.memory.usedPercent);
    }

    function __pollGpu(): void {
        if (!root.gpu.available)
            return;

        if (root.gpuBusyPath) {
            root.gpu.usagePercent = PluginFs.readSyncNumber(root.gpuBusyPath, 0);
        } else if (root.gpuRc6Path) {
            const now = Date.now();
            const residency = PluginFs.readSyncNumber(root.gpuRc6Path, -1);
            if (residency >= 0 && root.__lastRc6 >= 0 && root.__lastPollAt > 0) {
                const wall = now - root.__lastPollAt;
                const idle = residency - root.__lastRc6;
                if (wall > 0)
                    root.gpu.usagePercent = Math.max(0, Math.min(100, (1 - idle / wall) * 100));
            }
            root.__lastRc6 = residency;
        }

        if (root.gpuTempPath)
            root.gpu.tempCelsius = PluginFs.readSyncNumber(root.gpuTempPath, 0) / 1000;

        if (root.gpuFreqPath)
            root.gpu.frequencyMhz = PluginFs.readSyncNumber(root.gpuFreqPath, 0);

        if (root.gpu.hasVram) {
            root.gpu.vramUsedBytes = PluginFs.readSyncNumber(root.gpuVramUsedPath, 0);
            if (root.gpu.vramTotalBytes > 0)
                root.gpu.vramPercent = (root.gpu.vramUsedBytes / root.gpu.vramTotalBytes) * 100;
        }

        root.gpu.history = root.__pushHistory(root.gpu.history, root.gpu.usagePercent);
    }

    function __pollNetwork(): void {
        const dev = PluginFs.readSync("/proc/net/dev");
        if (dev.length === 0)
            return;

        const now = Date.now();
        const elapsed = root.__lastPollAt > 0 ? (now - root.__lastPollAt) / 1000 : 0;
        const interfaces = [];
        let download = 0;
        let upload = 0;
        let receivedTotal = 0;
        let sentTotal = 0;
        let primary = "";
        let primaryRate = -1;

        for (const line of dev.split("\n")) {
            const match = line.match(/^\s*([^:]+):\s*(.+)$/);
            if (!match)
                continue;
            const name = match[1].trim();
            if (name === "lo")
                continue;
            const values = match[2].trim().split(/\s+/).map(Number);
            const received = values[0] ?? 0;
            const sent = values[8] ?? 0;

            const previous = root.__lastNet[name];
            let downRate = 0;
            let upRate = 0;
            if (previous && elapsed > 0) {
                // Counters reset when an interface goes down and comes back; a negative
                // delta is that, not a negative speed.
                downRate = Math.max(0, (received - previous.received) / elapsed);
                upRate = Math.max(0, (sent - previous.sent) / elapsed);
            }
            root.__lastNet[name] = { received: received, sent: sent };

            const up = PluginFs.readSync(`/sys/class/net/${name}/operstate`).trim() === "up";
            interfaces.push({
                name: name,
                up: up,
                wireless: PluginFs.readSync(`/sys/class/net/${name}/uevent`).includes("DEVTYPE=wlan")
                    || PluginFs.readSyncNumber(`/sys/class/net/${name}/type`, 0) === 801,
                receivedBytes: received,
                sentBytes: sent,
                downloadBytesPerSecond: downRate,
                uploadBytesPerSecond: upRate
            });

            if (!up)
                continue;
            download += downRate;
            upload += upRate;
            receivedTotal += received;
            sentTotal += sent;
            if (downRate + upRate > primaryRate) {
                primaryRate = downRate + upRate;
                primary = name;
            }
        }

        root.network.interfaces = interfaces;
        root.network.downloadBytesPerSecond = download;
        root.network.uploadBytesPerSecond = upload;
        root.network.totalReceivedBytes = receivedTotal;
        root.network.totalSentBytes = sentTotal;
        root.network.isOnline = interfaces.some(entry => entry.up);
        root.network.primaryInterface = primary;

        root.network.downloadHistory = root.__pushHistory(root.network.downloadHistory, download);
        root.network.uploadHistory = root.__pushHistory(root.network.uploadHistory, upload);
    }

    function refreshDisks(): void {
        // -P for POSIX output (one line per filesystem, never wrapped), -k for KiB units,
        // --local to skip network mounts that can block, --print-type so a caller can tell
        // xfs from vfat. No shell: df's output arrives through a callback, not a pipe.
        PluginUtils.run(["df", "-kP", "--local", "--print-type"], (stdout, code) => {
            if (code !== 0)
                return;
            const entries = [];
            const seen = ({});
            for (const line of stdout.split("\n").slice(1)) {
                const parts = line.trim().split(/\s+/);
                if (parts.length < 7)
                    continue;
                const device = parts[0];
                // Only real block devices. Everything else df lists - tmpfs, devtmpfs,
                // efivarfs, the per-service credential mounts systemd makes - is not
                // storage, and putting it in a disk list is noise a widget then has to
                // filter again.
                if (!device.startsWith("/dev/"))
                    continue;
                const mount = parts[6];
                if (seen[mount])
                    continue;
                const total = Number(parts[2]) * 1024;
                const used = Number(parts[3]) * 1024;
                const free = Number(parts[4]) * 1024;
                if (!(total > 0))
                    continue;
                seen[mount] = true;
                entries.push({
                    device: device,
                    mount: mount,
                    filesystem: parts[1],
                    totalBytes: total,
                    usedBytes: used,
                    freeBytes: free,
                    usedPercent: (used / total) * 100,
                    totalFormatted: PluginUtils.formatBytes(total),
                    usedFormatted: PluginUtils.formatBytes(used),
                    freeFormatted: PluginUtils.formatBytes(free)
                });
            }
            root.disks.list = entries;
        });
    }

    function __pushHistory(history: var, value: real): var {
        const next = history.slice();
        next.push(value);
        while (next.length > root.historyLength)
            next.shift();
        return next;
    }

    // ---------------------------------------------------------------- timers

    // Usage is a delta between two samples, so a single first poll can only ever report
    // zero. Taking the second sample 120ms later means a meter shows a real number almost
    // immediately instead of a confident 0% for the first two seconds.
    Component.onCompleted: {
        root.refresh();
        root.refreshDisks();
        primer.start();
    }

    Timer {
        id: primer
        interval: 120
        onTriggered: root.refresh()
    }

    Timer {
        interval: root.interval
        running: !root.paused
        repeat: true
        onTriggered: root.refresh()
    }

    Timer {
        interval: root.diskInterval
        running: !root.paused
        repeat: true
        onTriggered: root.refreshDisks()
    }
}
