# Plugin API reference

Companion to [SKILL.md](../SKILL.md). That file is the workflow and the rules;
this one is the exhaustive list, so nothing needs to be looked up in the tree.

Everything here is reached with `import qs.core`.

---

## manifest.json

### Top level

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `id` | string | **yes** | Must equal the folder name |
| `name` | string | | Shown in the GUI. Defaults to `id` |
| `version` | string | | Free-form, shown in the plugin's detail view |
| `apiVersion` | int | | Defaults to 1. Refused if above the shell's `PluginRegistry.apiVersion` |
| `description` | string | | One line, shown in the plugin list |
| `author` | string | | |
| `icon` | string | | Material Symbols name. Defaults to `extension` |
| `enabledByDefault` | bool | | Defaults to **true**. Set false for something experimental |
| `provides` | object | | See below |
| `settings` | array | | See below |
| `requires` | object | | `{ "compositor": ["hyprland"] }` |
| `runtimeDeps` | array | | nixpkgs attribute names, appended to the shell's PATH |

Unknown top-level fields are ignored, so a manifest written for a later version
still loads.

### provides

Every value is an array. Every entry gets `pluginId`, `pluginName` and (when it
has an `entry`) an absolute `url` added by the registry.

#### barWidgets

| Field | Notes |
| --- | --- |
| `id` | Referenced in the user's bar layout. Also overrides a built-in widget of the same id |
| `entry` | QML file. Root should be `PluginBarWidget` |
| `name`, `icon` | Shown in the bar layout editor |
| `pillColor` | An `Appearance.colors` role name, e.g. `secondaryContainer` |

#### desktopWidgets

| Field | Notes |
| --- | --- |
| `id` | Must match the `widgetId` your `PluginBackgroundWidget` sets |
| `entry` | Root should be `PluginBackgroundWidget` |
| `name`, `icon` | Shown in the desktop widget picker |
| `enabledByDefault` | Per-widget, independent of the plugin's own default |

#### panels

`{ "id", "entry" }`. Instantiated at shell scope in a `LazyLoader` once
`Config.ready`. The plugin owns the window and its visibility — typically a
`PanelWindow` or `WlSessionLock`, plus a `CompositorGlobalShortcut` and an
`IpcHandler` to open it.

#### services

`{ "id", "entry" }`. Same lifecycle as `panels`, for things with no window:
timers, file watchers, `IpcHandler`, `Process`. Use this for "do something when X
changes".

#### settingsPages

| Field | Notes |
| --- | --- |
| `id`, `entry` | Root should be `ContentPage` |
| `name`, `icon` | The nav rail entry |
| `order` | Sort key among plugin pages. Default 100 |

The page keeps its nav entry while the plugin is disabled, greyed out, so
toggling a plugin never reshuffles the list under the cursor. Implement
`function goTo(term)` to support the settings search.

#### settingsSections

| Field | Notes |
| --- | --- |
| `id`, `entry` | Root should be `ContentSection` |
| `page` | Host page name, matched case-insensitively |
| `order` | Sort key within the page. Default 100 |

Host pages currently rendering plugin sections: **Interface**. Add another with
`PluginSections { page: "Bar" }` in that page.

Unlike `settingsPages`, a section **disappears when the plugin is disabled** —
which is the point. Values may still live in `Config.options` if the plugin reads
them there; only the UI belongs to the plugin.

#### launcherActions

`{ "id", "exec": ["cmd", "arg"] }`. A static entry in the launcher. There is no
dynamic query API.

#### shortcuts

| Field | Notes |
| --- | --- |
| `id` | Bound as `quickshell:<id>` |
| `description` | Shown by `hyprctl globalshortcuts` |
| `exec` | Array. Runs detached |
| `ipc` | `{ "target": "...", "function": "..." }`. Calls your `IpcHandler` |

`exec` wins if both are given. Hyprland only (`CompositorGlobalShortcut` is a
no-op elsewhere). For anything conditional, declare a
`CompositorGlobalShortcut` in your own QML instead.

### settings

