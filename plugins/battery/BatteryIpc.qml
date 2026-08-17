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
    // The command name lives in the manifest (`provides.ipc[].target`), not here: the host injects
    // it, so the name a script types and the name the manifest documents cannot drift apart.

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
