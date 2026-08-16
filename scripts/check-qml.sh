#!/usr/bin/env bash
# check-qml.sh — Compile every QML file in the shell tree and report the ones
# that fail to resolve their imports or types.
#
# Nothing is instantiated, so no windows appear and the running shell is not
# touched. Needs a Wayland session (Quickshell won't start without one).
#
#   scripts/check-qml.sh                  # whole tree, then the plugin entry points
#   scripts/check-qml.sh plugins          # one or more subtrees
#
# Exit status is 0 only when everything passed, so this is usable in a hook.
#
# ## Three things make this work, and all three used to be wrong
#
# 1. **The harness has to import what the tree imports.** A synthetic `qs.*`
#    module only exists once something has *statically* imported it, and an import
#    inside a dynamically created component is too late. So this harness is
#    generated with a static `import` for every `qs.*` module the tree mentions.
#    Without them a pristine tree reported 76 "module is not installed" failures.
#
#    The shell itself has the same problem, which is what `core/PluginModuleAnchors.qml`
#    is for. Do not let this harness paper over a missing anchor: phase 2 below is
#    the check that would catch one.
#
# 2. **`file://` URLs, deliberately.** That is what `core/PluginRegistry.qml`
#    resolves plugin entries to, so compiling the same way tests the path a
#    plugin is really loaded through. (Quickshell also exposes the tree as a
#    virtual `qs:` filesystem; compiling from there works too, but it registers
#    each directory as a module, and plugin folders cannot be modules because
#    their names contain hyphens.)
#
# 3. **Compiling every file individually is not enough, and can lie.** The engine
#    caches compiled types by name, so compiling an internal file the shell never
#    loads directly can bind a name early and hide a genuine clash. That is not
#    hypothetical: `plugins/overlay/notes/Notes.qml` clashed with the `Notes`
#    singleton in `qs.services`, the whole overlay plugin failed to load in the
#    real shell, and phase 1 reported failures=0 because it had already compiled
#    `Notes.qml` on its own.
#
#    So phase 2 compiles only what the shell actually loads — each plugin's
#    declared manifest entries — which is a closer reproduction but still shares one
#    engine, so treat it as best-effort. Phase 3 is the deterministic one: it looks
#    for the name clashes that make the other two order-dependent at all, and it is
#    what catches the `Notes` class of bug reliably.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS="$ROOT/.qml-check-harness.qml"

cd "$ROOT"

