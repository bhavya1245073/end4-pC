# Templates for the two plugin shapes that use the whole SDK, kept in their own file because
# new-plugin.sh was already 700 lines of heredoc and these are the two longest.
#
# Sourced by new-plugin.sh with $id, $camel, $pascal, $name, $author, $schemaRef and $dir set.
# Each function writes its files and sets $files for the summary.

write_window_template() {
    files="${pascal}Panel.qml, ${pascal}State.qml, ${pascal}Ipc.qml, ${pascal}Widget.qml"

    cat > "$dir/manifest.json" <<EOF
{
  "\$schema": "$schemaRef",
  "id": "$id",
  "name": "$name",
  "version": "1.0.0",
  "apiVersion": 1,
  "description": "One line, shown under the name in Settings -> Plugins.",
  "permissions": ["storage"],
  "author": "$author",
  "icon": "web_asset",
  "enabledByDefault": true,
  "provides": {
    "panels": [
      {
        "id": "$id",
        "label": "$name",
        "entry": "${pascal}Panel.qml"
      }
    ],
    "barWidgets": [
      {
        "id": "$camel",
        "name": "$name",
        "icon": "web_asset",
        "entry": "${pascal}Widget.qml",
        "zone": "right",
        "zoneOrder": 50
      }
    ],
    "actions": [
      {
        "id": "open",
        "label": "Open $name",
        "icon": "web_asset",
        "description": "Show the $name window"
      },
      {
        "id": "toggle",
        "label": "Toggle $name",
        "icon": "web_asset"
      }
    ],
    "shortcuts": [
      {
        "id": "$id",
        "description": "Toggle $name",
        "ipc": { "target": "$camel", "function": "toggle" }
      }
    ],
    "ipc": [
      {
        "target": "$camel",
        "entry": "${pascal}Ipc.qml"
      }
    ]
  },
  "settings": [
    {
      "key": "rememberPosition",
      "type": "bool",
      "default": true,
      "label": "Remember where I put it",
      "icon": "pin_drop"
    }
  ]
}
EOF

    cat > "$dir/${pascal}Panel.qml" <<EOF
// A draggable, resizable window.
//
// PluginFloatingWindow owns the chrome, the dragging, the resize handles, remembering where
// you left it, Escape to close and click-outside to dismiss. \`panelId\` ties it to
// PanelRegistry, which is what makes every other way of opening it work at once: the keybind,
// the bar widget, \`qs ipc call $camel toggle\`, and PluginIntent.call("$id:open").
//
// Never assign \`open\`: it is derived from the registry, and assigning it would put the window
// and the registry out of step - after which toggling works on every other press. Call show(),
// hide() or toggle().

import QtQuick
import QtQuick.Layouts
import qs.core
import qs.modules.common.widgets

PluginFloatingWindow {
    id: root

    pluginId: "$id"
    panelId: "$id"
    windowId: "main"

    title: qsTr("$name")
    icon: "web_asset"

    windowWidth: 520
    windowHeight: 380
    rememberGeometry: PluginConfig.of("$id").rememberPosition ?? true

    // Buttons in the title bar, left of the close button.
    actions: Component {
        PluginIconButton {
            icon: "refresh"
            tooltip: qsTr("Refresh")
            onClicked: ${pascal}State.refresh()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.pad.l
        spacing: Theme.pad.m

        PluginCard {
            Layout.fillWidth: true

            ColumnLayout {
                spacing: Theme.pad.xs

                StyledText {
                    text: qsTr("Opened %n time(s)", "", ${pascal}State.opens)
                    color: Theme.text
                    font.pixelSize: Theme.font.m
                }

                StyledText {
                    text: qsTr("Everything here survives a restart.")
                    color: Theme.textFaint
                    font.pixelSize: Theme.font.s
                }
            }
        }

        Item {
            Layout.fillHeight: true
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.pad.s

            PluginChip {
                text: qsTr("Reset")
                icon: "restart_alt"
                tone: PluginChip.Tone.Accent
                onClicked: ${pascal}State.reset()
            }

            Item {
                Layout.fillWidth: true
            }

            PluginChip {
                text: qsTr("Close")
                onClicked: root.hide()
            }
        }
    }
}
EOF

    cat > "$dir/${pascal}State.qml" <<EOF
pragma Singleton

// State and behaviour, in one place so every view agrees.
//
// \`pragma Singleton\` is on line 1 and has to be: Quickshell's scanner gives up at the first
// \`{\` it sees, including one inside a comment, so a design note above the pragma can silently
// stop this being a singleton - and every importer then fails with a type error somewhere else.

import QtQuick
import Quickshell
import qs.core

Singleton {
    id: root

    // A scoped view of PluginUtils that carries the plugin id, so the permissions declared in
    // the manifest are actually checked and a refused call names who was refused.
    readonly property var utils: PluginUtils.as("$id")
    readonly property var store: PluginStorage.of("$id")

    readonly property int opens: root.store.get("opens", 0)

    function open(): void {
        PanelRegistry.open("$id", ({}));
        root.store.update("opens", current => (current ?? 0) + 1);
    }

    function close(): void {
        PanelRegistry.close("$id");
    }

    function toggle(): void {
        if (PanelRegistry.isOpen("$id"))
            root.close();
        else
            root.open();
    }

    function refresh(): void {
        root.utils.toast(qsTr("Refreshed"));
    }

    function reset(): void {
        // Anything destructive should be undoable, and this is the whole integration: the user
        // gets a toast with an Undo button and Ctrl+Z works on it.
        const before = root.opens;
        root.store.set("opens", 0);
        root.utils.record(qsTr("Reset the counter"), {
            undo: () => root.store.set("opens", before),
            redo: () => root.store.set("opens", 0)
        });
    }

    // Nothing that has to *register* itself belongs in a singleton: a singleton is not created
    // until something reads it. See ${pascal}Ipc.qml.
}
EOF

    cat > "$dir/qmldir" <<EOF
# Declares the singleton. Without this line \`${pascal}State\` still resolves - as the *type*,
# not the instance - so every call on it fails with "is not a function" and every property reads
# as undefined. There is no warning: it is a valid type reference to a component nobody
# instantiated.
singleton ${pascal}State 1.0 ${pascal}State.qml
EOF

    cat > "$dir/qmldir" <<EOF
# Declares the singleton. Without this line \`${pascal}State\` still resolves - as the *type*,
# not the instance - so every call on it fails with "is not a function" and every property reads
# as undefined. There is no warning: it is a valid type reference to a component nobody
# instantiated.
singleton ${pascal}State 1.0 ${pascal}State.qml
EOF

    cat > "$dir/${pascal}Ipc.qml" <<EOF
// The plugin's outside interface.
//
// Its own file, declared in the manifest under \`provides.ipc\`, because that is what the host
// *instantiates* when the plugin is switched on - a singleton would not do, since a singleton is
// not created until something reads it.
//
// These functions are the plugin's whole external surface. The manifest declares \`open\` and
// \`toggle\` under \`provides.actions\`, and an action resolves to the IPC function of the same
// name - so all of this works with nothing else written:
//
//     qs ipc call $camel toggle                    the command line
//     qs ipc call intent call $id:toggle           the same thing as an intent
//     PluginIntent.call("$id:toggle")              from another plugin
//     typing "Toggle $name" in the launcher
//     the keybind declared in the manifest
//
// Every function needs annotated parameter *and* return types. An unannotated one is silently
// left out, which is the usual reason \`ipc call\` reports "function not found".

import qs.core

PluginIpc {
    id: root

    function open(): string {
        ${pascal}State.open();
        return "opened";
    }

    function close(): string {
        ${pascal}State.close();
        return "closed";
    }

    function toggle(): string {
        ${pascal}State.toggle();
        return PanelRegistry.isOpen("$id") ? "opened" : "closed";
    }
}
EOF

    cat > "$dir/${pascal}Widget.qml" <<EOF
// The bar pill that opens the window.

import QtQuick
import qs.core
import qs.modules.common.widgets

PluginBarWidget {
    id: root

    pluginId: "$id"
    tooltip: qsTr("$name")

    onClicked: ${pascal}State.toggle()

    MaterialSymbol {
        text: "web_asset"
        iconSize: Theme.font.l
        color: root.colText
    }
}
EOF
}

write_picker_template() {
    files="${pascal}Panel.qml, ${pascal}State.qml, ${pascal}Ipc.qml, ${pascal}Widget.qml"

    cat > "$dir/manifest.json" <<EOF
{
  "\$schema": "$schemaRef",
  "id": "$id",
  "name": "$name",
  "version": "1.0.0",
  "apiVersion": 1,
  "description": "Search something and pick from the results.",
  "permissions": ["network", "clipboard", "storage"],
  "author": "$author",
  "icon": "search",
  "enabledByDefault": true,
  "provides": {
    "panels": [
      {
        "id": "$id",
        "label": "$name",
        "entry": "${pascal}Panel.qml"
      }
    ],
    "barWidgets": [
      {
        "id": "$camel",
        "name": "$name",
        "icon": "search",
        "entry": "${pascal}Widget.qml",
        "zone": "right",
        "zoneOrder": 50
      }
    ],
    "actions": [
      {
        "id": "search",
        "label": "Search $name",
        "icon": "search",
        "description": "Search and show the results",
        "schema": {
          "query": { "type": "string", "required": true, "description": "What to look for" }
        }
      }
    ],
    "ipc": [
      {
        "target": "$camel",
        "entry": "${pascal}Ipc.qml"
      }
    ]
  },
  "settings": [
    {
      "key": "resultLimit",
      "type": "int",
      "default": 30,
      "min": 5,
      "max": 100,
      "label": "Results",
      "icon": "format_list_numbered"
    }
  ]
}
EOF

    cat > "$dir/${pascal}Panel.qml" <<EOF
// A picker.
//
// PluginContentView is the entire view: a debounced search field, a grid that fits its columns
// to the available width, a still thumbnail that hands over to an animated preview on hover,
// arrow keys and Enter, hover actions, a spinner while loading and an empty state. It stops
// animating when the screen locks, and drops requests whose owner has gone away.
//
// What is left to write is what this picker is *of*.

import QtQuick
import qs.core

PluginFloatingWindow {
    id: root

    pluginId: "$id"
    panelId: "$id"
    windowId: "picker"

    title: qsTr("$name")
    icon: "search"

    windowWidth: 620
    windowHeight: 480

    PluginContentView {
        id: view
        anchors.fill: parent
        anchors.margins: Theme.pad.m

        pluginId: "$id"
        items: ${pascal}State.shown
        loading: ${pascal}State.loading
        mode: "grid"
        cellWidth: 140
        cellHeight: 112

        searchPlaceholder: qsTr("Search")
        emptyIcon: "search"
        emptyText: qsTr("Type to search")
        emptySubtitle: qsTr("Enter copies it, Tab previews, Escape closes")

        // Bound, so the provider does the filtering and the view does not filter the results a
        // remote search already narrowed.
        onSearch: text => ${pascal}State.search(text)

        onActivated: item => {
            ${pascal}State.use(item);
            root.hide();
        }

        onDismissed: root.hide()

        actions: [
            {
                id: "favourite",
                icon: "star",
                label: qsTr("Favourite"),
                onTriggered: item => ${pascal}State.favourites.toggle(item)
            }
        ]

        // The window's content is built when it opens and destroyed when it closes, so this runs
        // at exactly the right moment and typing works without a click. It has to live here
        // rather than in an \`onOpenChanged\` on the window: content is a Component, and an id
        // inside a Component is not visible from outside it.
        Component.onCompleted: view.focusSearch()
    }
}
EOF

    cat > "$dir/${pascal}State.qml" <<EOF
pragma Singleton

// Fetching, caching and remembering.
//
// Note what is *not* here: no XMLHttpRequest, no curl subprocess, no JSON.parse in a
// try/catch, no hand-written cache, no debounce timer, and no "is this response still wanted"
// flag. PluginHttp and PluginContentView own all of it.

import QtQuick
import Quickshell
import qs.core

Singleton {
    id: root

    readonly property var utils: PluginUtils.as("$id")
    readonly property var settings: PluginConfig.of("$id")

    // A reactive, persisted list. Binding to \`.list\` re-runs only when this key changes, not
    // when anything else in the plugin's storage does.
    readonly property var favourites: PluginStorage.collection("$id", "favourites")

    property var results: []
    property bool loading: false
    property string query: ""

    // With no query, show what was favourited: more useful than an empty grid, and the reason a
    // picker is worth opening a second time.
    readonly property var shown: root.query.length === 0 ? root.favourites.list : root.results

    function search(text: string): void {
        root.query = text ?? "";
        if (root.query.length === 0) {
            root.results = [];
            root.loading = false;
            return;
        }

        root.loading = true;

        // Replace this URL with a real one. \`cacheTtl\` makes a repeated search instant,
        // \`owner\` drops the callback if this goes away, \`query\` is encoded properly, and the
        // "network" permission is checked because the plugin id is attached.
        root.utils.get("https://api.example.com/search", {
            query: { q: root.query, limit: root.settings.resultLimit ?? 30 },
            cacheTtl: 5 * 60 * 1000,
            owner: root
        }, response => {
            root.loading = false;

            if (!response.ok) {
                root.utils.toast(qsTr("Search failed: %1").arg(response.error));
                return;
            }

            // Shape the provider's rows into what PluginContentView reads: id, title, subtitle,
            // thumbnail, preview. Anything else you add is available to a custom delegate.
            root.results = (response.json?.items ?? []).map(item => ({
                id: item.id,
                title: item.name,
                subtitle: item.description,
                thumbnail: item.thumb,
                preview: item.animated,
                url: item.url
            }));
        });
    }

    function use(item: var): void {
        if (!item)
            return;
        root.utils.copy(item.url ?? item.id ?? "");
        root.utils.toast(qsTr("Copied"));
        // A history worth having, capped so it cannot grow without limit.
        PluginStorage.collection("$id", "recent").add(item, 40);
    }
}
EOF

    cat > "$dir/qmldir" <<EOF
# Declares the singleton. Without this line \`${pascal}State\` still resolves - as the *type*, not
# the instance - so every call on it fails with "is not a function" and every property reads as
# undefined. There is no warning: it is a valid type reference to a component nobody instantiated.
singleton ${pascal}State 1.0 ${pascal}State.qml
EOF

    cat > "$dir/${pascal}Ipc.qml" <<EOF
// The plugin's outside interface. Its own file, declared under \`provides.ipc\`, because that is
// what the host instantiates when the plugin is switched on - see the note in ${pascal}State.qml.
//
// \`search\` is also declared in the manifest under \`provides.actions\`, and an action resolves to
// the IPC function of the same name. Its declared \`query\` argument is validated first, so by the
// time this runs it is present and it is a string. All of these reach this one function:
//
//     qs ipc call $camel search cat
//     qs ipc call intent call $id:search 'query=cat'
//     qs ipc call intent call $id:search cat          (a bare value fills the first argument)
//     typing "$name cat" in the launcher
//     PluginIntent.call("$id:search", { query: "cat" })   from another plugin

import qs.core

PluginIpc {
    id: root

    function open(): string {
        PanelRegistry.open("$id", ({}));
        return "opened";
    }

    function search(query: string): string {
        PanelRegistry.open("$id", ({}));
        ${pascal}State.search(query);
        return \`searching for \${query}\`;
    }
}
EOF

    cat > "$dir/${pascal}Widget.qml" <<EOF
// The bar pill that opens the picker.

import QtQuick
import qs.core
import qs.modules.common.widgets

PluginBarWidget {
    id: root

    pluginId: "$id"
    tooltip: qsTr("$name")

    onClicked: PanelRegistry.toggle("$id", ({}))

    MaterialSymbol {
        text: "search"
        iconSize: Theme.font.l
        color: root.colText
    }
}
EOF
}