| Field | Applies to | Notes |
| --- | --- | --- |
| `key` | all | The name you read back |
| `type` | all | `bool` `int` `real` `string` `enum` |
| `default` | all | Falls back to `false` / `min` / first option / `""` |
| `label` | all | The row's text |
| `description` | all | Under the control. **One line** |
| `icon` | all | Material Symbols name |
| `group` | all | Subheading. Ungrouped rows come first |
| `min`, `max`, `step` | int, real | `real` renders as a percentage when `max <= 1` |
| `placeholder` | string | |
| `options` | enum | `[{ "value": "l", "label": "Left" }]` |

Values are coerced against the schema on read, so a hand-edited `plugins.json`
cannot feed a string where a number is declared.

---

## Theme

`import qs.core`. All live bindings on the wallpaper-derived Material You palette.

### Surfaces

Stacked and translucent — see SKILL.md. `panel` → `raised` → `high` → `top`, plus
opaque `solid` / `solidHigh` for over-wallpaper use. `surface` and `surfaceHigh`
are aliases of `raised` and `high`.

### Text

| Member | For |
| --- | --- |
| `text` | body text on `raised` / `high` / `top` / `solid` |
| `textDim` | captions, units, secondary values |
| `textFaint` | hints, placeholders, disabled |
| `textOnPanel` | text directly on `panel` |

### Accents and semantics

| Member | Pairs with |
| --- | --- |
| `accent` | `onAccent` |
| `accentBlock` | `onAccentBlock` |
| `accentMuted` | `onAccentMuted` |
| `error` | — |
| `errorBlock` | `onErrorBlock` |
| `notice` | `onNoticeBlock` (stands in for "warning"/"success") |
| `noticeBlock` | `onNoticeBlock` |

`outline`, `outlineDim`, `scrim`, `shadow`, and `dark` (bool).

### Scale

`font.xs|s|m|l|xl`, `font.family`, `font.mono` · `pad.xs|s|m|l|xl` ·
`radius.xs|s|m|l|full` · `state.hover|focus|press|drag|disabled` (opacities).

### Motion

`anim.fast` `anim.normal` `anim.enter` `anim.exit` `anim.bounce`. Each has
`.numberAnimation` and `.colorAnimation` Components:

```qml
Behavior on opacity { animation: Theme.anim.enter.numberAnimation.createObject(this) }
```

### Functions

| Call | Returns |
| --- | --- |
| `fade(c, amount)` | `c` more transparent; 1 is invisible |
| `mix(a, b, amount)` | blend, `amount` is how much of `b` |
| `on(background)` | a readable text colour for any background, correct in both modes |
| `harmonize(c)` | `c` pulled towards the wallpaper palette |
| `role(name)` | any `Appearance` role by name; `transparent` if unknown |

---

## Base types

### PluginBarWidget

| Property | Direction | Notes |
| --- | --- | --- |
| `pluginId` | set | Enables `settings` |
| `settings` | read | This plugin's settings, defaults filled in |
| `vertical`, `mirrored` | read | Set by the bar |
| `colText`, `colTextDim`, `colAccent` | read | Correct for the pill style and mode |
| `isMaterial` | read | `bar.cornerStyle === 3` |
| `padding` | set | Along the bar's long axis |
| `tooltip` | set | One line. Ignored when `popup` is set |
| `popup` | set | A `Component`; `hoverTarget` is wired for you |
| `interactive` | set | False for decoration; stops eating clicks |
| `hovered`, `containsPress` | read | |
| `clicked`, `rightClicked`, `middleClicked` | signal | |
| `scrolled(int up)` | signal | `up` is +1 |

The internal `MouseArea` is declared **before** the content slot, so a widget with
its own `MouseArea` keeps priority.

### PluginPopup

Root of a bar widget's `popup`. `title`, `subtitle`, `icon`, `iconBlock`,
`iconColor`, `maximumWidth` (default 320). Children go in a column under the
header; omit all three header fields for a bare panel.

### PluginRow

