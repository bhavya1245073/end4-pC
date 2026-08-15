#!/usr/bin/env bash
# check-qml.sh — Compile every QML file in the shell tree and report the ones
# that fail to resolve their imports or types.
#
# Nothing is instantiated, so no windows appear and the running shell is not
# touched. Needs a Wayland session (Quickshell won't start without one).
#
#   scripts/check-qml.sh                  # whole tree
#   scripts/check-qml.sh plugins          # one or more subtrees
#
# Exit status is 0 only when every file compiled, so this is usable in a hook.
#
# ## Two things make this work, and both used to be wrong
#
# 1. **The harness has to import what the tree imports.** A synthetic `qs.*`
#    module only exists once something has imported it, and an import inside a
#    dynamically created component is too late. The real shell registers the deep
#    ones (`qs.modules.ii.bar`, `qs.modules.common.widgets.widgetCanvas`, ...) on
#    the way down from shell.qml, so this harness is generated with a static
#    `import` for every `qs.*` module the tree mentions. Without them a pristine
#    tree reported 76 "module is not installed" failures that the running shell
#    does not have.
#
# 2. **`file://` URLs, deliberately.** That is what `core/PluginRegistry.qml`
#    resolves plugin entries to, so compiling the same way tests the path a
#    plugin is really loaded through. (Quickshell also exposes the tree as a
#    virtual `qs:` filesystem; compiling from there works too, but it registers
#    each directory as a module, and plugin folders cannot be modules because
#    their names contain hyphens.)
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

exit "$status"
