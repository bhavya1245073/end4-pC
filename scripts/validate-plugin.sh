#!/usr/bin/env bash
# Validate one plugin: manifest, references, QML, icons.
#
#     scripts/validate-plugin.sh battery
#     scripts/validate-plugin.sh ~/nixos-pc/modules/home/quickshell/plugins/quote-of-the-day
#     scripts/validate-plugin.sh battery --json
#
# Takes a plugin id (looked up in this tree, then in the NixOS config's plugin folder)
# or a path to a plugin folder. Plugins developed in the NixOS config are checked
# against this tree's core, which is what they will run against.
#
# Fast on purpose. check-qml.sh compiles 580 files and starts a shell, which is right
# before a commit and much too slow to run after every edit; this checks one plugin and
# tells you where the problem is. Everything it can determine without starting Quickshell
# is done first, so a manifest typo is reported in milliseconds.
#
# Exit status is the number of errors, capped at 125, so `&&` chains work.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMA="$ROOT/core/manifest.schema.json"

JSON=0
TARGET=""
NO_QML=0
for arg in "$@"; do
    case "$arg" in
        --json) JSON=1 ;;
        --no-qml) NO_QML=1 ;;
        -*) echo "unknown flag: $arg" >&2; exit 126 ;;
        *) TARGET="$arg" ;;
    esac
done

if [[ -z "$TARGET" ]]; then
    echo "usage: $(basename "$0") <plugin-id|path> [--json] [--no-qml]" >&2
    exit 126
fi

# ── locate ───────────────────────────────────────────────────────────────────

DIR=""
if [[ -d "$TARGET" && -f "$TARGET/manifest.json" ]]; then
    DIR="$(cd "$TARGET" && pwd)"
else
    for candidate in \
        "$ROOT/plugins/$TARGET" \
        "$HOME/nixos-pc/modules/home/quickshell/plugins/$TARGET"
    do
        if [[ -f "$candidate/manifest.json" ]]; then
            DIR="$(cd "$candidate" && pwd)"
            break
        fi
    done
fi

if [[ -z "$DIR" ]]; then
    echo "no plugin \"$TARGET\": looked in plugins/ and ~/nixos-pc/modules/home/quickshell/plugins/" >&2
    exit 126
fi

MANIFEST="$DIR/manifest.json"
ID="$(basename "$DIR")"

# ── diagnostics ──────────────────────────────────────────────────────────────

errors=0
warnings=0
diagnostics=()

# report <error|warning> <file> <message> [line]
report() {
    local level="$1" file="$2" message="$3" line="${4:-0}"
    [[ "$level" == "error" ]] && errors=$((errors + 1)) || warnings=$((warnings + 1))
    diagnostics+=("$(jq -cn --arg l "$level" --arg f "$file" --arg m "$message" --argjson n "$line" \
        '{level: $l, file: $f, line: $n, message: $m}')")
}

# ── 1. manifest is JSON at all ───────────────────────────────────────────────

if ! jq -e . "$MANIFEST" >/dev/null 2>&1; then
    # jq's own message names the line and column, which is the useful part.
    msg="$(jq . "$MANIFEST" 2>&1 | head -2 | tr '\n' ' ')"
    report error "manifest.json" "not valid JSON: $msg"
    # Nothing below can run without a parsed manifest.
    if [[ $JSON -eq 1 ]]; then
        printf '{"plugin":"%s","errors":1,"warnings":0,"diagnostics":[%s]}\n' "$ID" "$(IFS=,; echo "${diagnostics[*]}")"
    else
        echo "FAIL $ID: manifest.json is not valid JSON"
        echo "  $msg"
    fi
    exit 1
fi

m() { jq -r "$1" "$MANIFEST" 2>/dev/null; }

# ── 2. schema ────────────────────────────────────────────────────────────────
# Full JSON Schema validation when check-jsonschema is on PATH; the checks below cover
# the mistakes that actually happen either way, so a missing validator is a note rather
# than a hole.

