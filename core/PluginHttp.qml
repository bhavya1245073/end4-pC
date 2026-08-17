pragma Singleton

// HTTP for plugins, with the four things hand-rolled `curl` calls never have: a cache, a
// timeout, cancellation when the caller goes away, and one place to look when a request
// misbehaves.
//
//     PluginHttp.get("https://api.example.com/today", { cacheTtl: 600000 }, response => {
//         if (!response.ok) {
//             PluginToast.error(response.error);
//             return;
//         }
//         root.temperature = response.json.temp;
//     })
//
// The response is always an object, never a throw:
//
//     { ok, status, body, json, headers, error, fromCache, url, elapsedMs }
//
// `json` is already parsed when the body is JSON, and null when it is not - so the usual
// `try { JSON.parse(...) } catch` around every callback disappears.
//
// ## Why XMLHttpRequest and not curl
//
// Qt's XHR is in-process and non-blocking, so a slow server costs no process spawn and
// cannot stall the UI thread. It also gives real status codes and headers, which a
// `curl -s` pipeline throws away - the reason so many plugins treat "404 page not found"
// as valid data and render the error page.
//
// ## Cancellation is the point
//
// A popup that fetches on open and is closed two frames later leaves a request in flight.
// When it lands, the callback writes to a destroyed object's properties. Qt survives it;
// the plugin does not - it is the usual cause of "the picker shows the previous search's
// results". Pass `owner` and the callback is dropped if that object is gone:
//
//     PluginHttp.get(url, { owner: root, cacheTtl: 0 }, handle)
//
// PluginContentView passes itself, so anything built on it gets this for free.

import QtQuick
import Quickshell
import qs.core

