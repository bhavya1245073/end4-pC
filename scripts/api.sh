#!/usr/bin/env bash
# Look something up in the API catalogue without reading it.
#
#     scripts/api.sh                       what is in the catalogue
#     scripts/api.sh theme                 every Theme token
#     scripts/api.sh theme color           just the colours
#     scripts/api.sh PluginDesktopCard     one type, with its members
#     scripts/api.sh Battery               one service
#     scripts/api.sh StyledText            one widget
#     scripts/api.sh manifest barWidgets   the manifest contract for one provides kind
#     scripts/api.sh find accent           anything whose name mentions "accent"
#     scripts/api.sh rules                 the short list of things that bite
#
# core/api.json is generated from the source (scripts/gen-api.sh), so what this prints
# is what the code actually declares, not what the docs remember it declaring.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
API="$ROOT/core/api.json"

if [[ ! -f "$API" ]]; then
    echo "no $API - run scripts/gen-api.sh" >&2
    exit 1
fi

q() { jq -r "$@" "$API"; }

# Compact one-line rendering of a member record, so a type fits on a screen.
member_lines='
def render:
    if .kind == "function" then "  \(.name)(\(.args // "")) -> \(.returns // "var")"
    elif .kind == "signal" then "  signal \(.name)(\(.args // ""))"
    elif .kind == "enum" then "  enum \(.name) { \(.values) }"
    else "  \(if .readonly then "readonly " else "" end)\(.type) \(.name)\(if .default then " = \(.default)" else "" end)"
    end
    + (if (.doc // "") != "" then "\n      \(.doc)" else "" end);
'

case "${1:-}" in
"")
    printf 'API catalogue: %s\n\n' "$(basename "$API")"
    printf '  apiVersion    %s\n' "$(q '.apiVersion')"
    printf '  theme         %s tokens\n' "$(q '.theme.members | length')"
    printf '  base types    %s   %s\n' "$(q '.core.baseTypes | length')" "$(q '[.core.baseTypes[].name] | join(", ")' | fold -s -w 60 | sed '2,$s/^/                    /')"
    printf '  singletons    %s   %s\n' "$(q '.core.singletons | length')" "$(q '[.core.singletons[].name] | join(", ")' | fold -s -w 62 | sed '2,$s/^/                    /')"
    printf '  services      %s\n' "$(q '.services.singletons | length')"
    printf '  widgets       %s\n' "$(q '.widgets.types | length')"
    printf '  provides      %s\n' "$(q '[.manifest.kinds[].kind] | join(", ")' | fold -s -w 62 | sed '2,$s/^/                /')"
    printf '\nTry: %s rules | theme | <TypeName> | find <text>\n' "$(basename "$0")"
    ;;

rules)
    q '.readMeFirst[] | "- " + .'
    ;;

theme)
    filter="${2:-}"
    if [[ -n "$filter" ]]; then
        q --arg f "$filter" "$member_lines"'.theme.members[] | select(((.type // "") == $f) or ((.name // "") | test($f; "i"))) | render'
    else
        q "$member_lines"'.theme.members[] | render'
    fi
    ;;

manifest)
    kind="${2:-}"
    if [[ -z "$kind" ]]; then
        q '.manifest.kinds[] | "\(.kind)"'
        exit 0
    fi
    # A provides kind points at a definition; print that definition's fields.
    ref="$(q --arg k "$kind" '.manifest.kinds[] | select(.kind == $k) | .ref // ""' | sed 's|#/definitions/||')"
    if [[ -z "$ref" ]]; then
        echo "no provides kind \"$kind\". Known: $(q '[.manifest.kinds[].kind] | join(", ")')" >&2
        exit 1
    fi
    q --arg d "$ref" '
        .manifest.definitions[$d] as $def
        | "\($d): \($def.description)",
          (if ($def.required | length) > 0 then "required: \($def.required | join(", "))" else empty end),
          "",
          ($def.fields | to_entries[] | "  \(.key)  (\(.value.type))\(if .value.default != null then " default \(.value.default)" else "" end)"
            + (if .value.enum then "  one of: \(.value.enum | join(", "))" else "" end)
            + (if .value.description != "" then "\n      \(.value.description)" else "" end))'
    ;;

find)
    needle="${2:?usage: api.sh find <text>}"
    q --arg n "$needle" '
        [ (.theme.members[] | select(.name | test($n; "i")) | "theme       Theme.\(.name)  (\(.type // .kind))")
        , (.core.baseTypes[] | select(.name | test($n; "i")) | "base type   \(.name)")
        , (.core.baseTypes[] as $t | $t.members[] | select(.name | test($n; "i")) | "member      \($t.name).\(.name)")
        , (.core.singletons[] | select(.name | test($n; "i")) | "singleton   \(.name)")
        , (.core.singletons[] as $t | $t.members[] | select(.name | test($n; "i")) | "member      \($t.name).\(.name)")
        , (.services.singletons[] | select(.name | test($n; "i")) | "service     \(.name)")
        , (.services.singletons[] as $s | ($s.properties | keys[]) | select(test($n; "i")) | "service     \($s.name).\(.)")
        , (.widgets.types[] | select(.name | test($n; "i")) | "widget      \(.name)")
        ] | unique | .[]'
    ;;

*)
    name="$1"
    found=0

    # A core type or singleton: full detail, since this is the API a plugin is written
    # against.
    if [[ "$(q --arg n "$name" '[.core.baseTypes[], .core.singletons[]] | map(select(.name == $n)) | length')" != "0" ]]; then
        q --arg n "$name" "$member_lines"'
            [.core.baseTypes[], .core.singletons[]] | .[] | select(.name == $n)
            | "\(.name)  (\(.kind), extends \(.extends))",
              (if .summary != "" then "\n\(.summary)\n" else "" end),
              (.members[] | render)'
        found=1
    fi

    if [[ "$(q --arg n "$name" '.services.singletons | map(select(.name == $n)) | length')" != "0" ]]; then
        q --arg n "$name" '
            .services.singletons[] | select(.name == $n)
            | "\(.name)  (service singleton - import qs.services)",
              (if .summary != "" then "\n\(.summary)\n" else "" end),
              (.properties | to_entries[] | "  \(.value) \(.key)"),
              (if (.functions | length) > 0 then "" else empty end),
              (.functions[] | "  \(.)")'
        found=1
    fi

    if [[ "$(q --arg n "$name" '.widgets.types | map(select(.name == $n)) | length')" != "0" ]]; then
        q --arg n "$name" '
            .widgets.types[] | select(.name == $n)
            | "\(.name)  (widget, extends \(.extends) - import qs.modules.common.widgets)",
              "",
              (.properties | to_entries[] | "  \(.value) \(.key)")'
        found=1
    fi

    if [[ $found -eq 0 ]]; then
        echo "nothing called \"$name\". Close matches:" >&2
        "$0" find "$name" >&2 || true
        exit 1
    fi
    ;;
esac
