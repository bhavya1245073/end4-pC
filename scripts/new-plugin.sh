#!/usr/bin/env bash
# Scaffold a plugin that already works.
#
#     scripts/new-plugin.sh weather-pill                       # bar widget (default)
#     scripts/new-plugin.sh notes --type desktop
#     scripts/new-plugin.sh units --type search
#     scripts/new-plugin.sh focus --type toggle
#     scripts/new-plugin.sh backup --type service
#     scripts/new-plugin.sh pomodoro --type osd
#     scripts/new-plugin.sh clipboard --type menu
#
#     --into <dir>    where to put it. Defaults to this tree's plugins/.
#     --name "..."    display name. Defaults to the id, title-cased.
#
# What comes out is a plugin that passes scripts/validate-plugin.sh, appears in
# Settings -> Plugins, and draws something on screen - so the first thing you do is
# replace behaviour, not write boilerplate. Every template uses the base types and
# PluginUtils rather than hand-rolling layout, hover states or subprocesses.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

id=""
name=""
type="bar"
into="$ROOT/plugins"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --type) type="${2:?--type needs a value}"; shift 2 ;;
        --name) name="${2:?--name needs a value}"; shift 2 ;;
        --into) into="${2:?--into needs a value}"; shift 2 ;;
        -h|--help) sed -n '2,20p' "$0" | sed 's|^# \?||'; exit 0 ;;
        -*) echo "unknown flag: $1" >&2; exit 1 ;;
        *) id="$1"; shift ;;
    esac
done

if [[ -z "$id" ]]; then
    echo "usage: $(basename "$0") <plugin-id> [--type bar|desktop|toggle|service|ipc|search|osd|menu] [--name \"Display Name\"] [--into DIR]" >&2
    exit 1
fi

# The id is a folder name, a JSON key, part of a QML path and a config key.
if [[ ! "$id" =~ ^[a-z][a-z0-9-]*$ ]]; then
    echo "error: plugin id must be lowercase letters, digits and dashes, starting with a letter: '$id'" >&2
    exit 1
fi

# "my-cool-plugin" -> "My Cool Plugin"
[[ -n "$name" ]] || name="$(echo "$id" | tr '-' ' ' | sed -E 's/(^| )([a-z])/\1\u\2/g')"
# "my-cool-plugin" -> "myCoolPlugin", for widget and provides ids
camel="$(echo "$id" | sed -E 's/-([a-z])/\u\1/g')"
# "my-cool-plugin" -> "MyCoolPlugin", for file names
pascal="$(echo "$camel" | sed -E 's/^(.)/\u\1/')"

dir="$into/$id"
if [[ -e "$dir" ]]; then
    echo "error: already exists: $dir" >&2
    exit 1
fi

author="$(git -C "$ROOT" config user.name 2>/dev/null || echo "")"
mkdir -p "$dir"

# Where the schema is, relative to the plugin folder. A plugin in this tree gets
# ../../core/..., one in the NixOS config gets a path back to this checkout - which is
# what makes editor completion work for a plugin that lives somewhere else. Relative
# rather than absolute so a plugin folder stays movable between machines with the same
# layout.
schemaRef="$(realpath --relative-to="$dir" "$ROOT/core/manifest.schema.json" 2>/dev/null || echo "$ROOT/core/manifest.schema.json")"

# ── templates ────────────────────────────────────────────────────────────────
# Each writes manifest.json plus its QML, and sets $files for the summary.

files=""

case "$type" in
bar)
    files="${pascal}Widget.qml"
    cat > "$dir/manifest.json" <<EOF
{
  "\$schema": "$schemaRef",
  "id": "$id",
  "name": "$name",
  "version": "1.0.0",
  "apiVersion": 1,
  "description": "One line, shown under the name in Settings -> Plugins.",
  "author": "$author",
  "icon": "extension",
  "enabledByDefault": true,
  "provides": {
    "barWidgets": [
      {
        "id": "$camel",
        "name": "$name",
        "icon": "extension",
        "entry": "${pascal}Widget.qml",
        "pillColor": "secondaryContainer",
        "zone": "right",
        "zoneOrder": 50
      }
    ]
  },
  "settings": [
    {
      "key": "label",
      "type": "string",
      "default": "hello",
      "label": "Label",
      "description": "Shown in the bar.",
      "icon": "label"
    },
    {
      "key": "showIcon",
      "type": "bool",
      "default": true,
      "label": "Show icon",
      "icon": "visibility"
    }
  ]
}
EOF

    cat > "$dir/${pascal}Widget.qml" <<EOF