Singleton {
    id: root

    // Default ceiling on a request. Long enough for a slow API, short enough that a plugin
    // waiting on it does not look broken.
    readonly property int defaultTimeoutMs: 5000

    // How many bodies to keep. Entries are evicted oldest-first; a cache that grows without
    // limit in a process that runs for weeks is a leak with a nice name.
    readonly property int maxCacheEntries: 120

    readonly property int inFlight: Object.keys(root.__active).length

    // Set by the settings GUI or a plugin under test. When off, every request fails
    // immediately with a cache fallback if there is one - which is also how offline mode
    // is tested without unplugging anything.
    property bool enabled: true

    property var __cache: ({})
    property var __cacheOrder: []
    property var __active: ({})
    property int __nextId: 1

    // ------------------------------------------------------------------- verbs

    // options:
    //   pluginId    attribution and the permission check
    //   owner       QtObject whose destruction cancels the callback
    //   headers     { "Authorization": "Bearer ..." }
    //   cacheTtl    milliseconds a response stays fresh; 0 disables caching
    //   timeoutMs   defaults to defaultTimeoutMs
    //   json        parse the body as JSON even when the content type does not say so
    //   query       { key: value } appended as a query string, encoded properly
    function get(url: string, options: var, callback: var): int {
        return root.request("GET", url, null, options, callback);
    }

    function post(url: string, body: var, options: var, callback: var): int {
        return root.request("POST", url, body, options, callback);
    }

    function put(url: string, body: var, options: var, callback: var): int {
        return root.request("PUT", url, body, options, callback);
    }

    function del(url: string, options: var, callback: var): int {
        return root.request("DELETE", url, null, options, callback);
    }

    // Fire and forget, for a ping that nobody reads.
    function head(url: string, options: var, callback: var): int {
        return root.request("HEAD", url, null, options, callback);
    }

    // ----------------------------------------------------------------- request

    function request(method: string, url: string, body: var, options: var, callback: var): int {
        const opts = options ?? ({});
        const pluginId = String(opts.pluginId ?? "");
        const full = root.__withQuery(String(url ?? ""), opts.query);

        if (full.length === 0) {
            root.__deliver(callback, root.__failure("", "no URL given"), opts);
            return 0;
        }

        if (pluginId && !PluginPermissions.check(pluginId, "network", qsTr("reach %1").arg(root.hostOf(full))))
            return 0;

        const ttl = Math.max(0, opts.cacheTtl ?? 0);
        const key = `${method} ${full}`;

        if (ttl > 0) {
            const hit = root.__cache[key];
            if (hit && (Date.now() - hit.at) < ttl) {
                // Synchronous delivery would run the callback before the caller has finished
                // its own function - a plugin assigning `loading = true` after the call would
                // then leave a spinner up forever. Always a turn later, cache or not.
                const cached = Object.assign({}, hit.response);
                cached.fromCache = true;
                Qt.callLater(() => root.__deliver(callback, cached, opts));
                return 0;
            }
        }

        if (!root.enabled) {
            const stale = root.__cache[key];
            if (stale) {
                const offline = Object.assign({}, stale.response);
                offline.fromCache = true;
                offline.error = "offline: served from cache";
                Qt.callLater(() => root.__deliver(callback, offline, opts));
                return 0;
            }
            root.__deliver(callback, root.__failure(full, "networking is switched off"), opts);
            return 0;
        }

        const id = root.__nextId++;
        const started = Date.now();
        const timeoutMs = Math.max(250, opts.timeoutMs ?? root.defaultTimeoutMs);

        const xhr = new XMLHttpRequest();
        const active = Object.assign({}, root.__active);
        active[id] = { xhr: xhr, url: full, at: started, pluginId: pluginId };
        root.__active = active;

        // Qt's XHR has a timeout property but it is unreliable across backends, so the
        // timeout is enforced here and the request aborted. Belt and braces, and the same
        // behaviour everywhere.
        const timer = timeoutComponent.createObject(root, { interval: timeoutMs });
        timer.triggered.connect(() => {
            if (!root.__active[id])
                return;
            root.__finish(id);
            try {
                xhr.abort();
            } catch (e) {
                // Aborting an already-finished request throws on some backends; harmless.
            }
            root.__deliver(callback, root.__failure(full, `timed out after ${timeoutMs} ms`, 0, Date.now() - started), opts);
            timer.destroy();
        });
        timer.start();

        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (!root.__active[id])
                return;   // already timed out or cancelled

            root.__finish(id);
            timer.stop();
            timer.destroy();

            const response = root.__responseOf(xhr, full, started, opts);
            if (response.ok && ttl > 0)
                root.__store(key, response);
            root.__deliver(callback, response, opts);
        };

        try {
            xhr.open(method, full);

            const headers = opts.headers ?? ({});
            for (const name of Object.keys(headers))
                xhr.setRequestHeader(name, String(headers[name]));

            let payload = null;
            if (body !== null && body !== undefined) {
                if (typeof body === "string") {
                    payload = body;
                } else {
                    payload = JSON.stringify(body);
                    if (headers["Content-Type"] === undefined)
                        xhr.setRequestHeader("Content-Type", "application/json");
                }
            }

            xhr.send(payload);
        } catch (e) {
            root.__finish(id);
            timer.stop();
            timer.destroy();
            root.__deliver(callback, root.__failure(full, `could not start the request: ${e}`), opts);
            return 0;
        }

        return id;
    }

    // ------------------------------------------------------------ cancellation

    function cancel(id: int): bool {
        const entry = root.__active[id];
        if (!entry)
            return false;
        root.__finish(id);
        try {
            entry.xhr.abort();
        } catch (e) {
        }
        return true;
    }

    // Everything a plugin has in flight. Called when a plugin is switched off, so its
    // requests do not land in a shell that no longer has it.
    function cancelFor(pluginId: string): int {
        let cancelled = 0;
        for (const id of Object.keys(root.__active)) {
            if (root.__active[id].pluginId !== pluginId)
                continue;
            if (root.cancel(parseInt(id)))
                cancelled += 1;
        }
        return cancelled;
    }

    function cancelAll(): int {
        let cancelled = 0;
        for (const id of Object.keys(root.__active)) {
            if (root.cancel(parseInt(id)))
                cancelled += 1;
        }
        return cancelled;
    }

    // ------------------------------------------------------------------- cache

    function clearCache(): int {
        const count = Object.keys(root.__cache).length;
        root.__cache = ({});
        root.__cacheOrder = [];
        return count;
    }

    readonly property int cacheEntries: Object.keys(root.__cache).length

    function cacheStats(): var {
        let bytes = 0;
        for (const key of Object.keys(root.__cache))
            bytes += (root.__cache[key].response.body ?? "").length;
        return { entries: Object.keys(root.__cache).length, bytes: bytes, inFlight: root.inFlight };
    }

    // --------------------------------------------------------------- internals

    function hostOf(url: string): string {
        const match = /^[a-z]+:\/\/([^\/:?#]+)/i.exec(url ?? "");
        return match ? match[1] : (url ?? "");
    }

    function __withQuery(url: string, query: var): string {
        if (!query || typeof query !== "object")
            return url;
        const parts = [];
        for (const key of Object.keys(query)) {
            const value = query[key];
            if (value === undefined || value === null)
                continue;
            parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(String(value))}`);
        }
        if (parts.length === 0)
            return url;
        return url + (url.includes("?") ? "&" : "?") + parts.join("&");
    }

    function __responseOf(xhr: var, url: string, started: real, opts: var): var {
        const status = xhr.status;
        const body = xhr.responseText ?? "";
        const contentType = (xhr.getResponseHeader("content-type") ?? "").toLowerCase();

        let parsed = null;
        const looksJson = opts.json === true || contentType.includes("json")
            || /^\s*[\[{]/.test(body);
        if (looksJson && body.length > 0) {
            try {
                parsed = JSON.parse(body);
            } catch (e) {
                parsed = null;
            }
        }

        const ok = status >= 200 && status < 300;
        return {
            ok: ok,
            status: status,
            body: body,
            json: parsed,
            headers: xhr.getAllResponseHeaders ? (xhr.getAllResponseHeaders() ?? "") : "",
            error: ok ? "" : (status === 0 ? "no response - offline or DNS failure" : `HTTP ${status}`),
            fromCache: false,
            url: url,
            elapsedMs: Date.now() - started
        };
    }

    function __failure(url: string, message: string, status: int, elapsed: real): var {
        return {
            ok: false,
            status: status ?? 0,
            body: "",
            json: null,
            headers: "",
            error: message,
            fromCache: false,
            url: url,
            elapsedMs: elapsed ?? 0
        };
    }

    function __store(key: string, response: var): void {
        const cache = Object.assign({}, root.__cache);
        cache[key] = { at: Date.now(), response: response };

        let order = root.__cacheOrder.filter(existing => existing !== key).concat([key]);
        while (order.length > root.maxCacheEntries) {
            delete cache[order[0]];
            order = order.slice(1);
        }

        root.__cache = cache;
        root.__cacheOrder = order;
    }

    function __finish(id: var): void {
        const active = Object.assign({}, root.__active);
        delete active[id];
        root.__active = active;
    }

    // The one place a plugin's callback is called. Everything about *not* calling it lives
    // here: a destroyed owner, a callback that is not a function, a throw inside it.
    function __deliver(callback: var, response: var, opts: var): void {
        if (typeof callback !== "function")
            return;

        const owner = opts?.owner ?? null;
        // A destroyed QObject is falsy in Qt's JS bindings, which is the documented way to
        // test for it and the whole reason `owner` is worth passing.
        if (owner !== null && owner !== undefined && !owner)
            return;

        try {
            callback(response);
        } catch (e) {
            console.warn(`[http] callback for ${response.url} threw:`, e);
        }
    }

    readonly property Component timeoutComponent: Component {
        Timer {
            repeat: false
        }
    }
}
