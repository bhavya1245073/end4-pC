#!/usr/bin/env bash
# One command that tells you whether the shell and every plugin in it are healthy.
#
#     scripts/doctor.sh                  everything
#     scripts/doctor.sh --quick          skip the checks that start a shell (~2s instead of ~90s)
#     scripts/doctor.sh --plugin gifs    one plugin, in depth
#     scripts/doctor.sh --json           machine-readable, for CI
#
# The existing scripts each answer one question well: check-qml.sh compiles, check-icons.sh
# verifies glyph names, validate-plugin.sh checks one manifest. What was missing is the
# question a person actually has - "is anything wrong?" - which meant remembering four
# commands, their flags, and which of them needs a running shell.
#
# It also checks things none of the others could, because they need a *live* shell to see:
# intents declared with no handler, permissions used but not declared, plugins whose
# surfaces failed to load, orphaned panels. Those are exactly the failures that pass every
# static check and then do nothing on the desktop.
#
# Exit status is the number of problems found, capped at 125.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 126

QUICK=0
JSON=0
ONE_PLUGIN=""
CONFIG_NAME="${QS_CONFIG_NAME:-end4-pC}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --quick) QUICK=1 ;;
        --json) JSON=1 ;;
        --plugin) ONE_PLUGIN="${2:-}"; shift ;;
        --config) CONFIG_NAME="${2:-}"; shift ;;
        -h|--help)
            sed -n '2,20p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *) echo "unknown flag: $1" >&2; exit 126 ;;
    esac
    shift
done

# ─────────────────────────────────────────────────────────────────── reporting ──

errors=0
warnings=0
declare -a findings=()

if [[ -t 1 && $JSON -eq 0 ]]; then
    bold=$'\e[1m'; red=$'\e[31m'; yellow=$'\e[33m'; green=$'\e[32m'; dim=$'\e[2m'; reset=$'\e[0m'
else
    bold=""; red=""; yellow=""; green=""; dim=""; reset=""
fi

section() {
    [[ $JSON -eq 1 ]] && return
    printf '\n%s==> %s%s\n' "$bold" "$1" "$reset"
}

ok() {
    [[ $JSON -eq 1 ]] && return
    printf '    %s✓%s %s\n' "$green" "$reset" "$1"
}

problem() {
    errors=$((errors + 1))
    findings+=("$(printf '{"level":"error","area":"%s","message":%s}' "$1" "$(jq -Rs . <<<"$2")")")
    [[ $JSON -eq 1 ]] && return
    printf '    %s✗ %s%s %s\n' "$red" "$1" "$reset" "$2"
}

warn() {
    warnings=$((warnings + 1))
    findings+=("$(printf '{"level":"warning","area":"%s","message":%s}' "$1" "$(jq -Rs . <<<"$2")")")
    [[ $JSON -eq 1 ]] && return
    printf '    %s! %s%s %s\n' "$yellow" "$1" "$reset" "$2"
}

note() {
    [[ $JSON -eq 1 ]] && return
    printf '      %s%s%s\n' "$dim" "$1" "$reset"
}

# ──────────────────────────────────────────────────────────────── prerequisites ──

section "Tools"
for tool in qs jq; do
    if command -v "$tool" >/dev/null 2>&1; then
        ok "$tool"
    else
        problem "tools" "$tool is not on PATH - most checks cannot run without it"
    fi
done

if command -v check-jsonschema >/dev/null 2>&1; then
    ok "check-jsonschema"
else
    warn "tools" "check-jsonschema is not on PATH - manifests will be checked structurally only"
    note "nix shell nixpkgs#check-jsonschema"
fi

# ─────────────────────────────────────────────────────────────────── manifests ──
#
# Every plugin folder that exists, from every search path the shell itself would use, so a
# plugin developed in the NixOS config is checked the same way as one in this tree.

section "Plugins on disk"

