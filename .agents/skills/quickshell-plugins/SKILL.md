---
name: quickshell-plugins
description: Build and modify plugins for the end4-pC Quickshell desktop shell, and safely edit its core. Use for any work in the end4-pC fork or a shell tree containing core/PluginRegistry.qml — bar widgets, desktop widgets, panels, background services, settings pages and sections, launcher actions, keybinds, Material You theming of QML widgets, and the check-qml.sh verification workflow. Covers the plugin API (Theme, PluginBarWidget, PluginPopup, PluginRow, PluginCard, PluginConfig), the manifest format, the two failure modes that silently kill a plugin, and what the plugin system cannot do.
compatibility: Needs a Wayland session to run scripts/check-qml.sh (Quickshell will not start without one). Quickshell 0.3+, Qt 6.7+.
---

# Quickshell plugins (end4-pC)

A plugin is **one folder** under `plugins/` with a `manifest.json`. Nothing else
installs it: no core file to edit, no import to register, no Nix change.

Work from this document. The tree is ~560 QML files and reading it to answer
"what colour should this text be" is how you end up with a widget that is
invisible in light mode.

## Orientation

| Path | What |
| --- | --- |
| `core/` | the plugin system. `PluginRegistry`, `PluginConfig`, `Theme`, base types |
| `plugins/<id>/` | one plugin |
| `modules/common/widgets/` | the shell's widget library (`StyledText`, `MaterialSymbol`, …) |
| `modules/common/Appearance.qml` | the full palette. Prefer `Theme` |
| `modules/ii/` | the illogical-impulse panel family: bar, sidebars, settings, background |
| `services/` | singletons: `Battery`, `Audio`, `Network`, `DateTime`, `Translation`, `WM` … |
| `scripts/check-qml.sh` | compiles everything. **Run this.** |
| `docs/PLUGINS.md` | the authoring guide this skill summarises |

## The 60-second plugin

```
plugins/hello/
├── manifest.json
└── HelloWidget.qml
```

```json
{
    "id": "hello",
    "name": "Hello",
    "version": "1.0.0",
    "apiVersion": 1,
    "description": "One line, shown in Settings -> Plugins.",
    "icon": "waving_hand",
    "enabledByDefault": true,
    "provides": {
        "barWidgets": [
            { "id": "hello", "name": "Hello", "icon": "waving_hand",
              "entry": "HelloWidget.qml", "pillColor": "secondaryContainer" }
        ]
    },
    "settings": [
        { "key": "who", "type": "string", "default": "world", "label": "Greet" }
    ]
}
```

```qml
import QtQuick
import qs.core
import qs.modules.common.widgets

PluginBarWidget {
    id: root
    pluginId: "hello"
    tooltip: qsTr("A greeting")

    StyledText {
        text: `hello ${root.settings.who}`
        color: root.colText
    }
}
```

`id` must equal the folder name. `manifest.json` is the only schema: the settings
GUI is generated from it, so there is no settings UI to write.

## Two failure modes that kill a plugin silently

Both produce a single line in `qs log` and an otherwise working shell. Both are
caught by `scripts/check-qml.sh`. Neither is obvious from reading your own code.

### 1. A `qs.*` module only a plugin imports is not registered

```
module "qs.modules.common.panels.lock" is not installed
```

A `qs.foo` module exists once the engine has **compiled** an `import qs.foo`.
Everything reachable by static imports from `shell.qml` is compiled before
anything runs. Plugins are found on disk at runtime and loaded from a URL, so
their imports are compiled far too late to register anything.

**If you import a `qs.*` module that no core file already imports, add it to
`core/PluginModuleAnchors.qml`.** Duplicates are harmless no-ops; the list has to
be complete, not minimal. Already anchored:

```
qs.core  qs.services  qs.modules.common  qs.modules.common.widgets
qs.modules.common.functions  qs.modules.common.utils  qs.modules.common.models
qs.modules.common.models.gCloud  qs.modules.common.panels.lock
qs.modules.common.widgets.widgetCanvas  qs.modules.ii.bar
qs.modules.ii.sidebarRight.volumeMixer
```

### 2. A type named after a singleton

```
qmldir defines type as singleton, but no pragma Singleton found in type Notes
```

Two types with one name, one a singleton, resolve to whichever the engine bound
first. The loser fails, and which one loses depends on load order — so it works
until it doesn't. `services/` alone has 80 singletons (`Battery`, `Audio`,
`Notes`, `Wallpapers`, …).

**Do not name a QML file after a singleton.** `plugins/overlay`'s notes widget is
`NotesWidget.qml`, not `Notes.qml`, for exactly this reason.

## Theming: use `Theme`, not `Appearance`

`import qs.core` gives you `Theme`. Every member is a live binding onto the
Material You palette generated from the wallpaper, so a widget using it recolours
with the wallpaper and works in light and dark with no branching.

```qml
Rectangle {
    color: Theme.raised
    radius: Theme.radius.m
    StyledText { color: Theme.text; font.pixelSize: Theme.font.m }
}
```

### Surfaces are stacked and translucent

This is the one thing to get right. The shell composites layers; each is computed
to look correct **painted on the one below**, with an alpha that follows the
user's transparency setting. `Theme.raised` over the wrong base, or over the
wallpaper, comes out at 10% alpha and nearly invisible.

| Use | For |
| --- | --- |
| `Theme.panel` | a window the shell owns — bar, sidebar, popup |
| `Theme.raised` | a card or row **inside a panel** ← the usual one |
| `Theme.high` | a block inside a block |
| `Theme.top` | innermost step: selected, focused |
| `Theme.solid` | **opaque.** Desktop widgets, anything over the wallpaper |

Text pairs with them: `Theme.text` (body), `Theme.textDim` (captions, units),
`Theme.textFaint` (hints, placeholders), `Theme.textOnPanel` (directly on
`Theme.panel`).

### The rest

```qml
Theme.accent        Theme.onAccent          // wallpaper colour + only readable text on it
Theme.accentBlock   Theme.onAccentBlock     // filled accent card
Theme.accentMuted   Theme.onAccentMuted     // chips, toggles that shouldn't shout
Theme.error         Theme.errorBlock  Theme.onErrorBlock
Theme.notice        Theme.noticeBlock Theme.onNoticeBlock   // Material has no warning role
Theme.outline       Theme.outlineDim        // hairlines. Already low contrast
Theme.dark                                  // bool

Theme.font.xs/s/m/l/xl   .family  .mono     // m is body text
Theme.pad.xs/s/m/l/xl                       // m is the default gap
Theme.radius.xs/s/m/l/full                  // m is a card, full is a pill
Theme.state.hover/focus/press/drag/disabled // opacities, not colours

Theme.anim.fast     // colours, hovers, small flips
Theme.anim.normal   // position and size
Theme.anim.enter / .exit / .bounce

Theme.fade(c, 0.5)        // same colour, more transparent
Theme.mix(a, b, 0.3)
Theme.on(anyBackground)   // readable text on an arbitrary colour
Theme.harmonize(c)        // pull a brand colour towards the wallpaper palette
Theme.role("colTertiaryHover")   // escape hatch to Appearance by name
```

Animate with the shell's curves or the widget will move but not *feel* right:

```qml
Behavior on color { animation: Theme.anim.fast.colorAnimation.createObject(this) }
Behavior on width { animation: Theme.anim.normal.numberAnimation.createObject(this) }
```

## Base types

Use these. They exist because each one is a pile of detail that is invisible when
wrong.

### `PluginBarWidget`

```qml
PluginBarWidget {
    id: root
    pluginId: "battery"        // gives you `settings`
    tooltip: qsTr("...")       // or set `popup:` for a panel
    onClicked: doThing()

    StyledText { text: "hi"; color: root.colText }
}
```