[[ $# -gt 0 ]] || set -- .
mapfile -t files < <(find "$@" -name '*.qml' -not -name '.qml-check-harness.qml' | sort)
[[ ${#files[@]} -gt 0 ]] || { echo "no .qml files under $*"; exit 1; }

# Every `qs.*` module the tree imports, whether or not it is in the subtree being
# checked: a file under plugins/ still needs qs.modules.common to resolve.
mapfile -t wanted < <(
    grep -rhoE '^[[:space:]]*import[[:space:]]+qs(\.[A-Za-z0-9_]+)*' --include='*.qml' . \
        | sed -E 's/^[[:space:]]*import[[:space:]]+//' \
        | sort -u
)

# A module whose directory is gone is a dangling import — the one class of
# breakage that compiling cannot report, because the harness would fail to build
# instead of blaming a file. Reported here and left out of the harness.
imports=""
dangling=()
for module in "${wanted[@]}"; do
    relative="${module#qs}"
    relative="${relative#.}"
    directory="${relative//./\/}"

    if [[ -z "$directory" || -d "$directory" ]]; then
        imports+="import $module"$'\n'
    else
        dangling+=("$module -> $directory")
    fi
done

if (( ${#dangling[@]} )); then
    echo "==> Imports with no directory behind them:"
    for entry in "${dangling[@]}"; do
        echo "    DANGLING $entry"
        grep -rln "import[[:space:]]\+${entry%% ->*}\b" --include='*.qml' . | sed 's/^/             /'
    done
fi

targets=""
for f in "${files[@]}"; do
    targets+="file://$ROOT/${f#./},"
done

{
    printf 'import QtQuick\nimport Quickshell\n'
    # Ambiguity between same-named types in two modules is only an error at a use
    # site, and the harness never uses one; the imports are here to register the
    # modules, nothing more.
    printf '%s' "$imports"
    cat <<'QML'

ShellRoot {
    Component.onCompleted: {
        const targets = (Quickshell.env("QMLCHECK_TARGETS") ?? "").split(",").filter(t => t.length > 0);
        let failed = 0;
        for (const t of targets) {
            // file://, matching how core/PluginRegistry.qml resolves plugin
            // entries; the qs.* modules a target imports are already registered
            // by this file's own imports.
            const c = Qt.createComponent(t, Component.PreferSynchronous);
            if (c.status === Component.Error) {
                failed++;
                console.log("QMLCHECK FAIL " + t);
                console.log(c.errorString());
            }
        }
        console.log("QMLCHECK DONE checked=" + targets.length + " failures=" + failed);
    }
}
QML
} > "$HARNESS"

echo "==> Compiling ${#files[@]} QML files under $* (${#wanted[@]} qs.* modules in scope)..."

# Quickshell has no QML-side exit (`Quickshell.quit` does not exist and
# `Qt.exit` has no receiver), so the harness cannot stop itself: it prints a DONE
# marker and this script ends the process. The previous version relied on awk
# closing the pipe and SIGPIPE killing qs, which is why it could not report an
# exit status.
log="$(mktemp -t qml-check.XXXXXX)"
trap 'rm -f "$HARNESS" "$log"' EXIT

QMLCHECK_TARGETS="$targets" qs -p "$HARNESS" >"$log" 2>&1 &
qs_pid=$!

deadline=$(( $(date +%s) + 900 ))
while :; do
    grep -q 'QMLCHECK DONE ' "$log" 2>/dev/null && break
    kill -0 "$qs_pid" 2>/dev/null || break
    (( $(date +%s) < deadline )) || { echo "check-qml.sh: timed out after 900s" >&2; break; }
    sleep 0.1
done

kill "$qs_pid" 2>/dev/null || true
wait "$qs_pid" 2>/dev/null || true

summary="$(
    sed 's/\x1b\[[0-9;]*m//g' "$log" \
        | sed -n 's/^ *DEBUG qml: //p' \
        | sed "s|file://$ROOT/||g" \
        | awk '
            /^QMLCHECK FAIL / { print "FAIL " $3; inside = 1; next }
            /^QMLCHECK DONE / { print; inside = 0; next }
            inside && length($0) { print "      " $0 }
        '
)"

if [[ -n "$summary" ]]; then
    echo "$summary"
fi

status=0

if (( ${#dangling[@]} )); then
    status=1
fi

if ! grep -q '^QMLCHECK DONE ' <<<"$summary"; then
    echo "check-qml.sh: the harness did not run to completion; full log:" >&2
    sed 's/\x1b\[[0-9;]*m//g' "$log" | tail -30 >&2
    status=1
elif ! grep -q 'failures=0$' <<<"$summary"; then
    status=1
fi

# ---------------------------------------------------------------------------
# Phase 2: everything the shell loads by URL rather than by static import.
#
# Plugin entry points, plus the built-in desktop widgets, which are now loaded from
# DesktopWidgetRegistry by URL too. Only the imports shell.qml really has, so a
# module the core forgot to anchor shows up here rather than at runtime.
#
# This phase matters because a `qs.foo` module only exists once something statically
# compiled imports it. A file that resolves fine when compiled as part of a module
# can fail when the same file is fetched by URL - which is how the clock widget broke
# the moment it stopped being statically imported by Background.qml, since the type
# it needed lived in a sibling file in its own directory.
#
# Still one engine for all of them, so this does not fully escape the cache
# ordering described above - phase 3 is the deterministic check.
# Skipped when a subtree was named, since then the run is deliberately partial.
# ---------------------------------------------------------------------------

if [[ "$*" == "." ]] && command -v jq >/dev/null 2>&1; then
    entries=""
    for manifest in "$ROOT"/plugins/*/manifest.json; do
        [[ -e "$manifest" ]] || continue
        dir="$(dirname "$manifest")"
        while read -r entry; do
            [[ -n "$entry" && "$entry" != "null" ]] || continue
            entries+="file://$dir/$entry,"
        done < <(jq -r '(.provides // {}) | to_entries[] | .value[]? | .entry // empty' "$manifest")
    done

    # The built-in desktop widgets, read straight out of the registry's table so this
    # cannot drift from what the shell actually loads.
    while read -r path; do
        [[ -n "$path" ]] || continue
        entries+="file://$ROOT/modules/ii/background/widgets/$path,"
    done < <(sed -n 's/.*path: "\([^"]*\)".*/\1/p' "$ROOT/core/DesktopWidgetRegistry.qml")

    entryHarness="$ROOT/.qml-check-entries.qml"
    entryLog="$(mktemp -t qml-entries.XXXXXX)"
    trap 'rm -f "$HARNESS" "$log" "$entryHarness" "$entryLog"' EXIT

    # Only the imports shell.qml really has. Anything a plugin needs must come
    # from core/PluginModuleAnchors.qml, which is the point of the exercise.
    cat >"$entryHarness" <<'QML'
import QtQuick
import Quickshell
import qs.core

ShellRoot {
    PluginModuleAnchors {}

    Component.onCompleted: {
        const targets = (Quickshell.env("QMLCHECK_TARGETS") ?? "").split(",").filter(t => t.length > 0);
        let failed = 0;
        for (const t of targets) {
            const c = Qt.createComponent(t, Component.PreferSynchronous);
            if (c.status === Component.Error) {
                failed++;
                console.log("QMLCHECK FAIL " + t);
                console.log(c.errorString());
            }
        }
        console.log("QMLCHECK DONE checked=" + targets.length + " failures=" + failed);
    }
}
QML

    entryCount=$(( $(tr -cd ',' <<<"$entries" | wc -c) ))
    echo "==> Loading $entryCount URL-loaded entry point(s) the way the shell does..."

    QMLCHECK_TARGETS="$entries" qs -p "$entryHarness" >"$entryLog" 2>&1 &
    entry_pid=$!

    deadline=$(( $(date +%s) + 300 ))
    while :; do
        grep -q 'QMLCHECK DONE ' "$entryLog" 2>/dev/null && break
        kill -0 "$entry_pid" 2>/dev/null || break
        (( $(date +%s) < deadline )) || { echo "check-qml.sh: entry phase timed out" >&2; break; }
        sleep 0.1
    done

    kill "$entry_pid" 2>/dev/null || true
    wait "$entry_pid" 2>/dev/null || true

    entrySummary="$(
        sed 's/\x1b\[[0-9;]*m//g' "$entryLog" \
            | sed -n 's/^ *DEBUG qml: //p' \
            | sed "s|file://$ROOT/||g" \
            | awk '
                /^QMLCHECK FAIL / { print "FAIL " $3; inside = 1; next }
                /^QMLCHECK DONE / { print; inside = 0; next }
                inside && length($0) { print "      " $0 }
            '
    )"

    [[ -n "$entrySummary" ]] && echo "$entrySummary"

    if ! grep -q '^QMLCHECK DONE ' <<<"$entrySummary"; then
        echo "check-qml.sh: the entry harness did not run to completion; full log:" >&2
        sed 's/\x1b\[[0-9;]*m//g' "$entryLog" | tail -30 >&2
        status=1
    elif ! grep -q 'failures=0$' <<<"$entrySummary"; then
        status=1
    fi
fi

# ---------------------------------------------------------------------------
# Phase 3: type names that also name a singleton.
#
# Two types with one name, one of them a singleton, resolve to whichever the
# engine bound first. The loser fails with "qmldir defines type as singleton, but
# no pragma Singleton found", and which one loses depends on load order, so it can
# work for months and then not.
#
# Only a clash whose plain type is instantiated *by name* can actually bite — a
# file loaded by URL never has its name resolved, which is why the two
# `pages/*Config.qml` that shadow service singletons are harmless. Those are
# reported as notes; a name that is really used is an error.
# ---------------------------------------------------------------------------

mapfile -t singletonFiles < <(grep -rl '^pragma Singleton' --include='*.qml' . | sort)

singletonNames=""
for f in "${singletonFiles[@]}"; do
    singletonNames+="$(basename "$f" .qml)"$'\n'
done

clashes=0
notes=0

while read -r file; do
    [[ -n "$file" ]] || continue
    grep -q '^pragma Singleton' "$file" && continue

    name="$(basename "$file" .qml)"
    grep -qxF "$name" <<<"$singletonNames" || continue

    owner="$(printf '%s\n' "${singletonFiles[@]}" | grep -E "/$name\.qml$" | head -1)"

    # Used as a type anywhere? `Name {` is how QML instantiates one.
    if grep -rqE "(^|[^A-Za-z0-9_.])$name[[:space:]]*\{" --include='*.qml' .; then
        (( clashes == 0 )) && echo "==> Type names that also name a singleton:"
        clashes=$(( clashes + 1 ))
        echo "    CLASH $name is instantiated by name, and both of these define it:"
        echo "          singleton  ${owner#./}"
        echo "          plain type ${file#./}"
    else
        (( notes == 0 )) && echo "==> Shadowed singleton names (loaded by URL only, so harmless):"
        notes=$(( notes + 1 ))
        echo "    NOTE  $name  ${file#./}  shadows  ${owner#./}"
    fi
done < <(find . -name '*.qml' -not -path './.git/*' | sort)

if (( clashes )); then
    status=1
fi

# ---------------------------------------------------------------------------
# Phase 4: singletons used without importing the module that provides them.
#
# `QuickToggleRegistry.foo` in a file that never imported qs.core compiles cleanly -
# an unresolved name inside a JS binding is a runtime error, not a compile one - and
# then silently evaluates to undefined forever. That is exactly how AndroidQuickPanel
# ended up with an empty toggle list while every phase above reported success.
#
# Deterministic: pure text, no engine, no cache ordering.
# ---------------------------------------------------------------------------

missing=0

check_singleton_imports() {
    local dir="$1" module="$2" file name base
    base="$(basename "$dir")"

    for file in "$dir"/*.qml; do
        [[ -e "$file" ]] || continue
        grep -q '^pragma Singleton' "$file" || continue
        name="$(basename "$file" .qml)"

        # Member access is how a singleton is used. Strip line comments first so a
        # mention in prose does not count.
        while read -r user; do
            # Same directory resolves implicitly, and the file itself is not a user.
            [[ "$(dirname "$user")" == "$dir" ]] && continue
            # Either form registers the module: `import qs.services`, or the
            # directory-relative `import "services"` / `import "../services"` that
            # shell.qml uses.
            grep -qE "^import[[:space:]]+$module([[:space:]]|$)" "$user" && continue
            grep -qE "^import[[:space:]]+\"([^\"]*/)?$base\"" "$user" && continue
            (( missing == 0 )) && echo "==> Singletons used without importing their module:"
            missing=$(( missing + 1 ))
            echo "    MISSING $module in ${user#./}  (uses $name)"
        done < <(
            grep -rlE "(^|[^A-Za-z0-9_.\"'])$name\.[A-Za-z_]" --include='*.qml' . \
                --exclude-dir=.git \
                | while read -r cand; do
                    sed 's#//.*##' "$cand" \
                        | grep -qE "(^|[^A-Za-z0-9_.\"'])$name\.[A-Za-z_]" && echo "$cand"
                done
        )
    done
}

if [[ "$*" == "." ]]; then
    check_singleton_imports "./core" "qs.core"
    check_singleton_imports "./services" "qs.services"

    if (( missing )); then
        status=1
    else
        echo "==> Singleton imports: all $(( $(ls ./core/*.qml ./services/*.qml 2>/dev/null | wc -l) )) candidates resolve"
    fi
fi

# ---------------------------------------------------------------------------
# Phase 5: required properties in anything loaded by URL.
#
# A component with an uninitialised `required` property cannot be constructed, so a
# Loader resolving it from an id reports Loader.Error and you get an empty space. It
# compiles, and Qt.createComponent succeeds - the failure is at instantiation - so no
# phase above sees it.
#
# The declaration is usually not in the entry file but in a base type a few levels up,
# which is where both real occurrences were: AbstractBackgroundWidget's five geometry
# properties and AndroidQuickToggleButton's seven grid properties.
# ---------------------------------------------------------------------------

required_offenders=0

root_type_of() {
    # `|| true` throughout: a grep that matches nothing exits 1, and under
    # `set -e -o pipefail` that aborts the whole script from inside a command
    # substitution - silently, because the output is being captured.
    {
        sed 's#//.*##' "$1" \
            | grep -oE '^[A-Za-z][A-Za-z0-9_]*[[:space:]]*\{' \
            | head -1 \
            | sed 's/[[:space:]]*{//'
    } || true
}

file_for_type() {
    local type="$1" near="$2" hit
    [[ -n "$type" ]] || return 1
    # Same directory first, which is how QML resolves it.
    [[ -e "$near/$type.qml" ]] && { echo "$near/$type.qml"; return 0; }
    hit="$(find . -name "$type.qml" -not -path './.git/*' | head -1)"
    [[ -n "$hit" ]] && { echo "$hit"; return 0; }
    return 1
}

check_no_required() {
    local entry="$1"
    local file="$entry"
    local depth=0 type
    local chain="" required="" unsatisfied=""

    # Walk the inheritance chain, collecting it and every root-level `required property`.
    # Root-level means indented exactly four spaces: a required property deeper than that
    # belongs to a nested Repeater or Instantiator delegate, where it is not only legal
    # but the recommended way to take modelData.
    while [[ -n "$file" && -e "$file" ]] && (( depth < 6 )); do
        chain+="$file"$'\n'
        required+="$(grep -E '^    required[[:space:]]+property[[:space:]]' "$file" \
            | sed -E 's/.*[[:space:]]([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*$/\1/' || true)"$'\n'
        type="$(root_type_of "$file")"
        file="$(file_for_type "$type" "$(dirname "$file")" || true)"
        depth=$(( depth + 1 ))
    done

    # A required property is only a problem if nothing in the chain initialises it. A base
    # type may perfectly well require something the concrete file always sets -
    # PluginBackgroundWidget requires `pluginId`, and every plugin widget assigns it.
    local prop
    while read -r prop; do
        [[ -n "$prop" ]] || continue
        if ! grep -qhE "^[[:space:]]{4}$prop:" $chain 2>/dev/null; then
            unsatisfied+="      $prop"$'\n'
        fi
    done < <(printf '%s' "$required" | sort -u)

    if [[ -n "$unsatisfied" ]]; then
        (( required_offenders == 0 )) && echo "==> Uninitialised required properties in URL-loaded components:"
        required_offenders=$(( required_offenders + 1 ))
        echo "    ${entry#"$ROOT/"}"
        printf '%s' "$unsatisfied"
    fi
}

if [[ "$*" == "." ]] && command -v jq >/dev/null 2>&1; then
    while read -r target; do
        [[ -n "$target" && -e "$target" ]] || continue
        check_no_required "$target"
    done < <(
        for manifest in "$ROOT"/plugins/*/manifest.json; do
            [[ -e "$manifest" ]] || continue
            dir="$(dirname "$manifest")"
            jq -r '(.provides // {}) | to_entries[] | .value[]? | .entry // empty' "$manifest" \
                | while read -r e; do [[ -z "$e" ]] || echo "$dir/$e"; done
        done
        sed -n 's/.*path: "\([^"]*\)".*/\1/p' "$ROOT/core/DesktopWidgetRegistry.qml" \
            | sed "s#^#$ROOT/modules/ii/background/widgets/#"
        sed -n 's/.*android: "\([^"]*\)".*/\1/p' "$ROOT/core/QuickToggleRegistry.qml" \
            | sed "s#^#$ROOT/modules/ii/sidebarRight/quickToggles/androidStyle/#"
        sed -n 's/.*classic: "\([^"]*\)".*/\1/p' "$ROOT/core/QuickToggleRegistry.qml" \
            | sed "s#^#$ROOT/modules/ii/sidebarRight/quickToggles/classicStyle/#"
        sed -n 's/^[[:space:]]*{ id: "\([a-zA-Z]*\)".*/\1/p' "$ROOT/core/BarWidgetRegistry.qml" \
            | while read -r id; do
                printf '%s/modules/ii/bar/%s%s.qml\n' "$ROOT" "$(tr '[:lower:]' '[:upper:]' <<<"${id:0:1}")" "${id:1}"
            done
    )

    if (( required_offenders )); then
        status=1
    else
        echo "==> Required properties in URL-loaded components: all initialised"
    fi
fi

exit "$status"
