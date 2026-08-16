// Commands this plugin adds to the shell's command line.
//
//     qs -c end4-pC ipc call battery report
//     qs -c end4-pC ipc call battery percent
//
// Every function here is a command, so a plugin can be driven from a script or a
// compositor keybind without the shell needing to know anything about it. Parameters and
// return types must be annotated or Quickshell cannot marshal the call.

import qs.core

PluginIpc {
    // Defaults to the plugin id, which is already "battery"; spelled out because this
    // file is the worked example.
    target: "battery"

    function report(): string {
        if (!BatteryState.available)
            return "no battery on this machine";
        const text = `${BatteryState.percent}% - ${BatteryState.summary()}`;
        console.log(`[battery] ${text}`);
        return text;
    }

    function percent(): int {
        return BatteryState.percent;
    }

    function isCharging(): bool {
        return BatteryState.charging;
    }
}
