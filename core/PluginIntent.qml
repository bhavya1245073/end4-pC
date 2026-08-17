pragma Singleton

// One way to invoke anything a plugin can do.
//
// A plugin declares an action in its manifest and implements it in one place. From then on
// it is reachable from the launcher, from a keybind, from the command line, from a context
// menu and from another plugin - without the plugin knowing any of those exist.
//
//     "actions": [{
//         "id": "search",
//         "label": "Search GIFs",
//         "description": "Find an animated GIF",
//         "icon": "gif",
//         "schema": { "query": { "type": "string", "required": true } }
//     }]
//
// The plugin registers a handler once, usually in the service it already has:
//
//     PluginIntentHandler {
//         pluginId: "gif-picker"
//         action: "search"
//         onInvoked: args => GifState.search(args.query)
//     }
//
// And then every one of these works:
//
//     PluginIntent.call("gif-picker:search", { query: "celebrate" })   // from another plugin
//     qs -c end4-pC ipc call intent call gif-picker:search query=cat   // from a terminal
//     type "gif cat" in the launcher                                   // from the launcher
//
// ## Why not just call the plugin's singleton
//
// Because a plugin cannot import another plugin. Plugin QML is loaded from a URL at runtime
// and its singletons are not in any module the other one can name, so peer-to-peer calls
// have no path - which is why cross-plugin features never got written. An intent is a
// string, and a string always resolves.
//
// ## Arguments are validated, not trusted
//
// The manifest's `schema` is checked before the handler runs: missing required arguments,
// wrong types, and unknown keys are all reported to the caller as a failed result rather
// than reaching plugin code. A handler can therefore read `args.query` without guarding it,
// which is the whole point of declaring a schema.

import QtQuick
import Quickshell
import qs.core

