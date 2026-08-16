pragma Singleton

// Safe stand-ins for the things plugins otherwise shell out for.
//
// Every function here exists because the obvious way to do it in QML is a
// `Quickshell.execDetached(["bash", "-c", ...])` with a plugin's own string
// interpolated into it. That is a shell injection in your own desktop: a quote in
// a filename, a `$` in a note, a backtick in a clipboard entry, and the command
// means something else. Three of the five functions below need no process at all.
//
//     import qs.core
//
//     PluginUtils.copy(note.text)
//     PluginUtils.notify("Backup finished", "3.2 GB in 41s", { icon: "check" })
//     PluginUtils.fetchJson("https://api.example.com/v1/rates", res => {
//         if (res.ok) rate = res.data.usd
//         else console.warn(res.error)
//     })
//     PluginUtils.openUrl("https://example.com")
//     PluginUtils.exec(["systemctl", "--user", "restart", "waybar"])
//
// Nothing here is stateful, so calling any of it from a binding is a mistake -
// call it from a signal handler, a Timer, or a function.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // The app name notifications are attributed to. Notification centre groups on
    // this, so plugins share one group rather than spamming a dozen sources.
    readonly property string notifyAppName: "Shell"

    readonly property int fetchTimeout: 10000

    // ─────────────────────────────────────────────────────────── clipboard ──
    // Quickshell owns a clipboard connection already, so this is an assignment.
    // No wl-copy, no pipe, no escaping, and it works when wl-clipboard is not
    // installed.

    function copy(text: string): void {
        Quickshell.clipboardText = text ?? "";
    }

    // Copy with an explicit MIME type, for content that is not plain text: a list of file URIs a
    // file manager will accept as a paste, an SVG, an HTML fragment.
    //
    //     PluginUtils.copyTyped(paths.map(p => `file://${p}`).join("\n"), "text/uri-list")
    //
    // This is the one clipboard operation that cannot be done in-process: Quickshell's clipboard
    // is text/plain, and offering a different type means owning a Wayland data source. wl-copy is
    // the tool that does that, invoked as argv with the payload as an argument - no shell, so no
    // quoting hazard, whatever is in the text.
    function copyTyped(text: string, mimeType: string): void {
        Quickshell.execDetached(["wl-copy", "--type", mimeType ?? "text/plain", text ?? ""]);
    }

    function paste(): string {
        return Quickshell.clipboardText ?? "";
    }

    // ──────────────────────────────────────────────────────── notifications ──
    // `options`: { icon, urgency: "low"|"normal"|"critical", timeout (ms),
    //              appName, actions: { id: label }, onAction: id => {} }
    //
    // The shell is itself the notification daemon, so this makes a round trip out
    // to D-Bus and back into the shell's own popup. That is deliberate: the
    // notification then behaves like every other one - history, grouping, do not
    // disturb - instead of being a private overlay that ignores all of it.

    function notify(title: string, body: string, options: var): void {
        const opts = options ?? {};
        const command = ["notify-send", "--app-name", opts.appName ?? root.notifyAppName];

        if (opts.icon)
            command.push("--icon", opts.icon);
        if (opts.urgency)
            command.push("--urgency", opts.urgency);
        if (opts.timeout !== undefined)
            command.push("--expire-time", String(Math.round(opts.timeout)));

        // Each token is its own argv entry, so a title of `"; rm -rf ~` is a title.
        command.push(title ?? "", body ?? "");
        Quickshell.execDetached(command);
    }

    // ─────────────────────────────────────────────────────────────── http ──
    // XMLHttpRequest rather than curl: no process, no argv, and the response never
    // passes through a shell. `callback` always gets one shape, so a plugin has one
    // branch to write instead of guessing at failure modes:
    //
    //     { ok: bool, status: int, data: var, text: string, error: string }
    //
    // `ok` is false for a network failure, a timeout, a non-2xx status and
    // unparseable JSON alike - a widget that wants to show "unavailable" does not
    // care which.

    function fetchJson(url: string, optionsOrCallback: var, maybeCallback: var): void {
        const hasOptions = typeof optionsOrCallback === "object" && optionsOrCallback !== null;
        const options = hasOptions ? optionsOrCallback : {};
        const callback = hasOptions ? maybeCallback : optionsOrCallback;
        root.__fetch(url, options, callback, true);
    }

    function fetchText(url: string, optionsOrCallback: var, maybeCallback: var): void {
        const hasOptions = typeof optionsOrCallback === "object" && optionsOrCallback !== null;
        const options = hasOptions ? optionsOrCallback : {};
        const callback = hasOptions ? maybeCallback : optionsOrCallback;
        root.__fetch(url, options, callback, false);
    }

    // Internal: the shared half of fetchJson/fetchText. Not part of the plugin API.
    function __fetch(url, options, callback, parseJson) {
        if (typeof callback !== "function") {
            console.warn("[PluginUtils] fetch called without a callback:", url);
            return;
        }

        const done = result => {
            // A throwing callback would otherwise surface as an unhandled exception
            // inside XHR's own handler, which reports the wrong file and line.
            try {
                callback(result);
            } catch (e) {
                console.warn("[PluginUtils] fetch callback threw:", e);
            }
        };

        const xhr = new XMLHttpRequest();
        xhr.open(options.method ?? "GET", url);
        xhr.timeout = options.timeout ?? root.fetchTimeout;

        if (parseJson)
            xhr.setRequestHeader("Accept", "application/json");
        for (const name in (options.headers ?? {}))
            xhr.setRequestHeader(name, String(options.headers[name]));

        xhr.onerror = () => done({
            ok: false,
            status: xhr.status ?? 0,
            data: null,
            text: "",
            error: `request to ${url} failed`
        });
        xhr.ontimeout = () => done({
            ok: false,
            status: 0,
            data: null,
            text: "",
            error: `request to ${url} timed out after ${xhr.timeout}ms`
        });

        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            // onerror/ontimeout already reported it; status 0 here is that same event.
            if (xhr.status === 0)
                return;

            const httpOk = xhr.status >= 200 && xhr.status < 300;
            let data = null;
            let parseError = "";

            if (parseJson && httpOk) {
                try {
                    data = JSON.parse(xhr.responseText);
                } catch (e) {
                    parseError = `response from ${url} is not JSON: ${e}`;
                }
            }

            done({
                ok: httpOk && parseError === "",
                status: xhr.status,
                data: parseJson ? data : xhr.responseText,
                text: xhr.responseText,
                error: parseError !== "" ? parseError : httpOk ? "" : `${url} returned HTTP ${xhr.status}`
            });
        };

        xhr.send(options.body ?? null);
    }

    // ───────────────────────────────────────────────────────── processes ──
    // A list, never a string. `exec("rm -rf " + dir)` is the bug this signature
    // exists to make impossible, so a string is refused rather than split on
    // spaces - splitting would "work" until a path contained one.

    function exec(command: var): void {
        if (typeof command === "string") {
            console.warn("[PluginUtils] exec needs a list, not a string:", command,
                         "- write [\"sh\", \"-c\", \"...\"] if you really need a shell.");
            return;
        }
        if (!Array.isArray(command) || command.length === 0) {
            console.warn("[PluginUtils] exec called with no command");
            return;
        }
        Quickshell.execDetached(command.map(part => String(part)));
    }

    // Same, but hands the output back: `callback(stdout, exitCode, stderr)`. The Process is
    // parented to this singleton and destroyed when it finishes, so a plugin cannot leak one
    // by forgetting.
    function run(command: var, callback: var): void {
        if (!Array.isArray(command) || command.length === 0) {
            console.warn("[PluginUtils] run needs a non-empty list");
            return;
        }
        const proc = root.__processComponent.createObject(root, {
            command: command.map(part => String(part)),
            handler: callback ?? null
        });
        proc.running = true;
    }

    function openUrl(url: string): void {
        if (!url)
            return;
        Qt.openUrlExternally(url);
    }

    // ───────────────────────────────────────────────────────── formatting ──
    // Small things every second widget reimplements slightly differently.

    // Binary units, because this is for RAM and file sizes and every other tool on
    // the system reports those in powers of 1024.
    function formatBytes(bytes: real): string {
        const value = Math.max(0, bytes ?? 0);
        if (value < 1024)
            return `${Math.round(value)} B`;
        const units = ["KiB", "MiB", "GiB", "TiB", "PiB"];
        let scaled = value / 1024;
        let unit = 0;
        while (scaled >= 1024 && unit < units.length - 1) {
            scaled /= 1024;
            unit++;
        }
        // One decimal below 10 so a bar widget's width does not jitter between
        // "9.7 GiB" and "10.3 GiB" every refresh.
        return `${scaled < 10 ? scaled.toFixed(1) : Math.round(scaled)} ${units[unit]}`;
    }

    // 4055 -> "1h 7m". For a duration, not a clock.
    function formatDuration(seconds: real): string {
        const total = Math.max(0, Math.round(seconds));
        const h = Math.floor(total / 3600);
        const m = Math.floor((total % 3600) / 60);
        const s = total % 60;
        if (h > 0)
            return `${h}h ${m}m`;
        if (m > 0)
            return `${m}m ${s}s`;
        return `${s}s`;
    }

    function truncate(text: string, limit: int): string {
        const str = text ?? "";
        if (limit <= 1 || str.length <= limit)
            return str;
        // U+2026, so the ellipsis is one glyph and cannot wrap mid-dot. Trailing space is
        // stripped with a regex rather than trimEnd(): Qt's JS engine predates ES2019, and
        // calling a method it does not have is a runtime TypeError, not a compile error.
        return str.slice(0, limit - 1).replace(/\s+$/, "") + "…";
    }

    readonly property Component __processComponent: Component {
        Process {
            id: proc
            property var handler: null
            stdout: StdioCollector {}
            // Collected as well as stdout, because some tools write the answer there - fuser
            // prints its pids to stderr - and because a callback that only ever sees an
            // empty string cannot say *why* a command failed.
            stderr: StdioCollector {}
            onExited: (exitCode, _status) => {
                if (proc.handler)
                    proc.handler(proc.stdout.text, exitCode, proc.stderr.text);
                proc.destroy();
            }
        }
    }
}