if command -v check-jsonschema >/dev/null 2>&1; then
    schema_out="$(check-jsonschema --schemafile "$SCHEMA" "$MANIFEST" 2>&1)"
    if [[ $? -ne 0 ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            [[ "$line" =~ ^(Schema|Errors|error) ]] && continue
            report error "manifest.json" "schema: $(echo "$line" | sed 's/^ *//')"
        done <<< "$(echo "$schema_out" | grep -vE '^(ok|Schema validation errors were encountered)')"
    fi
else
    report warning "manifest.json" "check-jsonschema not on PATH - structural checks only. It is in nixpkgs."
fi

# The `$schema` key is what gives an editor completion and inline validation. A path that
# does not resolve means the editor silently offers nothing, which looks like the schema
# not existing.
declared_schema="$(m '.["$schema"] // ""')"
if [[ -z "$declared_schema" ]]; then
    report warning "manifest.json" "no \$schema key - adding one gives editor completion for every field. Relative to this folder that is: $(realpath --relative-to="$DIR" "$SCHEMA" 2>/dev/null || echo "$SCHEMA")"
elif [[ "$declared_schema" != http* && ! -f "$DIR/$declared_schema" ]]; then
    report error "manifest.json" "\$schema \"$declared_schema\" does not resolve from this folder - an editor validates nothing. Try: $(realpath --relative-to="$DIR" "$SCHEMA" 2>/dev/null || echo "$SCHEMA")"
fi

# ── 3. identity ──────────────────────────────────────────────────────────────

[[ "$(m .id)" == "$ID" ]] || report error "manifest.json" "id \"$(m .id)\" does not match the folder name \"$ID\" - the shell looks the plugin up by folder"

api="$(m .apiVersion)"
want="$(jq -r '.properties.apiVersion.maximum' "$SCHEMA")"
[[ "$api" == "$want" ]] || report error "manifest.json" "apiVersion $api, but this shell implements $want"

[[ "$(m '.name // ""')" != "" ]] || report error "manifest.json" "name is required"
[[ "$(m '.description // ""')" != "" ]] || report warning "manifest.json" "no description - the plugin list shows an empty line"

# ── 4. every referenced file exists ──────────────────────────────────────────
# The single most common reason a plugin appears to do nothing: the manifest points at a
# file that is not there, and a Loader failing is one line in the log.

while IFS=$'\t' read -r kind field file; do
    [[ -z "$file" || "$file" == "null" ]] && continue
    if [[ ! -f "$DIR/$file" ]]; then
        report error "manifest.json" "provides.$kind $field \"$file\" does not exist"
    fi
done < <(jq -r '
    (.provides // {}) | to_entries[] |
    .key as $kind | .value[]? |
    [ [$kind, "entry", (.entry // "null")],
      [$kind, "classicEntry", (.classicEntry // "null")],
      [$kind, "menu", (.menu // "null")],
      [$kind, "script", (.script // "null")] ][] |
    @tsv' "$MANIFEST")

# ── 5. per-kind rules the schema cannot express ──────────────────────────────

# A desktop widget's manifest id must equal the widgetId its QML sets, or position and
# size are written under one key and read from another - the widget silently resets to
# the corner on every restart.
while IFS=$'\t' read -r wid entry; do
    [[ -z "$entry" || ! -f "$DIR/$entry" ]] && continue
    declared="$(grep -oE 'widgetId:[[:space:]]*"[^"]+"' "$DIR/$entry" | head -1 | sed 's/.*"\(.*\)"/\1/')"
    if [[ -n "$declared" && "$declared" != "$wid" ]]; then
        report error "$entry" "widgetId \"$declared\" does not match the manifest id \"$wid\" - position and size would be stored under a different key than they are read from"
    fi
    if [[ -z "$declared" ]]; then
        report warning "$entry" "no widgetId - a desktop widget needs one to remember where it was put"
    fi
done < <(jq -r '(.provides.desktopWidgets // [])[] | [.id, (.entry // "")] | @tsv' "$MANIFEST")

# An ipc entry's root must be a PluginIpc, or its functions are not reachable and the
# host's pluginId injection fails.
while IFS= read -r entry; do
    [[ -z "$entry" || ! -f "$DIR/$entry" ]] && continue
    grep -qE '^[[:space:]]*PluginIpc[[:space:]]*\{' "$DIR/$entry" \
        || report error "$entry" "provides.ipc needs a PluginIpc root type"
    # Quickshell will not expose an unannotated function over IPC at all.
    while IFS= read -r fn; do
        report error "$entry" "function $fn has no return type annotation, so it is not exposed over IPC - say \": void\" if it returns nothing"
    done < <(grep -oE '^[[:space:]]*function[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*\([^)]*\)[[:space:]]*\{' "$DIR/$entry" \
        | grep -oE 'function[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*' | awk '{print $2}')
done < <(jq -r '(.provides.ipc // [])[] | .entry // ""' "$MANIFEST")

# A search provider's root must be a PluginSearchProvider, or PluginSearch cannot ask it
# anything.
while IFS= read -r entry; do
    [[ -z "$entry" || ! -f "$DIR/$entry" ]] && continue
    grep -qE '^[[:space:]]*PluginSearchProvider[[:space:]]*\{' "$DIR/$entry" \
        || report error "$entry" "provides.searchProviders needs a PluginSearchProvider root type"
    grep -qE 'function[[:space:]]+search[[:space:]]*\(' "$DIR/$entry" \
        || report error "$entry" "no search() function - the provider would never return anything"
done < <(jq -r '(.provides.searchProviders // [])[] | .entry // ""' "$MANIFEST")

# A shortcut that does nothing is a keybind the user will bind and wonder about.
while IFS=$'\t' read -r sid has_ipc has_exec; do
    [[ -z "$sid" ]] && continue
    [[ "$has_ipc" == "false" && "$has_exec" == "false" ]] \
        && report error "manifest.json" "shortcut \"$sid\" has neither ipc nor exec, so pressing it does nothing"
done < <(jq -r '(.provides.shortcuts // [])[] | [.id, (.ipc != null), (.exec != null)] | @tsv' "$MANIFEST")

# A context menu item likewise. Five verbs now: panel opens a panel, ipc calls a command, exec runs
# argv, url opens a link, entry names a submenu. A row with none of them draws and does nothing.
while IFS=$'\t' read -r cid has_ipc has_exec has_entry has_panel has_url; do
    [[ -z "$cid" ]] && continue
    [[ "$has_ipc" == "false" && "$has_exec" == "false" && "$has_entry" == "false" \
       && "$has_panel" == "false" && "$has_url" == "false" ]] \
        && report error "manifest.json" "context menu item \"$cid\" has no panel, ipc, exec, url or entry, so clicking it does nothing"
done < <(jq -r '(.provides.contextMenuItems // [])[] | [.id, (.ipc != null), (.exec != null), (.entry != null), (.panel != null), (.url != null)] | @tsv' "$MANIFEST")

# An ipc reference that names a target no manifest declares. Checked across this
# plugin only: a cross-plugin reference is legal, just unverifiable from here.
own_targets="$(jq -r '[(.provides.ipc // [])[] | .target // empty] + [.id] | join("\n")' "$MANIFEST")"
while IFS=$'\t' read -r where target fn; do
    [[ -z "$target" ]] && continue
    if grep -qx "$target" <<< "$own_targets"; then
        # The function has to exist in one of this plugin's PluginIpc files.
        if ! grep -rqE "function[[:space:]]+$fn[[:space:]]*\(" "$DIR" 2>/dev/null; then
            report error "manifest.json" "$where calls $target.$fn, and no function of that name exists in this plugin"
        fi
    fi
done < <(jq -r '
    [ ((.provides.shortcuts // [])[] | select(.ipc) | ["shortcut \"" + .id + "\"", .ipc.target, .ipc.function]),
      ((.provides.contextMenuItems // [])[] | select(.ipc) | ["context menu item \"" + .id + "\"", .ipc.target, .ipc.function]) ][]
    | @tsv' "$MANIFEST")

# ── 6. settings keys ─────────────────────────────────────────────────────────
# A settings key becomes a QML property. Some names cannot be, and PluginConfig skips
# them - so the setting is in the GUI but reading it returns nothing.

reserved="data children resources parent objectName state visible enabled width height x y z opacity anchors"
while IFS=$'\t' read -r key type; do
    [[ -z "$key" ]] && continue
    grep -qw "$key" <<< "$reserved" \
        && report error "manifest.json" "setting \"$key\" is a QML reserved name and cannot become a property - rename it"
    [[ "$key" =~ ^[a-z][a-zA-Z0-9]*$ ]] \
        || report error "manifest.json" "setting \"$key\" is not a valid QML identifier (lowercase first letter, letters and digits)"
    if [[ "$type" == "enum" ]]; then
        opts="$(jq -r --arg k "$key" '(.settings // [])[] | select(.key == $k) | (.options // []) | length' "$MANIFEST")"
        [[ "$opts" -gt 0 ]] || report error "manifest.json" "setting \"$key\" is an enum with no options"
    fi
done < <(jq -r '(.settings // [])[] | [.key, .type] | @tsv' "$MANIFEST")

# A default is optional in the schema but nearly always a bug to omit.
while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    report warning "manifest.json" "setting \"$key\" has no default, so it reads as an empty value until the user touches it"
done < <(jq -r '(.settings // [])[] | select(has("default") | not) | .key' "$MANIFEST")

# Settings the QML never reads, and reads of keys that are not declared. The second is
# the real bug: `settings.foo` where no `foo` exists is silently undefined.
declared_keys="$(jq -r '(.settings // [])[] | .key' "$MANIFEST")"
used_keys="$(grep -rhoE 'settings\.[a-zA-Z_][a-zA-Z0-9_]*' "$DIR" --include='*.qml' 2>/dev/null | sed 's/settings\.//' | sort -u)"
while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    grep -qx "$key" <<< "$declared_keys" \
        || report error "qml" "settings.$key is read but not declared in the manifest, so it is always undefined"
done <<< "$used_keys"

# ── 7. icons ─────────────────────────────────────────────────────────────────
# An unknown Material Symbol name is not an error and draws no placeholder: the font
# renders the string, so `icon: "power_plug"` writes PLUG across the widget.

FONT="$(fc-match -f '%{file}' 'Material Symbols Rounded' 2>/dev/null || true)"
if [[ -n "$FONT" && -f "$FONT" ]] && command -v magick >/dev/null 2>&1; then
    while IFS= read -r icon; do
        [[ -z "$icon" ]] && continue
        # A real ligature collapses to one glyph; a missing name stays as wide text.
        w="$(magick -font "$FONT" -pointsize 48 label:"$icon" -format "%w" info: 2>/dev/null || echo 0)"
        [[ "$w" -gt 90 ]] && report error "manifest.json" "icon \"$icon\" is not in Material Symbols - it would render as the literal text"
    done < <(jq -r '[.icon // empty] + [(.provides // {}) | to_entries[] | .value[]? | .icon // empty] + [(.settings // [])[] | .icon // empty] | unique | .[]' "$MANIFEST")
else
    report warning "manifest.json" "cannot check icon names: need the Material Symbols font and imagemagick"
fi

# ── 8. QML compiles ──────────────────────────────────────────────────────────
# Last, because it is the only slow part: it starts Quickshell. Every file in the
# plugin, with the imports the shell really has - which is what catches a `qs.*` module
# that needs an anchor in core/PluginModuleAnchors.qml.

qml_files=()
while IFS= read -r f; do qml_files+=("$f"); done < <(find "$DIR" -name '*.qml' | sort)

if [[ $NO_QML -eq 0 && ${#qml_files[@]} -gt 0 ]]; then
    if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
        report warning "qml" "no Wayland display, so QML was not compiled - Quickshell will not start headless"
    else
        harness="$ROOT/.validate-plugin.qml"
        {
            printf 'import QtQuick\nimport Quickshell\n'
            # Every module a core file imports, so a plugin's imports resolve exactly as
            # they do in the running shell.
            grep -rhoE '^import qs[a-zA-Z0-9_.]*' "$ROOT/core" "$ROOT/shell.qml" 2>/dev/null | sort -u
            cat <<'QMLEOF'

ShellRoot {
    Component.onCompleted: {
        const targets = (Quickshell.env("VALIDATE_TARGETS") ?? "").split(",").filter(t => t.length > 0);
        let failed = 0;
        for (const t of targets) {
            const c = Qt.createComponent(t, Component.PreferSynchronous);
            if (c.status === Component.Error) {
                failed++;
                console.log("VALIDATE FAIL " + t);
                console.log(c.errorString());
            }
        }
        console.log("VALIDATE DONE checked=" + targets.length + " failures=" + failed);
    }
}
QMLEOF
        } > "$harness"

        log="$(mktemp -t validate-plugin.XXXXXX)"
        targets="$(printf '%s\n' "${qml_files[@]}" | sed 's|^|file://|' | paste -sd, -)"
        VALIDATE_TARGETS="$targets" qs -p "$harness" >"$log" 2>&1 &
        qs_pid=$!
        for _ in $(seq 1 200); do
            grep -q "VALIDATE DONE" "$log" 2>/dev/null && break
            sleep 0.05
        done
        kill "$qs_pid" 2>/dev/null
        wait "$qs_pid" 2>/dev/null

        # Quickshell reports errors as "file:line:col: message".
        while IFS= read -r line; do
            file="$(echo "$line" | sed -E 's|^.*/([^/]+\.qml):([0-9]+):[0-9]+:.*|\1|')"
            lineno="$(echo "$line" | sed -E 's|^.*\.qml:([0-9]+):[0-9]+:.*|\1|')"
            message="$(echo "$line" | sed -E 's|^.*\.qml:[0-9]+:[0-9]+: ||')"
            [[ "$lineno" =~ ^[0-9]+$ ]] || lineno=0
            report error "$file" "$message" "$lineno"
        done < <(grep -E '\.qml:[0-9]+:[0-9]+:' "$log" | grep -v "$(basename "$harness")" | sort -u)

        rm -f "$harness" "$log"
    fi
fi

# ── output ───────────────────────────────────────────────────────────────────

if [[ $JSON -eq 1 ]]; then
    jq -n \
        --arg plugin "$ID" \
        --arg dir "$DIR" \
        --argjson errors "$errors" \
        --argjson warnings "$warnings" \
        --argjson diagnostics "[$(IFS=,; echo "${diagnostics[*]:-}")]" \
        '{plugin: $plugin, dir: $dir, ok: ($errors == 0), errors: $errors, warnings: $warnings, diagnostics: $diagnostics}'
else
    for d in "${diagnostics[@]:-}"; do
        [[ -z "$d" ]] && continue
        level="$(jq -r .level <<< "$d")"
        file="$(jq -r .file <<< "$d")"
        line="$(jq -r .line <<< "$d")"
        message="$(jq -r .message <<< "$d")"
        marker="$([[ "$level" == "error" ]] && echo "ERROR " || echo "warn  ")"
        [[ "$line" != "0" ]] && where="$file:$line" || where="$file"
        printf '%s %s\n         %s\n' "$marker" "$where" "$message"
    done

    if [[ $errors -eq 0 ]]; then
        printf 'OK   %s: %s QML file(s), %s warning(s)\n' "$ID" "${#qml_files[@]}" "$warnings"
    else
        printf 'FAIL %s: %s error(s), %s warning(s)\n' "$ID" "$errors" "$warnings"
    fi
fi

[[ $errors -gt 125 ]] && exit 125
exit $errors
