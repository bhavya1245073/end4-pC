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
| `panels`, `services`, `barWidgets`, `desktopWidgets`, `launcherActions`, `shortcuts`, `settingsPages`, `settingsSections` | Flattened across active plugins |
| `installedSettingsPages` | Including disabled, so the nav list is stable |
| `sectionsFor(page)` | Sections for one host page, sorted |
| `get(id)` | Descriptor or null |
| `find(kind, id)`, `barWidget(id)`, `desktopWidget(id)` | |
| `isEnabled` / `isActive` / `setEnabled` | |
| `isSupported(plugin)` / `unsupportedReason(plugin)` | `requires.compositor` |
| `apiVersion` / `minApiVersion` | |
| `pluginsDir` / `resolve(id, path)` | |

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