`label` (required), `value`, `icon`, `shown`, `valueColor`. Use `shown` rather
than `visible` so a hidden row takes no space.

### PluginCard

`surface` (default `Theme.high`), `padding`, `columns`, `spacing`,
`interactive`, `hovered`, `clicked`. Children go into a `GridLayout`.

### PluginSeparator

`shown`. A hairline at the correct opacity.

### PluginBackgroundWidget

`pluginId` and `widgetId` required; `widgetId` must match the manifest entry.
Position and visibility persist in `plugins.json`. Provides `settings`,
`colText`, `screenWidth` / `screenHeight`, `visibleWhenLocked`. Draw your own
opaque backing with `Theme.solid`.

### PluginSections

`page` (required). Renders plugin-contributed sections for that host page.

### PluginShortcut

Internal; `PluginHost` creates one per manifest `shortcuts` entry.

---

## PluginConfig

| Call | Notes |
| --- | --- |
| `of(pluginId)` | Settings object with manifest defaults filled in |
| `value(pluginId, key)` | One value |
| `set(pluginId, key, v)` | Debounced write |
| `reset(pluginId, key)` | Back to the manifest default |
| `resetAll(pluginId)` | |
| `setEnabled(pluginId, b)` | |
| `loaded` | **False until `plugins.json` has been read** |
| `data` | The raw parsed file |
| `widgetValue` / `setWidgetValue` / `widgetEnabled` / `setWidgetEnabled` | Per-desktop-widget state |

Undeclared keys are preserved — that is how a plugin stores its own state beside
its settings.

---

## PluginRegistry

| Member | Notes |
| --- | --- |
| `all` | Every installed plugin, by name |
| `active` / `activeIds` | Enabled **and** supported here |
| `errors` | `[{ id, message }]`, shown in the GUI |
| `ready` | Discovery finished |
| `panels`, `services`, `barWidgets`, `desktopWidgets`, `launcherActions`, `shortcuts`, `settingsPages`, `settingsSections` | Flattened across **active** plugins |
| `installedPanels`, `installedServices`, `installedDesktopWidgets`, `installedShortcuts` | The same, over **installed** plugins. Use these as `Instantiator`/`Repeater` models |
| `installedSettingsPages` | Including disabled, so the nav list is stable |
| `sectionsFor(page)` | Sections for one host page, sorted |
| `get(id)` | Descriptor or null |
| `find(kind, id)`, `barWidget(id)`, `desktopWidget(id)` | |
| `isEnabled` / `isActive` / `setEnabled` | |
| `isSupported(plugin)` / `unsupportedReason(plugin)` | `requires.compositor` |
| `apiVersion` / `minApiVersion` | |
| `pluginsDir` / `resolve(id, path)` | |

---

## Performance traps

Both of these caused a one-to-two-minute freeze on toggling a plugin, and neither
is visible from reading the code that suffers from it.

### A JS-array model is rebuilt wholesale when reassigned

`Instantiator` and `Repeater` cannot diff two plain JS arrays, so a reassigned
model destroys and recreates **every** delegate. The active lists (`panels`,
`services`, `desktopWidgets`, `settingsSections`) are reassigned whenever any
plugin is toggled.

```qml
// wrong: toggling any plugin rebuilds every plugin's panels
Instantiator {
    model: PluginRegistry.panels
    delegate: LazyLoader { active: true; source: modelData.url }
}

// right: the model changes only when a plugin is installed or removed
Instantiator {
    model: PluginRegistry.installedPanels
    delegate: LazyLoader {
        source: modelData.url
        activeAsync: PluginRegistry.isActive(modelData.pluginId)
    }
}
```

### `LazyLoader.active` blocks

Quickshell's docs: setting `active: true` "will force the component to load to
completion, blocking the UI". `activeAsync` loads in the gaps between frames and
behaves identically when set to false.

Use `active` only when the component is needed this frame - a popup opening under
the cursor, say. `Variants` has no async support, so a component using it
internally blocks while it loads regardless.

### Loading is deferred one turn past `activeIds`

