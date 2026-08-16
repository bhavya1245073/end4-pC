#!/usr/bin/env bash
# Generate core/api.json: every Theme token, base type, core singleton and shell
# service a plugin can use, with types and one-line docs.
#
#     scripts/gen-api.sh            # write core/api.json
#     scripts/gen-api.sh --check    # fail if it is out of date (used by check-qml.sh)
#
# Why this exists: the alternative to a catalogue is an agent reading 580 QML files to
# find out whether the accent colour is Theme.accent, Theme.primary or
# Appearance.colors.colPrimary - and then picking one that exists but is wrong for the
# surface it is drawing on. One file, a few thousand tokens, no guessing.
#
# Generated rather than written so it cannot drift from the code. The `provides` section
# is derived from core/manifest.schema.json for the same reason, so the manifest contract
# is defined once.
#
# Deliberately no timestamp in the output: a generator that dirties git on every run
# gets ignored, and then the catalogue is stale in exactly the way this is meant to
# prevent.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OUT="core/api.json"
CHECK=0
[[ "${1:-}" == "--check" ]] && CHECK=1

# Parses declarations out of one QML file.
#
# Handles what this codebase actually writes:
#   [readonly] property <type> <name>[: <value>]
#   function <name>(<args>)[: <type>]
#   signal <name>(...)
#   enum <Name> { A, B }
# and attaches the comment block immediately above a declaration as its doc.
#
# Skips anything inside a nested object (brace depth > 1 relative to the root type), so
# a delegate's internal properties are not reported as part of the public API.
parse_qml() {
    awk '
    function flush_doc() { doc = "" }
    function esc(s) {
        gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s)
        gsub(/\t/, " ", s)
        return s
    }
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }

    BEGIN { depth = 0; root_seen = 0; first = 1; printf "[" }

    # Doc comments: keep the last contiguous // block before a declaration.
    /^[ \t]*\/\// {
        line = $0
        sub(/^[ \t]*\/\/[ ]?/, "", line)
        # A divider line (---- or ════) is decoration, not documentation.
        if (line ~ /^[-=_─═]{3,}$/ || line ~ /^[ \t]*$/) { flush_doc(); next }
        doc = (doc == "" ? line : doc " " line)
        next
    }

    # The root type opens the first brace at depth 0.
    /\{/ && root_seen == 0 && $0 !~ /^[ \t]*\/\// {
        match($0, /^[ \t]*([A-Za-z_][A-Za-z0-9_.]*)[ \t]*\{/, m)
        if (m[1] != "") { root_type = m[1]; root_seen = 1 }
    }

    {
        # Only declarations at the root types level are public API.
        public = (depth <= 1)

        if (public && $0 ~ /^[ \t]*(readonly[ \t]+)?(required[ \t]+)?property[ \t]/) {
            ro = ($0 ~ /readonly/) ? "true" : "false"
            req = ($0 ~ /required/) ? "true" : "false"
            l = $0
            sub(/^[ \t]*/, "", l)
            sub(/^readonly[ \t]+/, "", l)
            sub(/^required[ \t]+/, "", l)
            sub(/^property[ \t]+/, "", l)
            # type name[: value]
            if (match(l, /^([A-Za-z_][A-Za-z0-9_<>.]*)[ \t]+([A-Za-z_][A-Za-z0-9_]*)/, m)) {
                type = m[1]; name = m[2]
                rest = substr(l, RSTART + RLENGTH)
                val = ""
                if (match(rest, /^[ \t]*:[ \t]*(.*)$/, v)) {
                    val = trim(v[1])
                    sub(/[ \t]*\{[ \t]*$/, "", val)   # an object literal opening
                }
                # Internal by convention: a `__` prefix keeps a member out of the public
                # catalogue. QML has no access control, so the convention has to be
                # readable rather than enforced - and being absent from api.json is what
                # makes it real, since that is what a plugin author is handed.
                if (name !~ /^__/) {
                    if (!first) printf ","
                    first = 0
                    printf "{\"kind\":\"property\",\"name\":\"%s\",\"type\":\"%s\",\"readonly\":%s,\"required\":%s,\"default\":\"%s\",\"doc\":\"%s\"}",
                        esc(name), esc(type), ro, req, esc(val), esc(doc)
                }
            }
            flush_doc()
        }
        else if (public && $0 ~ /^[ \t]*function[ \t]/) {
            if (match($0, /function[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]*\(([^)]*)\)[ \t]*(:[ \t]*([A-Za-z_][A-Za-z0-9_<>.]*))?/, m)) {
                if (m[1] !~ /^__/) {
                    if (!first) printf ","
                    first = 0
                    printf "{\"kind\":\"function\",\"name\":\"%s\",\"args\":\"%s\",\"returns\":\"%s\",\"doc\":\"%s\"}",
                        esc(m[1]), esc(trim(m[2])), esc(m[4] == "" ? "var" : m[4]), esc(doc)
                }
            }
            flush_doc()
        }
        else if (public && $0 ~ /^[ \t]*signal[ \t]/) {
            if (match($0, /signal[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]*(\(([^)]*)\))?/, m)) {
                if (!first) printf ","
                first = 0
                printf "{\"kind\":\"signal\",\"name\":\"%s\",\"args\":\"%s\",\"doc\":\"%s\"}",
                    esc(m[1]), esc(trim(m[3])), esc(doc)
            }
            flush_doc()
        }
        else if (public && $0 ~ /^[ \t]*enum[ \t]/) {
            if (match($0, /enum[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]*\{([^}]*)\}/, m)) {
                if (!first) printf ","
                first = 0
                printf "{\"kind\":\"enum\",\"name\":\"%s\",\"values\":\"%s\",\"doc\":\"%s\"}",
                    esc(m[1]), esc(trim(m[2])), esc(doc)
            }
            flush_doc()
        }
        else if ($0 !~ /^[ \t]*$/) {
            # Any other substantive line ends a doc block that was not attached to
            # anything, so a file header comment is not credited to the first property.
            flush_doc()
        }

        # Track nesting after classifying the line, so a declaration on the same line as
        # a brace is still seen at its own depth.
        n = gsub(/\{/, "{"); depth += n
        n = gsub(/\}/, "}"); depth -= n
    }

    END { printf "]" }
    ' "$1"
}

