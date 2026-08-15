#!/usr/bin/env bash
# Scaffolds a new plugin under plugins/<id>/.
#
#   scripts/new-plugin.sh my-plugin ["My Plugin"]
#
# See docs/PLUGINS.md for what to do with it.

set -euo pipefail

id="${1:-}"
name="${2:-}"

if [[ -z "$id" ]]; then
    echo "usage: $(basename "$0") <plugin-id> [\"Display Name\"]" >&2
    exit 1
fi

if [[ ! "$id" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    echo "error: plugin id must be lowercase letters, digits and dashes: '$id'" >&2
    exit 1
fi

# "my-cool-plugin" -> "My Cool Plugin"
if [[ -z "$name" ]]; then
    name="$(echo "$id" | tr '-' ' ' | sed -E 's/(^| )([a-z])/\1\u\2/g')"
fi

# "my-cool-plugin" -> "myCoolPlugin", for widget ids
camel="$(echo "$id" | sed -E 's/-([a-z])/\u\1/g')"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$repo_root/plugins/$id"

if [[ -e "$dir" ]]; then
    echo "error: $dir already exists" >&2
    exit 1
fi

mkdir -p "$dir"

cat > "$dir/manifest.json" <<EOF
{
    "id": "$id",
    "name": "$name",
    "version": "0.1.0",
    "apiVersion": 1,
    "description": "",
    "author": "$(git -C "$repo_root" config user.name 2>/dev/null || echo "$USER")",
    "icon": "extension",
    "enabledByDefault": false,
    "provides": {
        "barWidgets": [
            {
                "id": "$camel",
                "name": "$name",
                "icon": "extension",
                "entry": "BarWidget.qml"
            }
        ]
    },
    "settings": [
        {
            "key": "label",
            "type": "string",
            "default": "$name",
            "label": "Label",
            "description": "Text shown in the bar.",
            "icon": "label"
        }
    ]
}
EOF

cat > "$dir/BarWidget.qml" <<EOF
import QtQuick
import qs.core
import qs.modules.common
import qs.modules.common.widgets

PluginBarWidget {
    id: root

    readonly property var settings: PluginConfig.of("$id")

    StyledText {
        text: root.settings.label ?? ""
        color: Appearance.colors.colOnLayer1
    }
}
EOF

cat > "$dir/README.md" <<EOF
# $name

What it does.

## Settings

- **Label** - text shown in the bar.
EOF

echo "Created $dir"
echo
echo "Next:"
echo "  1. Enable it:  Settings -> Plugins -> $name"
echo "  2. Add the widget:  Settings -> Bar -> layout"
echo "  3. Read docs/PLUGINS.md for panels, services, desktop widgets and settings types"