Singleton {
    id: root

    // ---------------------------------------------------------------- registry

    // Every declared action, tagged with its plugin. Comes from the manifests, so an action
    // is listed - and shows in the launcher - even before its plugin's QML has loaded.
    readonly property var actions: PluginRegistry.collect("actions")
        .filter(action => (action.id ?? "").length > 0)
        .map(action => Object.assign({
            ref: `${action.pluginId}:${action.id}`,
            label: action.label ?? action.id,
            description: action.description ?? "",
            icon: action.icon ?? "bolt",
            schema: action.schema ?? ({}),
            keywords: action.keywords ?? []
        }, action))

    // ref -> handler object. Handlers register themselves; PluginIntentHandler does it.
    property var handlers: ({})

    function register(ref: string, handler: var): void {
        if (!ref || ref.indexOf(":") === -1) {
            console.warn(`[intent] refusing to register "${ref}": expected "pluginId:actionId"`);
            return;
        }
        const next = Object.assign({}, root.handlers);
        next[ref] = handler;
        root.handlers = next;
    }

    function unregister(ref: string): void {
        if (root.handlers[ref] === undefined)
            return;
        const next = Object.assign({}, root.handlers);
        delete next[ref];
        root.handlers = next;
    }

    function describe(ref: string): var {
        return root.actions.find(action => action.ref === ref) ?? null;
    }

    function has(ref: string): bool {
        return root.handlers[ref] !== undefined || root.__ipcFor(ref) !== null;
    }

    // An action needs no handler object if the plugin already exposes an IPC function of the same
    // name. Most do: a plugin that can be driven from the command line has written the function
    // once, and declaring an action is then all it takes to also be reachable from the launcher,
    // from a keybind, and from other plugins.
    //
    // The IPC object is registered by PluginIpc itself and lives as long as the plugin is on, so
    // this resolves exactly when the plugin is loaded - which is the same lifetime a handler
    // object would have had, without the object.
    //
    // Looked up rather than cached: the target's own registration comes and goes with the plugin.
    function __ipcFor(ref: string): var {
        const parts = String(ref ?? "").split(":");
        if (parts.length !== 2)
            return null;

        const pluginId = parts[0];
        const name = parts[1];

        // The manifest may name a nicer IPC target than the plugin id, so try both.
        const declared = PluginRegistry.collect("ipc").find(entry => entry.pluginId === pluginId);
        for (const target of [declared?.target, pluginId]) {
            if (!target)
                continue;
            const handler = PluginRegistry.ipcTargets[target];
            if (handler && typeof handler[name] === "function")
                return { handler: handler, name: name };
        }
        return null;
    }

    // Declared in a manifest but with nothing implementing it. The usual cause is a plugin
    // that is switched off, which is not an error - but a handler missing while the plugin
    // is on is a bug worth surfacing, and doctor.sh reports it.
    readonly property var unimplemented: root.actions
        .filter(action => PluginRegistry.isActive(action.pluginId) && !root.has(action.ref))
        .map(action => action.ref)

    // ------------------------------------------------------------------- calling

    // Returns { ok, ref, error, result }. Never throws: a caller may be an IPC handler, a
    // launcher row or another plugin, and none of them can do anything useful with an
    // exception.
    function call(ref: string, args: var): var {
        const target = String(ref ?? "");
        const action = root.describe(target);
        const handler = root.handlers[target];
        const viaIpc = handler ? null : root.__ipcFor(target);

        if (!action && !handler && !viaIpc)
            return root.__fail(target, `no such action; try one of: ${root.refs().slice(0, 6).join(", ")}`);

        const pluginId = target.split(":")[0];
        if (action && !PluginRegistry.isActive(pluginId))
            return root.__fail(target, `${pluginId} is switched off`);

        if (!handler && !viaIpc) {
            // Declared, plugin on, nothing implementing it - neither a PluginIntentHandler nor an
            // IPC function of the same name. Almost always a plugin whose service has not
            // finished loading, so it is worth saying which.
            return root.__fail(target, `${pluginId} declares "${target.split(":")[1]}" but nothing is handling it yet`);
        }

        const validation = root.validate(target, args);
        if (!validation.ok)
            return root.__fail(target, validation.error);

        try {
            const result = handler
                ? handler.invoke(validation.args)
                : root.__callIpc(viaIpc, action, validation.args);
            root.__record(target, validation.args, true, "");
            return { ok: true, ref: target, error: "", result: result === undefined ? null : result };
        } catch (e) {
            root.__record(target, validation.args, false, String(e));
            console.warn(`[intent] ${target} threw:`, e);
            return root.__fail(target, `the plugin threw: ${e}`);
        }
    }

    // IPC functions take positional parameters; an intent carries named ones. The manifest's
    // schema is what maps between them: arguments are passed in the order the schema declares
    // them, which is why a schema key order is worth keeping stable.
    function __callIpc(via: var, action: var, args: var): var {
        const names = Object.keys(action?.schema ?? {});
        const positional = names.map(name => args[name]);
        return via.handler[via.name].apply(via.handler, positional);
    }

    // Same, but reports failures to the user rather than only to the caller. What a launcher
    // row or a keybind wants: the user pressed something and deserves to know it did nothing.
    function invoke(ref: string, args: var): bool {
        const outcome = root.call(ref, args);
        if (!outcome.ok) {
            PluginToast.show({
                text: outcome.error,
                tone: "error",
                icon: "bolt",
                pluginId: String(ref ?? "").split(":")[0]
            });
        }
        return outcome.ok;
    }

    function refs(): var {
        return root.actions.map(action => action.ref);
    }

    // --------------------------------------------------------------- validation

    // Checks `args` against the action's declared schema and returns
    // { ok, args, error } with defaults filled in and numbers coerced.
    function validate(ref: string, args: var): var {
        const action = root.describe(ref);
        const given = (args && typeof args === "object") ? args : ({});
        if (!action)
            return { ok: true, args: given, error: "" };   // undeclared: pass through untouched

        const schema = action.schema ?? ({});
        const names = Object.keys(schema);
        const checked = {};

        for (const name of names) {
            const spec = schema[name] ?? ({});
            const type = spec.type ?? "string";
            let value = given[name];

            if (value === undefined || value === null || value === "") {
                if (spec.default !== undefined) {
                    checked[name] = spec.default;
                    continue;
                }
                if (spec.required === true)
                    return { ok: false, args: given, error: `"${name}" is required` };
                continue;
            }

            // Coerced rather than rejected: everything arriving over IPC is a string, and
            // refusing "5" for an int would make the CLI useless.
            if (type === "int" || type === "real") {
                const number = Number(value);
                if (!isFinite(number))
                    return { ok: false, args: given, error: `"${name}" must be a number, got "${value}"` };
                checked[name] = type === "int" ? Math.round(number) : number;
                continue;
            }

            if (type === "bool") {
                if (typeof value === "boolean") {
                    checked[name] = value;
                } else {
                    const text = String(value).toLowerCase();
                    if (!["true", "false", "1", "0", "yes", "no"].includes(text))
                        return { ok: false, args: given, error: `"${name}" must be true or false, got "${value}"` };
                    checked[name] = ["true", "1", "yes"].includes(text);
                }
                continue;
            }

            if (type === "path") {
                // Expanded here so every handler does not have to: a path typed in a terminal
                // or a launcher is routinely relative or ~-prefixed.
                checked[name] = PluginFs.expand(String(value));
                continue;
            }

            if (Array.isArray(spec.oneOf) && spec.oneOf.length > 0 && !spec.oneOf.includes(String(value)))
                return { ok: false, args: given, error: `"${name}" must be one of ${spec.oneOf.join(", ")}` };

            checked[name] = String(value);
        }

        // Unknown keys are dropped with a warning rather than refused: an old caller passing
        // an argument a newer plugin removed should still work.
        for (const name of Object.keys(given)) {
            if (schema[name] === undefined)
                console.warn(`[intent] ${ref}: ignoring unknown argument "${name}"`);
        }

        return { ok: true, args: checked, error: "" };
    }

    // ------------------------------------------------------------------ search

    // Rows for the launcher. Matches the action label, its plugin name, its id and its
    // keywords, and treats everything after the matched word as the first required argument -
    // so "gif cat" fills `query` with "cat" and runs it inline.
    function match(query: string): var {
        const text = String(query ?? "").trim();
        if (text.length === 0)
            return [];

        const lower = text.toLowerCase();
        const firstWord = lower.split(/\s+/)[0];
        const rest = text.slice(firstWord.length).trim();

        const rows = [];
        for (const action of root.actions) {
            if (!PluginRegistry.isActive(action.pluginId))
                continue;

            const haystack = [
                action.id,
                action.label,
                action.pluginId,
                action.pluginName ?? "",
                (action.keywords ?? []).join(" ")
            ].join(" ").toLowerCase();

            // Two ways in: the whole query is a prefix of something (typing "gif p" while
            // deciding), or the first word alone identifies the action and the rest is its
            // argument ("gif cat").
            const wholeMatches = haystack.includes(lower);
            const wordMatches = firstWord.length >= 2 && haystack.includes(firstWord);
            if (!wholeMatches && !wordMatches)
                continue;

            const primary = root.__primaryArgument(action);
            const args = (primary && rest.length > 0) ? root.__argsWith(primary, rest) : ({});
            const needsMore = primary !== "" && rest.length === 0
                && (action.schema?.[primary]?.required === true);

            rows.push({
                ref: action.ref,
                pluginId: action.pluginId,
                name: action.label,
                subtitle: needsMore
                    ? qsTr("type %1 after the name").arg(primary)
                    : (rest.length > 0 && primary ? `${action.label}: ${rest}` : (action.description ?? action.pluginName ?? "")),
                icon: action.icon,
                // Score: an exact id match beats a label match beats a keyword match, and a
                // filled-in argument beats an incomplete one.
                score: (action.id.toLowerCase() === firstWord ? 100 : 0)
                    + (action.label.toLowerCase().startsWith(lower) ? 50 : 0)
                    + (needsMore ? 0 : 10),
                ready: !needsMore,
                args: args
            });
        }

        return rows.sort((a, b) => b.score - a.score);
    }

    // The argument a launcher query's trailing text goes into: the first required one, or the
    // first declared one.
    function __primaryArgument(action: var): string {
        const schema = action.schema ?? ({});
        const names = Object.keys(schema);
        return names.find(name => schema[name]?.required === true) ?? names[0] ?? "";
    }

    function __argsWith(name: string, value: string): var {
        const args = {};
        args[name] = value;
        return args;
    }

    // ------------------------------------------------------------------- audit

    // The last calls made, newest first. What `qs ipc call intent recent` prints, and the
    // fastest way to find out why a keybind "does nothing".
    property var recent: []
    readonly property int recentLimit: 40

    function __record(ref: string, args: var, ok: bool, error: string): void {
        const entry = { ref: ref, args: args, ok: ok, error: error, at: Date.now() };
        root.recent = [entry].concat(root.recent).slice(0, root.recentLimit);
    }

    function __fail(ref: string, message: string): var {
        root.__record(ref, ({}), false, message);
        return { ok: false, ref: ref, error: message, result: null };
    }

    // ------------------------------------------------------------------- CLI

    // Parses `key=value key2="two words"` as sent by the IPC target. Quoting is honoured so a
    // value with spaces survives, which is the only reason this is not a split on "=".
    function parseArgs(text: string): var {
        const args = {};
        const source = String(text ?? "").trim();
        if (source.length === 0)
            return args;

        const pattern = /([A-Za-z_][A-Za-z0-9_-]*)=("([^"]*)"|'([^']*)'|(\S+))/g;
        let match = pattern.exec(source);
        let matched = false;
        while (match !== null) {
            matched = true;
            args[match[1]] = match[3] ?? match[4] ?? match[5] ?? "";
            match = pattern.exec(source);
        }

        // A bare value with no key at all goes to the primary argument, so
        // `ipc call intent call gif-picker:search cat` works like the launcher does.
        if (!matched)
            args.__positional = source;
        return args;
    }

    // Resolves __positional against the action's schema. Kept separate from parseArgs so the
    // parser stays a pure string function.
    function withPositional(ref: string, args: var): var {
        const positional = args?.__positional;
        if (positional === undefined)
            return args;

        const action = root.describe(ref);
        const copy = Object.assign({}, args);
        delete copy.__positional;
        if (!action)
            return copy;

        const primary = root.__primaryArgument(action);
        if (primary)
            copy[primary] = positional;
        return copy;
    }
}