// A bar widget.
//
// \`zone: "right"\` in the manifest places it the first time the plugin is enabled, so
// there is nothing to drag in before you can see it.
//
// \`settings\` has one typed property per manifest key, so \`settings.label\` re-runs this
// binding only when that key changes.

import QtQuick
import QtQuick.Layouts
import qs.core
import qs.modules.common.widgets

PluginBarWidget {
    id: root

    pluginId: "$id"
    tooltip: qsTr("$name")

    onClicked: PluginUtils.notify(qsTr("$name"), qsTr("Clicked"))

    // Content sizes itself; do not anchor it to fill the widget. The bar measures the
    // widget by what is inside it.
    RowLayout {
        spacing: Theme.pad.s

        MaterialSymbol {
            visible: root.settings.showIcon
            text: "extension"
            iconSize: Theme.font.l
            color: root.colText
        }

        StyledText {
            text: root.settings.label ?? ""
            color: root.colText
            font.pixelSize: Theme.font.m
        }
    }
}
EOF
    ;;

desktop)
    files="${pascal}Widget.qml"
    cat > "$dir/manifest.json" <<EOF
{
  "\$schema": "$schemaRef",
  "id": "$id",
  "name": "$name",
  "version": "1.0.0",
  "apiVersion": 1,
  "description": "One line, shown under the name in Settings -> Plugins.",
  "author": "$author",
  "icon": "extension",
  "enabledByDefault": true,
  "provides": {
    "desktopWidgets": [
      {
        "id": "${camel}Card",
        "name": "$name",
        "icon": "extension",
        "entry": "${pascal}Widget.qml",
        "enabledByDefault": true
      }
    ]
  },
  "settings": [
    {
      "key": "body",
      "type": "string",
      "default": "Drag me. Resize me from the bottom-right corner.",
      "label": "Text",
      "icon": "notes"
    }
  ]
}
EOF

    cat > "$dir/${pascal}Widget.qml" <<EOF
// A desktop widget, as a card: opaque backing, header with actions, drag, resize, and
// both position and size remembered - all from PluginDesktopCard.
//
// Content goes in the default slot, which is a ColumnLayout, so children use
// Layout.fillWidth and get real layout behaviour.

import QtQuick
import QtQuick.Layouts
import qs.core
import qs.modules.common.widgets

PluginDesktopCard {
    id: root

    pluginId: "$id"
    widgetId: "${camel}Card"        // must match the manifest entry's id

    title: qsTr("$name")
    icon: "extension"

    actions: [
        PluginIconButton {
            icon: "content_copy"
            tooltip: qsTr("Copy")
            onClicked: PluginUtils.copy(root.settings.body ?? "")
        }
    ]

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: root.settings.body ?? ""
        color: root.colText
        font.pixelSize: Theme.font.m
    }

    footer: [
        StyledText {
            Layout.fillWidth: true
            text: qsTr("Right-click the desktop to lock widgets in place")
            color: Theme.textFaint
            font.pixelSize: Theme.font.xs
            elide: Text.ElideRight
        }
    ]
}
EOF
    ;;