`PluginRegistry.activeIds` updates synchronously when a plugin is toggled, so
anything that merely *reads* which plugins are on is immediate. `loadedIds`
follows 80 ms later, and that is what the loaders key off.

Without it, clicking the switch in the GUI started the plugin loading in the same
event-loop turn, so the frame showing the switch in its new position was never
painted - the switch appeared to stick for as long as the load took, then snap.
A plugin panel is a window containing `Variants`, which Quickshell cannot load
asynchronously, so the load itself is unavoidably seconds of blocked UI thread.
Yielding first does not make it faster; it makes the click acknowledged.

Use `isActive()` to read state, `isLoaded()` to instantiate.

### Registration is coalesced

`register()` writes into a pending map and a 30 ms timer publishes
`PluginRegistry.plugins` once. Assigning per manifest meant twenty reassignments
per scan, each invalidating `all`, `active` and all eight provides lists.

---

## Useful shell singletons

`import qs.services` (already anchored).

`Battery` · `Audio` · `Network` · `Bluetooth` · `DateTime` · `Weather` ·
`MprisController` · `Translation` (`Translation.tr(...)`) · `WM`
(`WM.compositor`) · `Notes` · `Wallpapers` · `SystemInfo` · `Updates` ·
`HyprlandData` · `CompositorGlobalShortcut` (a type, not a singleton).

`import qs` gives `GlobalStates` (`screenLocked`, `sidebarLeftOpen`, …).

`import qs.modules.common` gives `Appearance`, `Config`, `Directories`,
`Persistent`.

`import qs.modules.common.widgets` gives the widget library: `StyledText`,
`MaterialSymbol`, `MaterialShapeWrappedMaterialSymbol`, `RippleButton`,
`RippleButtonWithIcon`, `StyledPopup`, `StyledToolTip`, `StyledSwitch`,
`ConfigSwitch`, `ConfigSpinBox`, `ConfigSlider`, `ConfigComboBox`,
`ContentPage`, `ContentSection`, `ContentSubsection`, `GroupedList`,
`CircularProgress`, `StateLayer`, `NoticeBox`, `PagePlaceholder`,
`MaterialShape`, `IconToolbarButton`, `ToolbarTextField`, and more.

Note `PagePlaceholder` anchors-fills its parent and uses `shown`, not `visible` —
it is an overlay, not a layout child.

---

## Nix

In-tree plugins install automatically. Out-of-tree:

```nix
programs.end4.plugins.my-plugin = ./path/to/my-plugin;
```

A name matching an in-tree plugin replaces it. The build validates every manifest
(JSON, `id` vs folder, `apiVersion`, `entry` files exist), so a broken plugin
fails `nixos-rebuild` rather than at runtime.

```bash
nix eval .#nixosConfigurations.nixos.config.home-manager.users.bhavya.programs.end4.installedPlugins
```

`runtimeDeps` resolve against `pkgs`; unknown names warn and are skipped. Use
`programs.end4.extraRuntimeDeps` for anything not a plain nixpkgs attribute, or
for a devMode checkout (not scanned).

---

## Probing at runtime

`qs -p some-probe.qml` runs a throwaway config against the real tree, which is the
only way to check that something actually loads rather than merely compiles.

Keep any window in a probe **invisible**. `PanelWindow { visible: true }` is a real
layer-shell surface and will paint over the user's desktop for as long as the probe
runs. Sizes and bindings still evaluate with `visible: false`.

```qml
// probe.qml - report and exit, paint nothing
import QtQuick
import Quickshell
import qs.core

Scope {
    PluginModuleAnchors {}
    // Singletons are lazy: touch it now or discovery has not started when you look.
    Component.onCompleted: PluginRegistry.discovered

    Timer {
        interval: 2500
        running: true
        onTriggered: {
            console.log(`PROBE|plugins=${PluginRegistry.all.length}`);
            Qt.exit(0);
        }
    }
}
```

Anything that writes user state (`PluginRegistry.setEnabled`, `Config.options.*`)
writes to the real config. Back it up and restore it, or do not call it.

---

## Built-in registries

