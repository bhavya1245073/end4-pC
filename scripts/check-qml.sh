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
# Caveat: run this way Quickshell does not register every deep `qs.modules.*`
# submodule, so a handful of files report `module ... is not installed` even on
# a pristine tree. Treat the output as a baseline to diff against, not as an
# absolute pass/fail.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS="$ROOT/.qml-check-harness.qml"

cd "$ROOT"

[[ $# -gt 0 ]] || set -- .
mapfile -t files < <(find "$@" -name '*.qml' -not -name '.qml-check-harness.qml' | sort)
[[ ${#files[@]} -gt 0 ]] || { echo "no .qml files under $*"; exit 1; }

targets=""
for f in "${files[@]}"; do
    targets+="file://$ROOT/${f#./},"
done

cat > "$HARNESS" <<'QML'
import QtQuick
import Quickshell

ShellRoot {
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
trap 'rm -f "$HARNESS"' EXIT

echo "==> Compiling ${#files[@]} QML files under $*..."
QMLCHECK_TARGETS="$targets" timeout 900 qs -p "$HARNESS" 2>&1 \
    | sed -u 's/\x1b\[[0-9;]*m//g' \
    | sed -nu 's/^ *DEBUG qml: //p' \
    | awk -v root="$ROOT/" '
        /^QMLCHECK FAIL /   { path=$3; sub("file://" root, "", path); print "FAIL " path; next }
        /^QMLCHECK DONE /   { print; exit }
        { if (length($0)) print "      " $0 }
    '