# The first paragraph of a files header comment: what the type is for.
file_summary() {
    awk '
    /^[ \t]*\/\// {
        line = $0
        sub(/^[ \t]*\/\/[ ]?/, "", line)
        if (line ~ /^[ \t]*$/) { if (out != "") exit; else next }
        out = (out == "" ? line : out " " line)
        next
    }
    /^[ \t]*$/ { if (out != "") next }
    { if (out != "") exit }
    END { print out }
    ' "$1"
}

root_type_of() {
    awk '/^[A-Za-z_][A-Za-z0-9_.]*[ \t]*\{/ { sub(/[ \t]*\{.*/, ""); print; exit }' "$1"
}

is_singleton() {
    grep -q "^pragma Singleton" "$1"
}

# ── build ────────────────────────────────────────────────────────────────────

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Theme, split into the groups it declares, so an agent can see "these are the colours"
# rather than one flat list of 40 names.
parse_qml core/Theme.qml > "$tmp/theme.json"

# Every core type: base types to inherit, singletons to call. These get full detail -
# docs included - because this is the API a plugin is written against, and the docs are
# where the non-obvious rules live. Defaults are kept only when short enough to be a
# fact rather than an implementation.
: > "$tmp/types.ndjson"
for file in core/*.qml; do
    name="$(basename "$file" .qml)"
    [[ "$name" == "Theme" ]] && continue
    kind="type"
    is_singleton "$file" && kind="singleton"
    jq -cn \
        --arg name "$name" \
        --arg kind "$kind" \
        --arg extends "$(root_type_of "$file")" \
        --arg summary "$(file_summary "$file" | cut -c1-400)" \
        --argjson members "$(parse_qml "$file" | jq -c 'map(
            if .doc then .doc |= .[0:180] else . end
            | if .default and ((.default | length) > 60 or (.default | test("__"))) then .default = "(computed)" else . end
            | with_entries(select(.value != "" and .value != false))
        )')" \
        '{name: $name, kind: $kind, extends: $extends, summary: $summary, members: $members}' \
        >> "$tmp/types.ndjson"
done

# Shell services. A compact shape: an agent needs to know that Battery.percentage
# exists and is a real, not to read the service's internal documentation - so these are
# name/type pairs with no docs or defaults. The catalogue has to stay small enough to
# read in one go, or it is no better than the source it summarises.
: > "$tmp/services.ndjson"
for file in services/*.qml; do
    name="$(basename "$file" .qml)"
    is_singleton "$file" || continue
    jq -cn \
        --arg name "$name" \
        --arg summary "$(file_summary "$file" | cut -c1-180)" \
        --argjson props "$(parse_qml "$file" | jq -c '[.[] | select(.kind == "property")] | map({(.name): .type}) | add // {}')" \
        --argjson funcs "$(parse_qml "$file" | jq -c '[.[] | select(.kind == "function") | .name + "(" + .args + ")"]')" \
        '{name: $name, summary: $summary, properties: $props, functions: $funcs}' \
        >> "$tmp/services.ndjson"
done

# Widgets a plugin draws with: names and the properties each declares. Inherited
# properties are not listed - the `extends` chain says where to look, and repeating
# QQuickItem's API 162 times would treble the file for nothing.
: > "$tmp/widgets.ndjson"
for file in modules/common/widgets/*.qml; do
    name="$(basename "$file" .qml)"
    jq -cn \
        --arg name "$name" \
        --arg extends "$(root_type_of "$file")" \
        --argjson props "$(parse_qml "$file" | jq -c '[.[] | select(.kind == "property")] | map({(.name): .type}) | add // {}')" \
        '{name: $name, extends: $extends, properties: $props}' \
        >> "$tmp/widgets.ndjson"
done

# The manifest contract, derived from the schema so it is defined in exactly one place.
jq '{
    kinds: (.properties.provides.properties | to_entries | map({
        kind: .key,
        description: (.value.items["$ref"] as $ref | .value.items.description // ""),
        ref: .value.items["$ref"]
    })),
    settingTypes: .definitions.setting.properties.type.enum,
    definitions: (.definitions | with_entries(.value |= {
        description: (.description // ""),
        required: (.required // []),
        fields: ((.properties // {}) | with_entries(.value |= {
            type: (.type // .["$ref"] // (.enum | if . then "enum" else "any" end)),
            description: (.description // ""),
            default: (.default // null),
            enum: (.enum // null)
        }))
    }))
}' core/manifest.schema.json > "$tmp/manifest.json"

api_version="$(jq -r '.properties.apiVersion.maximum' core/manifest.schema.json)"

jq -n \
    --argjson apiVersion "$api_version" \
    --argjson theme "$(jq -c "map(if .doc then .doc |= .[0:180] else . end | with_entries(select(.value != \"\" and .value != false)))" "$tmp/theme.json")" \
    --slurpfile types <(cat "$tmp/types.ndjson") \
    --slurpfile services <(cat "$tmp/services.ndjson") \
    --slurpfile widgets <(cat "$tmp/widgets.ndjson") \
    --argjson manifest "$(cat "$tmp/manifest.json")" \
'{
    "$comment": "Generated by scripts/gen-api.sh - do not edit. Every token, type and service a plugin may use. Regenerate after changing core/, services/ or modules/common/widgets/; scripts/check-qml.sh fails if this is stale.",
    apiVersion: $apiVersion,

    readMeFirst: [
        "Colours: use Theme.*, never Appearance.* - Theme is the stable API and names surfaces by role.",
        "A desktop widget draws on a wallpaper: give it an opaque backing (Theme.solid) or it is invisible.",
        "Read settings as settings.<key> (declared in the manifest) - the object has one typed property per key, so binding to a key is a precise dependency.",
        "Never shell out for clipboard, notifications, HTTP or opening a URL: PluginUtils does all four without a subprocess.",
        "Commands are lists, never strings: PluginUtils.exec([\"cmd\", arg]).",
        "Annotate function parameter and return types, void included, or Quickshell will not expose the function over IPC.",
        "No `required property` in a file loaded by URL - it cannot be constructed and the Loader silently draws nothing.",
        "Validate with scripts/validate-plugin.sh <id>, then scripts/check-qml.sh."
    ],

    manifest: $manifest,

    theme: {
        summary: "Semantic tokens over the Material You palette. Import qs.core and use Theme.<token>.",
        members: $theme
    },

    core: {
        summary: "Base types to inherit from, and singletons to call. Import qs.core.",
        baseTypes: [$types[] | select(.kind == "type")],
        singletons: [$types[] | select(.kind == "singleton")]
    },

    services: {
        summary: "Live system state. Import qs.services. Read-only unless a function says otherwise.",
        singletons: $services
    },

    widgets: {
        summary: "The shells widget library. Import qs.modules.common.widgets.",
        types: $widgets
    }
}' > "$tmp/api.json"

if [[ $CHECK -eq 1 ]]; then
    if ! diff -q <(jq -S . "$tmp/api.json") <(jq -S . "$OUT" 2>/dev/null || echo '{}') >/dev/null 2>&1; then
        echo "==> $OUT is out of date. Run scripts/gen-api.sh" >&2
        diff <(jq -S . "$OUT" 2>/dev/null || echo '{}') <(jq -S . "$tmp/api.json") | head -30 >&2
        exit 1
    fi
    echo "==> $OUT is up to date"
    exit 0
fi

jq . "$tmp/api.json" > "$OUT"

printf '==> %s: %s theme tokens, %s base types, %s core singletons, %s services, %s widgets, %s provides kinds\n' \
    "$OUT" \
    "$(jq '.theme.members | length' "$OUT")" \
    "$(jq '.core.baseTypes | length' "$OUT")" \
    "$(jq '.core.singletons | length' "$OUT")" \
    "$(jq '.services.singletons | length' "$OUT")" \
    "$(jq '.widgets.types | length' "$OUT")" \
    "$(jq '.manifest.kinds | length' "$OUT")"