Free: `colText` / `colTextDim` / `colAccent` correct for every `bar.cornerStyle`
and both modes; `settings`; `vertical` and `mirrored` (lay out along `vertical`);
`clicked` / `rightClicked` / `middleClicked` / `scrolled(up)`; `hovered`;
tooltip honouring the user's click-to-show setting; lazy popup loading.

Content must **size itself** — a `StyledText`, a `RowLayout`, a `Rectangle` with
`implicitWidth`. Do not anchor it to fill the widget.

### `PluginPopup`

Set as a bar widget's `popup:`; `hoverTarget` is wired for you.

```qml
popup: Component {
    PluginPopup {
        title: qsTr("Battery");  subtitle: BatteryState.summary()
        icon: "battery_android_full"

        PluginRow { label: qsTr("Health"); value: "91%" }
        PluginSeparator {}
        PluginRow { label: qsTr("Draw"); value: "12.4 W"; shown: rateKnown }
    }
}
```

### `PluginRow`, `PluginCard`, `PluginSeparator`

`PluginRow` — label left, value right, correct emphasis, value stays flush. Use
`shown:` (not `visible:`) so an unavailable value takes no space.

`PluginCard` — a correct surface with padding and optional `interactive:` +
`onClicked`.

`PluginSeparator` — a hairline at the right opacity.

### `PluginBackgroundWidget`

A desktop widget. Position and visibility persist in `plugins.json` for you.

```qml
PluginBackgroundWidget {
    pluginId: "battery"
    widgetId: "batteryDesktop"      // must match the manifest entry's id
    implicitWidth: 140; implicitHeight: 140
    // Draw your own opaque backing: Theme.solid
}
```

## What a plugin can provide

Every kind is an array under `provides`. Each entry needs an `id`; most need
`entry` (a QML file, resolved relative to the plugin folder).

| Kind | What it does | Extra fields |
| --- | --- | --- |
| `barWidgets` | a widget the user can place in the bar | `name`, `icon`, `pillColor` |
| `desktopWidgets` | a draggable desktop widget | `name`, `icon`, `enabledByDefault` |
| `panels` | a window the plugin owns and shows itself | — |
| `services` | a non-visual always-on object: timers, watchers, `IpcHandler` | — |
| `settingsPages` | a whole page in Settings, with a nav entry | `name`, `icon`, `order` |
| `settingsSections` | a section injected into an **existing** Settings page | `page`, `order` |
| `launcherActions` | a result in the launcher | `exec` |
| `shortcuts` | a keybind, bound as `quickshell:<id>` | `description`, plus `exec` **or** `ipc` |

`settingsSections` is how a plugin's settings sit next to the related built-in
ones *and disappear when the plugin is switched off*. Host pages render
`PluginSections { page: "Interface" }`.

```json
"settingsSections": [
    { "id": "dock", "page": "Interface", "entry": "DockSettings.qml", "order": 20 }
]
```

`shortcuts` needs no QML:

```json
"shortcuts": [
    { "id": "batteryDetails", "description": "Show battery details",
      "ipc": { "target": "battery", "function": "toggle" } },
    { "id": "powerSave", "exec": ["powerprofilesctl", "set", "power-saver"] }
]
```

Bind it in the compositor as `bind = SUPER, B, global, quickshell:batteryDetails`.

Also available: `"requires": { "compositor": ["hyprland"] }` — the plugin is
skipped elsewhere, with the reason shown in the GUI. And
`"runtimeDeps": ["kde-material-you"]` — nixpkgs attribute names appended to the
shell's PATH.

## Settings

An ordered array in the manifest; the GUI is generated from it.

```json
{ "key": "format", "type": "string", "default": "hh:mm", "label": "Time format",
  "description": "One line. It sits under the control.",
  "icon": "schedule", "placeholder": "hh:mm", "group": "Appearance" }
```