declare -a pluginDirs=()
for base in "$ROOT/plugins" "$HOME/nixos-pc/modules/home/quickshell/plugins" ${END4_PLUGIN_PATH:+${END4_PLUGIN_PATH//:/ }}; do
    [[ -d "$base" ]] || continue
    while IFS= read -r manifest; do
        pluginDirs+=("$(dirname "$manifest")")
    done < <(find "$base" -maxdepth 2 -name manifest.json 2>/dev/null | sort)
done

if [[ ${#pluginDirs[@]} -eq 0 ]]; then
    problem "plugins" "no plugin manifests found at all - is this the right tree?"
else
    ok "${#pluginDirs[@]} plugin manifest(s) found"
fi

for dir in "${pluginDirs[@]}"; do
    id="$(basename "$dir")"
    [[ -n "$ONE_PLUGIN" && "$id" != "$ONE_PLUGIN" ]] && continue

    if ! jq -e . "$dir/manifest.json" >/dev/null 2>&1; then
        problem "$id" "manifest.json is not valid JSON"
        continue
    fi

    # The id in the manifest and the folder name have to agree: the folder is what the
    # registry keys plugins.json on, and the manifest id is what every provides entry is
    # tagged with. When they differ the plugin loads and its settings vanish on restart.
    declaredId="$(jq -r '.id // ""' "$dir/manifest.json")"
    if [[ -n "$declaredId" && "$declaredId" != "$id" ]]; then
        problem "$id" "manifest id is \"$declaredId\" but the folder is \"$id\" - settings will not persist"
    fi

    # Every entry file a manifest points at must exist. A missing one is a silent no-show.
    while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        [[ -f "$dir/$entry" ]] || problem "$id" "manifest points at $entry, which does not exist"
    done < <(jq -r '[.provides // {} | .[]? | .[]? | .entry? // empty] | .[]' "$dir/manifest.json" 2>/dev/null)

    # Actions need handlers, and a handler is a PluginIntentHandler somewhere in the plugin.
    # Statically we can only check that one exists at all; the live check below verifies each.
    actionCount="$(jq -r '(.provides.actions // []) | length' "$dir/manifest.json")"
    if [[ "$actionCount" -gt 0 ]] && ! grep -rq "PluginIntentHandler" "$dir" 2>/dev/null; then
        problem "$id" "declares $actionCount action(s) but has no PluginIntentHandler anywhere - they cannot be called"
    fi

    # A declared permission that is never used is noise in the one place the user reads to
    # decide whether to trust the plugin.
    while IFS= read -r permission; do
        [[ -z "$permission" ]] && continue
        case "$permission" in
            network)
                grep -rqE "PluginHttp|\.get\(|\.post\(|fetchJson|fetchText" "$dir" 2>/dev/null \
                    || warn "$id" "declares \"network\" but nothing in it makes a request"
                ;;
            clipboard)
                grep -rqE "copy\(|copyTyped|copyFile|paste\(|clipboard" "$dir" 2>/dev/null \
                    || warn "$id" "declares \"clipboard\" but nothing in it touches the clipboard"
                ;;
            system-exec)
                grep -rqE "\.exec\(|\.run\(|\.pipe\(|execDetached|Process" "$dir" 2>/dev/null \
                    || warn "$id" "declares \"system-exec\" but nothing in it starts a process"
                ;;
            notifications)
                grep -rqE "notify\(|PluginNotifications|notify-send" "$dir" 2>/dev/null \
                    || warn "$id" "declares \"notifications\" but nothing in it posts one"
                ;;
        esac
    done < <(jq -r '(.permissions // []) | .[]' "$dir/manifest.json" 2>/dev/null)

    # The reverse: used but not declared. Reported rather than blocked, and this is where a
    # manifest gets brought up to date.
    declaredPerms="$(jq -r '(.permissions // []) | join(" ")' "$dir/manifest.json" 2>/dev/null)"
    if grep -rqE "PluginHttp\.(get|post|put|del)" "$dir" 2>/dev/null && [[ " $declaredPerms " != *" network "* ]]; then
        warn "$id" "makes HTTP requests without declaring \"network\""
    fi
    if grep -rqE "PluginUtils\.(exec|run|pipe)\(|execDetached" "$dir" 2>/dev/null && [[ " $declaredPerms " != *" system-exec "* ]]; then
        warn "$id" "starts processes without declaring \"system-exec\""
    fi

    # pragma Singleton has to be on line 1. Quickshell's scanner gives up at the first `{` it
    # sees - including one inside a comment - so a file with a licence header or a design note
    # above the pragma is silently not a singleton, and every importer fails with a type error
    # somewhere else entirely. A comment with no braces happens to survive, which is worse than
    # failing: it works until someone writes `{` in prose.
    while IFS= read -r file; do
        grep -q '^pragma Singleton' "$file" || continue
        [[ "$(head -1 "$file")" == "pragma Singleton" ]] && continue
        line="$(grep -n '^pragma Singleton' "$file" | head -1 | cut -d: -f1)"
        if head -$((line - 1)) "$file" | grep -q '{'; then
            problem "$id" "$(basename "$file"): pragma Singleton is on line $line with a { above it - this file is not a singleton"
        else
            problem "$id" "$(basename "$file"): pragma Singleton is on line $line, not line 1 - one { in the text above it silently breaks the file"
        fi
    done < <(find "$dir" -name '*.qml' 2>/dev/null)

    # A required property on the *root* of a file loaded by URL makes the Loader fail with no
    # message at all. Only the root: a `required property var modelData` inside a delegate is
    # normal and correct, which is why this looks at indentation - a root-level property is
    # indented one step, a delegate's is deeper.
    while IFS= read -r file; do
        grep -qE '^    required property' "$file" || continue
        base="$(basename "$file")"
        jq -e --arg f "$base" '[.provides // {} | .[]? | .[]? | .entry? // empty] | any(endswith($f))' "$dir/manifest.json" >/dev/null 2>&1 \
            && problem "$id" "$base is loaded by URL and its root declares a required property - it will silently fail to instantiate"
    done < <(find "$dir" -name '*.qml' 2>/dev/null)

    if [[ -x "$ROOT/scripts/validate-plugin.sh" ]]; then
        if out="$("$ROOT/scripts/validate-plugin.sh" "$dir" --no-qml 2>&1)"; then
            :
        else
            problem "$id" "validate-plugin.sh reported problems"
            [[ $JSON -eq 0 ]] && sed 's/^/        /' <<<"$out"
        fi
    fi
done

[[ $errors -eq 0 ]] && ok "manifests, entry files, singletons and loaders all consistent"

# ─────────────────────────────────────────────────────────────────── the shell ──
#
# The same invariants, applied to the shell's own code. A plugin author is not the only person
# who can break these, and core/ getting them wrong breaks every plugin at once.

section "Shell invariants"

pragmaProblems=0
while IFS= read -r file; do
    grep -q '^pragma Singleton' "$file" || continue
    [[ "$(head -1 "$file")" == "pragma Singleton" ]] && continue
    line="$(grep -n '^pragma Singleton' "$file" | head -1 | cut -d: -f1)"
    pragmaProblems=$((pragmaProblems + 1))
    if head -$((line - 1)) "$file" | grep -q '{'; then
        problem "shell" "${file#./}: pragma Singleton on line $line with a { above it - not a singleton"
    else
        warn "shell" "${file#./}: pragma Singleton on line $line, not line 1"
    fi
done < <(find core modules services -name '*.qml' 2>/dev/null | sort)
[[ $pragmaProblems -eq 0 ]] && ok "every singleton declares its pragma on line 1"

# Every qs.* module a plugin imports must be anchored, or it does not exist by the time the
# plugin is loaded from a URL.
anchorProblems=0
while IFS= read -r module; do
    grep -qF "import $module" "$ROOT/core/PluginModuleAnchors.qml" \
        || { problem "anchors" "$module is imported by a plugin but not anchored in core/PluginModuleAnchors.qml"; anchorProblems=$((anchorProblems + 1)); }
done < <(
    for dir in "${pluginDirs[@]}"; do
        grep -rhoE '^import qs(\.[A-Za-z]+)*' "$dir" 2>/dev/null | sed 's/^import //'
    done | sort -u
)
[[ $anchorProblems -eq 0 ]] && ok "every qs.* module plugins import is anchored"

# ─────────────────────────────────────────────────────────────────────── icons ──

section "Material Symbol names"
if out="$(bash "$ROOT/scripts/check-icons.sh" 2>&1 | tail -3)"; then
    ok "$(tail -1 <<<"$out")"
else
    problem "icons" "unknown glyph names - they render as words, not icons"
    [[ $JSON -eq 0 ]] && sed 's/^/        /' <<<"$out"
fi

# ─────────────────────────────────────────────────────────────── api catalogue ──

section "API catalogue"
if [[ -f "$ROOT/core/api.json" ]]; then
    before="$(sha256sum "$ROOT/core/api.json" | cut -d' ' -f1)"
    bash "$ROOT/scripts/gen-api.sh" >/dev/null 2>&1
    after="$(sha256sum "$ROOT/core/api.json" | cut -d' ' -f1)"
    if [[ "$before" == "$after" ]]; then
        ok "core/api.json is up to date"
    else
        problem "api" "core/api.json was stale - it has been regenerated, commit it"
    fi
else
    problem "api" "core/api.json is missing - run scripts/gen-api.sh"
fi

# ────────────────────────────────────────────────────────────────── compilation ──

if [[ $QUICK -eq 1 ]]; then
    section "Skipped (--quick)"
    note "QML compilation and the live-shell checks need a shell; run without --quick before committing"
else
    section "QML compilation"
    # Its own generous budget: phase 10 starts a real shell and opens every panel, so the full
    # suite takes around two minutes. Reported as a timeout rather than a failure, because
    # "compilation failed" for a check that was killed mid-run sends you looking for a bug that
    # is not there.
    out="$(timeout 900 bash "$ROOT/scripts/check-qml.sh" . 2>&1)"
    status=$?
    if [[ $status -eq 0 ]]; then
        ok "$(grep -m1 'QMLCHECK DONE' <<<"$out")"
        ok "$(grep -c 'QMLCHECK DONE' <<<"$out") compile phase(s) and the runtime phases passed"
    elif [[ $status -eq 124 || $status -eq 143 ]]; then
        warn "qml" "check-qml.sh did not finish within 900s - run it on its own"
    else
        problem "qml" "compilation failed"
        [[ $JSON -eq 0 ]] && grep -E 'FAIL|MISSING' <<<"$out" | head -30 | sed 's/^/        /'
    fi

    # ───────────────────────────────────────────────────────────── live checks ──
    #
    # Everything below needs a running shell, because it is about what actually resolved.
    # A stopped shell is not a failure - it just means these are unknown.

    section "Running shell"
    if ! qs -c "$CONFIG_NAME" ipc call plugins list >/dev/null 2>&1; then
        warn "live" "no shell is running as \"$CONFIG_NAME\" - intent handlers, permissions in use and load failures cannot be checked"
        note "start one, or pass --config <name>"
    else
        ok "shell \"$CONFIG_NAME\" is answering"

        # Declared actions with nothing listening. Passes every static check and does nothing
        # when invoked, which is the worst kind of failure to debug from the outside.
        orphans="$(qs -c "$CONFIG_NAME" ipc call intent orphans 2>/dev/null)"
        if [[ "$orphans" == every* ]]; then
            ok "every declared action has a handler"
        else
            problem "intents" "actions declared with no handler"
            [[ $JSON -eq 0 ]] && sed 's/^/        /' <<<"$orphans"
        fi

        # Permissions exercised but not declared, as observed rather than grepped.
        caps="$(qs -c "$CONFIG_NAME" ipc call caps list 2>/dev/null)"
        if grep -q "undeclared:" <<<"$caps"; then
            while IFS= read -r line; do
                warn "permissions" "$line"
            done < <(grep "undeclared:" <<<"$caps")
        else
            ok "no plugin is using a permission it did not declare"
        fi

        # Panels registered by plugins that are switched off leave ids nothing can open.
        panels="$(qs -c "$CONFIG_NAME" ipc call panels list 2>/dev/null | wc -l)"
        ok "$panels panel(s) addressable"

        lifecycle="$(qs -c "$CONFIG_NAME" ipc call caps lifecycle 2>/dev/null)"
        if [[ -n "$lifecycle" ]]; then
            awake="$(jq -r '.awake' <<<"$lifecycle" 2>/dev/null)"
            saver="$(jq -r '.powerSaver' <<<"$lifecycle" 2>/dev/null)"
            ok "lifecycle: awake=$awake powerSaver=$saver"
        fi

        http="$(qs -c "$CONFIG_NAME" ipc call http stats 2>/dev/null | head -1)"
        [[ -n "$http" ]] && ok "http: $http"
    fi
fi

# ───────────────────────────────────────────────────────────────────── summary ──

if [[ $JSON -eq 1 ]]; then
    printf '{"errors":%d,"warnings":%d,"findings":[%s]}\n' \
        "$errors" "$warnings" "$(IFS=,; echo "${findings[*]:-}")"
else
    printf '\n'
    if [[ $errors -eq 0 && $warnings -eq 0 ]]; then
        printf '%s%s all clear%s\n' "$green" "$bold" "$reset"
    elif [[ $errors -eq 0 ]]; then
        printf '%s%d warning(s), no errors%s\n' "$yellow" "$warnings" "$reset"
    else
        printf '%s%d error(s)%s, %d warning(s)\n' "$red" "$errors" "$reset" "$warnings"
    fi
fi

[[ $errors -gt 125 ]] && exit 125
exit "$errors"
