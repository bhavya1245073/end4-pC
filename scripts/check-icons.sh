#!/usr/bin/env bash
# Verify every Material Symbol name used in QML is a real ligature in the font.
#
# An unknown name does not fail, warn, or draw a placeholder - the font simply renders
# the string, so `icon: "power_plug"` puts the word PLUG in your UI at whatever size the
# icon was meant to be. That is how the battery widget ended up with "PLUG" across it.
#
# Detection is by width: a ligature that exists collapses to one glyph (~1em), and one
# that does not stays as many characters of text.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v magick >/dev/null 2>&1; then
    echo "check-icons.sh: needs ImageMagick (magick); skipping" >&2
    exit 0
fi

font="$(fc-match -f "%{file}" "Material Symbols Rounded" 2>/dev/null)"
if [[ -z "$font" || ! -e "$font" ]]; then
    echo "check-icons.sh: Material Symbols Rounded not installed; skipping" >&2
    exit 0
fi

# One em at this size. A real glyph lands near it; rendered text runs well past.
size=48
threshold=90

mapfile -t names < <(
    {
        # Property assignments: `icon: "bolt"`, `buttonIcon: "tune"`, ...
        grep -rhoE '(icon|buttonIcon|materialIcon|symbol)[A-Za-z]*:[[:space:]]*"[a-z][a-z_0-9]*"' \
            --include='*.qml' . \
            | grep -oE '"[a-z][a-z_0-9]*"'

        # Strings returned from a function whose name mentions an icon. Scoped to those
        # functions on purpose: plenty of other functions return snake_case strings that
        # are not icons ("hyprland", "center", "monospace"), and blanket-scanning every
        # return produced more false alarms than findings.
        find . -name '*.qml' -not -path './.git/*' -print0 \
            | xargs -0 awk '
                /^[[:space:]]*function[[:space:]]/ {
                    inIcon = (tolower($0) ~ /function[[:space:]]+[a-z_]*icon/)
                }
                inIcon && match($0, /return[[:space:]]+"[a-z][a-z_0-9]*"/) {
                    s = substr($0, RSTART, RLENGTH)
                    sub(/return[[:space:]]+/, "", s)
                    print s
                }
            '
    } | tr -d '"' | sort -u
)

echo "==> Checking ${#names[@]} Material Symbol name(s) against $(basename "$font")..."

bad=0
for name in "${names[@]}"; do
    width="$(magick -font "$font" -pointsize "$size" label:"$name" -format "%w" info: 2>/dev/null || echo 0)"
    if (( ${width:-0} > threshold )); then
        (( bad == 0 )) && echo "==> Names the font does not have (they render as text):"
        bad=$(( bad + 1 ))
        printf '    INVALID %-28s renders %spx wide\n' "$name" "$width"
        grep -rn --include='*.qml' "\"$name\"" . | sed 's/^/             /' | head -4
    fi
done

if (( bad )); then
    echo "ICONCHECK DONE checked=${#names[@]} invalid=$bad"
    exit 1
fi

echo "ICONCHECK DONE checked=${#names[@]} invalid=0"