toggle)
    files="${pascal}Toggle.qml"
    cat > "$dir/manifest.json" <<EOF
{
  "\$schema": "$schemaRef",
  "id": "$id",
  "name": "$name",
  "version": "1.0.0",
  "apiVersion": 1,
  "description": "One line, shown under the name in Settings -> Plugins.",
  "author": "$author",
  "icon": "toggle_on",
  "enabledByDefault": true,
  "provides": {
    "quickToggles": [
      {
        "id": "$camel",
        "name": "$name",
        "icon": "toggle_on",
        "entry": "${pascal}Toggle.qml"
      }
    ]
  },
  "settings": [
    {
      "key": "active",
      "type": "bool",
      "default": false,
      "label": "Currently on",
      "description": "Stored state, so the tile survives a restart.",
      "icon": "power_settings_new"
    }
  ]
}
EOF

    cat > "$dir/${pascal}Toggle.qml" <<EOF
// A quick settings tile. Inherits the Android-style button, which the classic panel
// renders too, so one file covers both styles.
//
// The button is a shell, and the toggleModel is the contract: name, icon, state, action,
// and optionally a status line, a tooltip and an expanded menu. It is the same model
// every built-in toggle uses, so anything they can do this can do.
//
// It appears in the unused-toggle tray and drags into the grid like any built-in.

import QtQuick
import qs.core
import qs.modules.common.models.quickToggles
import qs.modules.ii.sidebarRight.quickToggles.androidStyle

AndroidQuickToggleButton {
    id: root

    readonly property var settings: PluginConfig.of("$id")

    toggleModel: QuickToggleModel {
        name: qsTr("$name")
        icon: root.settings.active ? "toggle_on" : "toggle_off"
        toggled: root.settings.active
        tooltipText: qsTr("$name")
        statusText: root.settings.active ? qsTr("On") : qsTr("Off")

        mainAction: () => PluginConfig.set("$id", "active", !root.settings.active)
    }
}
EOF
    ;;

service)
    files="${pascal}Service.qml, ${pascal}Ipc.qml"
    cat > "$dir/manifest.json" <<EOF
{
  "\$schema": "$schemaRef",
  "id": "$id",
  "name": "$name",
  "version": "1.0.0",
  "apiVersion": 1,
  "description": "One line, shown under the name in Settings -> Plugins.",
  "author": "$author",
  "icon": "settings_suggest",
  "enabledByDefault": false,
  "provides": {
    "services": [{ "entry": "${pascal}Service.qml" }],
    "ipc": [{ "entry": "${pascal}Ipc.qml" }],
    "shortcuts": [
      {
        "id": "${camel}Run",
        "description": "Run $name now",
        "suggestedKey": "SUPER SHIFT, R",
        "ipc": { "target": "$id", "function": "run" }
      }
    ]
  },
  "settings": [
    {
      "key": "intervalMinutes",
      "type": "int",
      "default": 30,
      "min": 1,
      "max": 1440,
      "step": 1,
      "label": "Interval",
      "description": "How often to run, in minutes.",
      "icon": "timer"
    }
  ]
}
EOF

    cat > "$dir/${pascal}Service.qml" <<EOF
// A background service: no UI, runs while the plugin is enabled.
//
// Loaded asynchronously by the host, so nothing here blocks startup. Keep it cheap:
// this is always running.

import QtQuick
import qs.core

Item {
    id: root

    readonly property var settings: PluginConfig.of("$id")

    function run(): void {
        // Replace with the actual work. PluginUtils.run gives you stdout without a shell:
        //
        //     PluginUtils.run(["systemctl", "--user", "is-active", "foo"], (out, code) => {
        //         console.log("exit", code, out.trim());
        //     });
        PluginUtils.notify(qsTr("$name"), qsTr("Ran at %1").arg(new Date().toLocaleTimeString()));
    }

    Timer {
        // A settings change re-evaluates this, so the user's interval applies without a
        // restart.
        interval: Math.max(1, root.settings.intervalMinutes) * 60 * 1000
        running: true
        repeat: true
        onTriggered: root.run()
    }
}
EOF

    cat > "$dir/${pascal}Ipc.qml" <<EOF
// Commands this plugin adds:
//
//     qs -c end4-pC ipc call $id run
//     qs -c end4-pC ipc call $id status
//
// Annotate parameter and return types, void included: Quickshell needs them to marshal a
// call, and an unannotated function is not exposed at all.

import qs.core