Built-ins are rows in the same tables plugin contributions land in. A host reads one
list and cannot tell the difference.

| Singleton | Holds |
| --- | --- |
| `BarWidgetRegistry` | `all`, `placeable()`, `find`, `url`, `name`, `repeatable`, `wantsPill`, `pillColor` |
| `DesktopWidgetRegistry` | `all`, `find`, `available`, `installed`, `enabled`, `setEnabled`, `toggle` |
| `QuickToggleRegistry` | `all`, `availableFor(style)`, `availableIds(style)`, `find`, `androidUrl`, `classicUrl`, `menuFor` |

`available()` uses `isLoaded` (gating instantiation); `installed()` uses `isActive`
(gating a GUI switch, which should track the click immediately).

`all` on every registry is the **installed** set, not the enabled one, and it is
identity-stable. Filter it for enabled-ness at the point of use (`placeable()`,
`availableFor()`) rather than deriving a new list — see the performance rules below.

---

## Performance rules

These are not micro-optimisations; each one is a bug that has already happened here,
and each is invisible until the shell is doing something else at the same time.

### A derived list must be identity-stable

QML decides whether to rebuild a Repeater, an Instantiator's delegates, or re-run a
binding by comparing the **identity** of a JS array, never its contents. So a derived
list recomputed from an unrelated dependency hands every consumer a brand new array
that happens to be equal to the old one — and they all rebuild.

That is why enabling a *bar* plugin used to rebuild all seventeen quick toggles.
Wrap derived lists in `Stable`:

```qml
readonly property var all: Stable.list("myRegistry.all", (() => {
    ...compute...
})())
```

`Stable.list(key, value)` returns the *previous* array when the new one serialises
identically, so consumers never see a change that was not one. `Stable.ids()` is the
cheaper version for arrays of plain strings, and `Stable.index(key, list)` gives an
`id -> entry` map so a per-id lookup is not a scan.

### Instantiate from `installed*`, read from `active`

`PluginRegistry.installedPanels` and friends change only when a plugin appears or
disappears **on disk**. Use them as `Instantiator`/`Repeater` models and put the
enabled state on the delegate's `active`, which costs a boolean. A model derived from
the active set is reassigned on every toggle, which destroys and recreates every other
plugin's objects.

Use `isActive()` to *read* whether a plugin is on, and `isLoaded()` to decide whether
to *instantiate* it. `loadedIds` follows `activeIds` one frame later, so the frame that
acknowledges the user's click gets painted before any loading starts.

### `settings` has real properties — bind to the key, not the object

`PluginConfig.of(id)` returns a long-lived object with one typed QML property per
declared setting. Its identity does not change when a value changes, and assigning a
typed property that already holds that value notifies nobody. So:

```qml
readonly property var settings: PluginConfig.of("myPlugin")
text: root.settings.format          // re-evaluates only when `format` changes
```

Do not copy the bag into a new object, and do not build a settings map yourself: that
reintroduces exactly the whole-config cascade this replaced, where one write re-ran
every plugin's every binding.

### Anything loaded by URL should be pre-compiled

Setting `Loader.source` compiles the file and then instantiates it. The compile is the
expensive half and it lands on the UI thread. `ComponentCache` compiles in the
background, and because the engine caches compiled units per URL, a later
`source: url` only pays instantiation.

Everything reachable from a manifest or a built-in registry is warmed automatically by
`core/Prewarm.qml`. If you add a new kind of thing loaded by URL, add it there.

```qml
ComponentCache.warm(url)        // queue it, compiled between frames
ComponentCache.warmNow(url)     // jump the queue: the user is about to need it
ComponentCache.isWarm(url)      // already compiled?
ComponentCache.get(url)         // the Component, or null
```

Do not bind a long-lived `Loader.component` to `ComponentCache.get(url)`: it returns
null until warm, and the change from null to a Component would reload an item that was
already showing. Use `source: url` and let the cache work underneath.

### Do not bind to `.length` of an array you mutate in place