| `type` | Control | Extra |
| --- | --- | --- |
| `bool` | switch | |
| `int` | spin box | `min`, `max`, `step` |
| `real` | slider | `min`, `max` (shown as % when `max <= 1`) |
| `string` | text field + confirm | `placeholder` |
| `enum` | dropdown | `options: [{ "value": "l", "label": "Left" }]` |

`group` puts rows under a subheading; ungrouped rows come first. Keep
`description` to one line — three-line descriptions make the list ragged.

Read them with `root.settings.foo` on a base type, or `PluginConfig.of("id").foo`
anywhere. Live bindings; no reload.

Write from QML only when the plugin owns the value (the GUI already writes):

```qml
PluginConfig.set("battery", "label", "time")
PluginConfig.resetAll("battery")
```

**`plugins.json` is read asynchronously.** Binding to a value is fine. But if you
*act* on a stored value, wait for `PluginConfig.loaded`, or you will act on the
defaults once at every startup:

```qml
Timer {
    interval: 600; running: true
    onTriggered: {
        if (!PluginConfig.loaded) { restart(); return }
        // stored values are real now
    }
}
```

Undeclared keys are preserved, which is how a plugin stores its own state next to
its settings (see `plugins/material-you-colors`'s `appliedSnapshot`).

## Several files, subfolders, singletons

Files beside each other resolve implicitly — no import needed. For a subfolder,
`import "subfolder"`; from inside it, `import ".."`.

For a plugin-local singleton, add a `qmldir`:

```
singleton BatteryState 1.0 BatteryState.qml
```

Siblings then use `BatteryState` with no import. Good for state several files
share. (Check the name against `services/` first — see failure mode 2.)

## Verify

```bash
scripts/check-qml.sh              # whole tree + entry points + name clashes
scripts/check-qml.sh plugins      # one subtree (skips the entry-point phase)
```

Expect `failures=0` twice and exit 0. Three phases, and you need to know why:

1. **Every file compiled individually.** Catches syntax and missing types. *Can
   give false negatives*: compiling an internal file the shell never loads that
   way primes the engine's type cache and can hide a real clash.
2. **Plugin entry points, with only the imports `shell.qml` really has.** This is
   the phase that catches a missing module anchor.
3. **Type names that also name a singleton.** Deterministic. This is the phase
   that catches failure mode 2.

Compiling is not running. To catch binding errors, instantiate:

```qml
// probe.qml at the tree root; run: qs -p probe.qml
import QtQuick
import Quickshell
import qs.core
Scope {
    PluginModuleAnchors {}
    Component.onCompleted: {
        const c = Qt.createComponent(`file://${Quickshell.shellDir}/plugins/x/X.qml`,
                                     Component.PreferSynchronous);
        console.log(c.status === Component.Error ? c.errorString() : "ok");
        const o = c.createObject(null, { width: 600 });
        console.log(o ? `h=${o.implicitHeight}` : "null");
        console.log("PROBE|DONE");
    }
}
```

Then `qs log -t 200 | grep -iE "warn|error"`. Quickshell has no QML-side exit;
kill the process yourself. Delete the probe when done.

Runtime state of the real shell:

```bash
hyprctl globalshortcuts | grep quickshell     # are the keybinds registered
qs -c end4-pC log -t 400 | grep -iE "warn|error"
jq . ~/.config/illogical-impulse/plugins.json
```

## Editing core safely

Invariants, each of which took a bug to learn:

- **Core must not reference `plugins/`.** Extension points are `PluginRegistry`
  lists. Two grandfathered exceptions exist in the other direction
  (`plugins/lock` → `qs.modules.ii.bar`, `plugins/overlay` →
  `qs.modules.ii.sidebarRight.volumeMixer`); do not add a third.
- **Plugins must not import other plugins.**
- **A new `qs.*` import in plugin code goes in `PluginModuleAnchors.qml`.**
- **Never name a file after a singleton.**
- **`PluginRegistry.plugins` is reassigned, never mutated**, so bindings update.
  Registration is coalesced through a timer so it publishes once per scan, not
  once per manifest — twenty reassignments meant twenty rebuilds of everything
  derived from it.
- **Never use an active-derived registry list as an `Instantiator`/`Repeater`
  model.** A model that is a plain JS array is rebuilt wholesale when the array is
  reassigned, and `panels` / `services` / `desktopWidgets` are reassigned whenever
  *any* plugin is toggled — so one toggle destroyed and recreated every plugin's
  windows. Use `installedPanels` / `installedServices` /
  `installedDesktopWidgets` / `installedShortcuts` (they change only when a plugin
  appears or disappears on disk) and put the enabled state on the delegate:
  `activeAsync: PluginRegistry.isLoaded(modelData.pluginId)`. Read state with
  `isActive()`; instantiate from `isLoaded()`, which lags a turn so the UI paints
  the click before a heavy plugin blocks the thread loading.
- **`LazyLoader.active: true` blocks the UI thread** until the component is fully
  loaded — Quickshell documents this. Use `activeAsync` for anything that is not
  needed this frame. (`Variants` has no async support, so a panel using it still
  blocks while it loads.)
- **Never enumerate built-ins in a host.** Bar widgets, desktop widgets and quick
  toggles are rows in `BarWidgetRegistry`, `DesktopWidgetRegistry` and
  `QuickToggleRegistry`. Adding one in a second place is how those lists drifted.
- **`Config.options.*` is a `JsonAdapter`** and drops keys it does not declare —
  which is why plugin settings live in `plugins.json` instead.
- **A `MouseArea` in a layout is wrong.** It is an `Item`, so the layout gives it
  a cell while it tries to `anchors.fill`. Use `TapHandler` + `HoverHandler`.
- **A `Repeater` delegate is not parented when its bindings first run**, so
  `parent.height` throws. Reference the container by `id`.
- **`??` binds looser than `&&`.** `a ?? false && b` parses as `a ?? (false && b)`.
- Bump `PluginRegistry.apiVersion` for a breaking manifest or injected-property
  change. Additive fields need no bump.

If a settings section belongs to a plugin, it goes in the plugin as a
`settingsSections` entry — not hardcoded in a core page. A hardcoded section for
a disabled plugin is a row of controls wired to nothing.

## What the plugin system cannot do

Be honest about these instead of half-building them.

- **Quick toggles** (sidebar) are not extensible. They are a `DelegateChooser`
  keyed on a string with separate Android/classic delegates per toggle and
  drag-to-reorder state. Adding a plugin toggle needs a real refactor of
  `modules/ii/sidebarRight/quickToggles/`.
- **Launcher search providers** — a plugin can add a static `launcherActions`
  entry, but cannot answer a query dynamically.
- **No sandboxing.** A plugin is QML in the shell's process with the shell's
  privileges. It can read any file, spawn any process, and break the shell. There
  is no permission model; `runtimeDeps` is convenience, not confinement.
- **No inter-plugin API.** Plugins cannot import each other. Talk over
  `IpcHandler`, or put the shared part in `modules/common/` and anchor it.
- **No hot reload.** Editing a plugin needs `qs kill && qs`, or `qr` in devMode.
- **Bar layout regions, notification actions, OSD content and the desktop
  right-click menu** are not extension points yet.
- **A plugin cannot add keys to `config.json`.** Use `plugins.json`, or write to
  an existing `Config.options` key.

## References

- [Full API reference](references/API.md) — every provides field, every `Theme`
  member, every base-type property
- `docs/PLUGINS.md` in the tree — the authoring guide
- `plugins/example-clock/` — bar widget + desktop widget + launcher action
- `plugins/battery/` — drawn graphics, a plugin singleton, a popup, both widget
  kinds
- `plugins/material-you-colors/` — a service, `IpcHandler`, acting on stored
  state, 20 grouped settings