PluginIpc {
    id: root

    function run(): string {
        // Reaching the service directly is not possible from here - go through a
        // singleton or, as here, do the work in one place.
        PluginUtils.notify(qsTr("$name"), qsTr("Triggered from IPC"));
        return "ok";
    }

    function status(): string {
        return \`every \${PluginConfig.of("$id").intervalMinutes} minutes\`;
    }
}
EOF
    ;;

ipc)
    files="${pascal}Ipc.qml"
    cat > "$dir/manifest.json" <<EOF
{
  "\$schema": "$schemaRef",
  "id": "$id",
  "name": "$name",
  "version": "1.0.0",
  "apiVersion": 1,
  "description": "One line, shown under the name in Settings -> Plugins.",
  "author": "$author",
  "icon": "terminal",
  "enabledByDefault": true,
  "provides": {
    "ipc": [{ "entry": "${pascal}Ipc.qml" }],
    "shortcuts": [
      {
        "id": "${camel}Go",
        "description": "$name",
        "suggestedKey": "SUPER, slash",
        "ipc": { "target": "$id", "function": "go" }
      }
    ]
  }
}
EOF

    cat > "$dir/${pascal}Ipc.qml" <<EOF
// Commands and a keybind, with no UI at all.
//
//     qs -c end4-pC ipc call $id go
//     qs -c end4-pC ipc call plugins shortcuts     # prints the bind line to paste
//
// Annotate parameter and return types, void included, or the function is not exposed.

import qs.core

PluginIpc {
    id: root

    function go(): string {
        PluginUtils.notify(qsTr("$name"), qsTr("Hello"));
        return "ok";
    }

    function echo(text: string): string {
        return text;
    }
}
EOF
    ;;

search)
    files="${pascal}Provider.qml"
    cat > "$dir/manifest.json" <<EOF
{
  "\$schema": "$schemaRef",
  "id": "$id",
  "name": "$name",
  "version": "1.0.0",
  "apiVersion": 1,
  "description": "One line, shown under the name in Settings -> Plugins.",
  "author": "$author",
  "icon": "manage_search",
  "enabledByDefault": true,
  "provides": {
    "searchProviders": [
      {
        "id": "$camel",
        "entry": "${pascal}Provider.qml",
        "prefix": "",
        "minLength": 2,
        "order": 40,
        "limit": 5
      }
    ]
  }
}
EOF

    cat > "$dir/${pascal}Provider.qml" <<EOF
// A live launcher provider: asked about every query, answers with whatever it likes.
//
// Rules that matter:
//   - search() runs on the UI thread on every keystroke. Return fast; do slow work
//     asynchronously and assign \`results\` when it lands.
//   - Check the cheap condition first and return [] - do not build rows you throw away.
//   - Return [], never null.

import QtQuick
import qs.core

PluginSearchProvider {
    id: root

    function search(query: string): var {
        // Replace with the real thing. This one answers "N km" / "N mi".
        const match = query.match(/^([\\d.]+)\\s*(km|mi)\$/i);
        if (!match)
            return [];

        const value = parseFloat(match[1]);
        const toMiles = match[2].toLowerCase() === "km";
        const converted = toMiles ? value / 1.609344 : value * 1.609344;
        const unit = toMiles ? "mi" : "km";
        const text = \`\${converted.toFixed(2)} \${unit}\`;

        return [{
            name: text,
            subtitle: qsTr("$name"),
            icon: "straighten",
            onActivate: () => PluginUtils.copy(text)
        }];
    }
}
EOF
    ;;

osd)
    files="${pascal}Osd.qml, ${pascal}Ipc.qml"
    cat > "$dir/manifest.json" <<EOF
{
  "\$schema": "$schemaRef",
  "id": "$id",
  "name": "$name",
  "version": "1.0.0",
  "apiVersion": 1,
  "description": "One line, shown under the name in Settings -> Plugins.",
  "author": "$author",
  "icon": "cast",
  "enabledByDefault": true,
  "provides": {
    "osdIndicators": [
      {
        "id": "$camel",
        "entry": "${pascal}Osd.qml",
        "timeout": 3000
      }
    ],
    "ipc": [{ "entry": "${pascal}Ipc.qml" }],
    "shortcuts": [
      {
        "id": "${camel}Show",
        "description": "Show the $name HUD",
        "suggestedKey": "SUPER, o",
        "ipc": { "target": "$id", "function": "show" }
      }
    ]
  }
}
EOF

    cat > "$dir/${pascal}Osd.qml" <<EOF
// A HUD, shown over everything and dismissed on a timer.
//
// Draw content only: the shell owns the window, the placement, the timeout and
// dismiss-on-hover. Show it with OsdRegistry.show("$camel") from anywhere.

import QtQuick
import QtQuick.Layouts
import qs.core
import qs.modules.common.widgets

Rectangle {
    id: root

    implicitWidth: layout.implicitWidth + Theme.pad.xl * 2
    implicitHeight: layout.implicitHeight + Theme.pad.l * 2
    radius: Theme.radius.full
    color: Theme.solid

    RowLayout {
        id: layout
        anchors.centerIn: parent
        spacing: Theme.pad.m

        MaterialSymbol {
            text: "cast"
            iconSize: Theme.font.xl
            color: Theme.accent
        }

        StyledText {
            text: qsTr("$name")
            color: Theme.text
            font.pixelSize: Theme.font.m
        }
    }
}
EOF

    cat > "$dir/${pascal}Ipc.qml" <<EOF
import qs.core

PluginIpc {
    id: root

    function show(): void {
        OsdRegistry.show("$camel");
    }
}
EOF
    ;;

menu)
    files="${pascal}Ipc.qml"
    cat > "$dir/manifest.json" <<EOF
{
  "\$schema": "$schemaRef",
  "id": "$id",
  "name": "$name",
  "version": "1.0.0",
  "apiVersion": 1,
  "description": "One line, shown under the name in Settings -> Plugins.",
  "author": "$author",
  "icon": "menu",
  "enabledByDefault": true,
  "provides": {
    "contextMenuItems": [
      {
        "id": "$camel",
        "label": "$name",
        "icon": "bolt",
        "order": 25,
        "ipc": { "target": "$id", "function": "activate" }
      }
    ],
    "ipc": [{ "entry": "${pascal}Ipc.qml" }]
  }
}
EOF

    cat > "$dir/${pascal}Ipc.qml" <<EOF
// A row in the desktop right-click menu. \`order: 25\` puts it between Widgets (20) and
// DropShelf (30).
//
// The menu calls this in-process, so it costs no subprocess and can touch live state.

import qs.core

PluginIpc {
    id: root

    function activate(): void {
        PluginUtils.notify(qsTr("$name"), qsTr("Chosen from the desktop menu"));
    }
}
EOF
    ;;

*)
    rmdir "$dir"
    echo "unknown --type \"$type\". One of: bar, desktop, toggle, service, ipc, search, osd, menu" >&2
    exit 1
    ;;
esac

# Flakes only see files git knows about, and the NixOS config installs plugins from a
# git-tracked path. An untracked folder evaluates to nothing, installs nothing, and
# reports no error - so record the intent to add it now.
if git -C "$into" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$into" add -N "$dir" >/dev/null 2>&1 || true
fi

# ── verify what we just wrote ────────────────────────────────────────────────
# A scaffolder that emits something broken is worse than none, so the template is
# validated before it is handed over.

echo "Created ${dir}"
echo "  manifest.json, $files"
echo

if [[ -x "$ROOT/scripts/validate-plugin.sh" ]]; then
    "$ROOT/scripts/validate-plugin.sh" "$dir" --no-qml || true
    echo
fi

cat <<EOF
Next:
  \$EDITOR $dir/manifest.json
  scripts/validate-plugin.sh $id          # manifest, references, QML, icons
  scripts/api.sh rules                    # the things that bite
  scripts/api.sh <TypeName>               # what a base type or service offers

Then restart the shell: qs kill; qs -c end4-pC
EOF