`push`/`shift`/`splice` on the array held by a `var` property emit nothing, so a
binding like `readonly property bool idle: queue.length === 0` is evaluated once and
then never again. `ComponentCache` shipped with exactly this bug and silently compiled
nothing. Either reassign the array or use a function instead of a binding.

### Measured cost of the above

With the real bar, quick panel and 13 desktop widgets instantiated, toggling each of
18 plugins off and on: **worst main-thread stall 38 ms, mean 13.8 ms, zero stalls over
40 ms**. Click-to-loaded is one frame (16–19 ms). A settings write costs 0.08 ms, and
20 000 settings reads through `of()` cost 4 ms in total.

The harnesses that produce those numbers are `bench*.qml` patterns described under
"Probing at runtime" — an 8 ms heartbeat timer whose gaps are, by definition, the UI
thread being blocked.

## Two rules for anything loaded by URL

Both of these produce a component that compiles but will not load, and neither shows
up in phase 1.

**No `required` properties.** A component with an uninitialised required property
cannot be constructed, so a `Loader` reports `Loader.Error` and you get nothing. Give
the property a default and let the host bind over it. `required` is fine for a type
always instantiated by hand, and fatal for one resolved from an id.

**Read context from the parent, do not make the host push it.** Both
`AbstractBackgroundWidget` and `PluginBackgroundWidget` take their screen geometry
from the canvas they sit on. That is why a desktop widget entry is just a URL.

## Do not gate a Loader on its own source

```qml
// wrong: `active` reads `source`, so the Loader never reads `source` itself,
// the binding never evaluates, and nothing ever loads. Qt reports a binding loop.
Loader {
    source: SomeRegistry.url(id)
    active: source != ""
}

// right: an empty source loads nothing on its own
Loader {
    source: SomeRegistry.url(id)
    visible: status === Loader.Ready
}
```

## Annotate function return types

```qml
function find(id: string): var { ... }   // right
function find(id: string) { ... }        // logs "insufficiently annotated" per call
```

---

## Commands and keybinds

### `PluginIpc` — a plugin's own command line

`provides.ipc` entries are files whose root is a `PluginIpc`. Every annotated function on
it becomes a command.

```qml
import qs.core

PluginIpc {
    target: "gifs"                  // defaults to the plugin id

    function open(): void { GifPicker.open(); }
    function search(query: string): void { GifPicker.search(query); }
}
```

```
qs -c end4-pC ipc call gifs open
qs -c end4-pC ipc call gifs search "cat"
```

**Annotate parameter and return types, `void` included.** Quickshell needs them to
marshal a call from the command line; an unannotated function is not exposed at all, with
no error to tell you so.

`target` defaults to the plugin id so two plugins cannot collide by accident.

### Keybinds

`provides.shortcuts` registers `quickshell:<id>`, which the compositor dispatches
straight to the running shell — no process spawn, unlike binding `qs ipc call`. Give the
entry `exec` (argv) or `ipc` (`{ target, function }`) and no QML is needed.

Nothing edits your compositor config. To find out what to write:

```
qs -c end4-pC ipc call plugins shortcuts   # declared keybinds + the exact bind line
qs -c end4-pC ipc call plugins commands    # IPC targets plugins own
qs -c end4-pC ipc call plugins list        # installed plugins, on/off, what they provide
```

`plugins/battery` is the worked example.

## Never unload something expensive to make it disappear

`PluginSections` used `active: isLoaded(pluginId)` so a switched-off plugin's settings
section vanished. Measured in the real settings window, that cost **390 ms of blocked UI
thread per toggle, 48% of a five-second window**, while a plugin with no settings section
cost 13 ms — which is exactly why some plugins felt laggy to toggle and others did not,
for reasons that had nothing to do with the plugins.

A settings section is a few dozen controls. Build it once, then only change `visible`.
Qt Quick Layouts exclude invisible items, so a hidden section collapses exactly as if it
had been unloaded, and `asynchronous: true` is not a substitute — the incubator still
does its work on this thread.

The general rule: unloading is for things that cost something to *keep*, not for things
that cost something to *build*.
