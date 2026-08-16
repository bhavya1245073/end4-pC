# Writing a plugin

A plugin is **one folder** under `plugins/` with a `manifest.json` in it. Drop the
folder in, restart the shell (or `qs kill && qs`), and it shows up under
**Settings → Plugins**. There is nothing to register, no core file to edit, and no
import to add anywhere.

```
plugins/
  my-plugin/
    manifest.json      <- the only required file
    BarClock.qml       <- whatever QML the manifest points at
    scripts/hello.sh
```

Folders starting with `.` or `_` are ignored, which is handy for
work-in-progress.

> **Working on this with an AI agent?** `.agents/skills/quickshell-plugins/` in
> this repo is a skill file covering the whole API, the two failure modes that
> silently kill a plugin, and the invariants for editing core. It is discovered
> automatically by agents run from this tree; point others at it directly.

## Quickstart

```sh
scripts/new-plugin.sh my-plugin        # scaffolds plugins/my-plugin/
```

or copy `plugins/example-clock/`, which uses every feature described below, and
rename the `id` in its manifest to match the new folder name.

Then: **Settings → Plugins → Enabled**.

## manifest.json

```json
{
    "id": "my-plugin",
    "name": "My Plugin",
    "version": "1.0.0",
    "apiVersion": 1,
    "description": "One line about what it does.",
    "author": "you",
    "icon": "extension",
    "enabledByDefault": false,
    "requires": { "compositor": ["hyprland"] },
    "runtimeDeps": ["jq"],
    "provides": { },
    "settings": [ ]
}
```

| Field | Required | Meaning |
| --- | --- | --- |
| `id` | yes | Must equal the folder name. Used as the key in `plugins.json`. |
| `name` | | Shown in the GUI. Defaults to `id`. |
| `version` | | Free-form, shown in the GUI. |
| `apiVersion` | | Plugin API the plugin was written against. Current: **1**. A plugin asking for a newer API than the shell provides is refused, with the reason shown in the GUI. |
| `description` | | One or two lines, shown under the name. |
| `author` | | Shown in the GUI. |
| `icon` | | [Material Symbol](https://fonts.google.com/icons) name. Defaults to `extension`. |
| `enabledByDefault` | | `true` to be on as soon as it's installed. Default `false`. |
| `requires.compositor` | | List of `"hyprland"` / `"niri"`. Elsewhere the plugin stays off and says why. |
| `runtimeDeps` | | Package names the plugin shells out to. The NixOS module puts them on the shell's `PATH`; see [Nix](#nix). |
| `provides` | | What the plugin contributes. See below. |
| `settings` | | Schema for the auto-generated settings GUI. See below. |

Every `entry` is a path relative to the plugin folder.

### provides

```json
"provides": {
    "panels":         [ { "id": "myPanel",  "entry": "MyPanel.qml" } ],
    "services":       [ { "id": "myWatch",  "entry": "MyService.qml" } ],
    "barWidgets":     [ { "id": "myClock",  "entry": "BarClock.qml",
                          "name": "My Clock", "icon": "schedule",
                          "pillColor": "secondaryContainer",
                          "materialPill": true, "multipleAllowed": false } ],
    "desktopWidgets": [ { "id": "myDeskClock", "entry": "DesktopClock.qml",
                          "name": "My Clock", "icon": "schedule",
                          "enabledByDefault": true } ],
    "settingsPages":  [ { "id": "myPage", "entry": "SettingsPage.qml",
                          "name": "My Plugin", "icon": "tune", "order": 50 } ],
    "settingsSections":[{ "id": "mySection", "entry": "MySettings.qml",
                          "page": "Interface", "order": 30 } ],
    "launcherActions":[ { "id": "hello", "exec": ["notify-send", "hi"] },
                        { "id": "backup", "script": "scripts/backup.sh" } ],
    "quickToggles":   [ { "id": "myToggle", "entry": "MyToggle.qml",
                          "menu": "", "requires": "" } ],
    "shortcuts":      [ { "id": "toggleMyPanel", "description": "Toggle my panel",
                          "suggestedKey": "SUPER, M",
                          "ipc": { "target": "myPanel", "function": "toggle" } } ]
}
```

| Kind | What it does |
| --- | --- |
| `panels` | A window. Loaded once at shell scope while the plugin is on. Root type: `PanelWindow` (or a `Scope` holding several). |
| `services` | A non-visual object: timers, file watchers, `Process`, `IpcHandler`. Loaded once at shell scope. Root type: `Scope` or any `QtObject`. |
| `barWidgets` | Selectable in **Settings → Bar** and placeable in any of the three bar sections. `pillColor` is one of `primary`, `secondary`, `tertiary`, `primaryContainer`, `secondaryContainer`, `tertiaryContainer`, `layer0`, `layer1`. `materialPill: false` opts out of the pill in the Material bar style. `multipleAllowed: true` lets the widget be added more than once. |
| `desktopWidgets` | Draggable widget on the wallpaper. Appears in the desktop right-click menu under **Widgets**, and in **Settings → Desktop**, alongside the built-in ones - there is no separate "from plugins" area, because built-ins and plugin widgets come from the same registry. Root type: `PluginBackgroundWidget`. |
| `settingsPages` | A whole page in the settings sidebar, for when the generated form isn't enough. `order` sorts them (default 100). Keeps its nav entry while the plugin is off, greyed out. |
| `settingsSections` | A section injected into an **existing** settings page, named by `page`. Unlike a page, it *disappears* when the plugin is switched off - which is why every stock panel's settings live in the plugin rather than in the core page. |
| `launcherActions` | `>`-prefixed launcher action. Either `exec` (argv array) or `script` (path inside the plugin). Anything typed after the action name is appended as arguments. |
| `quickToggles` | A tile in the sidebar's quick settings panel. Inherit `AndroidQuickToggleButton` and it works in both panel styles; supply `classicEntry` if you want a different file for the classic style. `menu` names a dialog its expand arrow opens (`wifi`, `bluetooth`, `nightLight`, `audioOutput`, `audioInput`); `requires` limits it to one compositor. Appears in the unused-toggle tray, draggable into the grid like any built-in. |
| `shortcuts` | A keybind, registered as `quickshell:<id>`. Give it `exec` (argv array) or `ipc` (`{ target, function }`) and the shell handles it with no QML from you. `suggestedKey` is documentation, shown in the plugin's page under **Keybinds**; nothing binds a key for you. Omit both `exec` and `ipc` to declare a shortcut you handle yourself with `CompositorGlobalShortcut`. |

Ids must be unique across plugins for the same kind. A `barWidgets`,
`desktopWidgets` or `quickToggles` entry that reuses a built-in id (`clockWidget`,
`media`, `network`, ...) **replaces** the built-in - that is the supported way to
swap out a stock widget.

### Where built-ins live

Built-ins are rows in the same tables plugin contributions land in, so anything the
shell ships can be replaced, and anything a plugin adds is a first-class citizen:

| Registry | Table of |
| --- | --- |
| `core/BarWidgetRegistry.qml` | bar widgets: file, name, icon, pill preference, pill colour, repeatability |
| `core/DesktopWidgetRegistry.qml` | desktop widgets: file, name, icon, and where the enabled flag is stored |
| `core/QuickToggleRegistry.qml` | quick toggles: file per panel style, dialog, required compositor |

None of these are consulted by more than one host. If you find yourself adding a
widget in two places, one of them is wrong.

### settings

An ordered array. Each entry becomes one row on the plugin's page under
**Settings → Plugins**, in this order.

```json
{
    "key": "format",
    "type": "string",
    "default": "hh:mm ap",
    "label": "Time format",
    "description": "Shown in small text under the control.",
    "icon": "schedule",
    "placeholder": "hh:mm ap",
    "group": "Appearance"
}
```

| `type` | Control | Extra fields |
| --- | --- | --- |
| `bool` | switch | |
| `int` | spin box | `min`, `max`, `step` |
| `real` | slider | `min`, `max` (shown as a percentage when `max <= 1`) |
| `string` | text field with a confirm button | `placeholder` |
| `enum` | dropdown | `options: [{ "value": "left", "label": "Left" }]` |

`key`, `type` and `label` are what matter; everything else is optional. Values are
validated against the schema on read, so a hand-edited `plugins.json` can't feed
your plugin a string where it expects a number.

`group` puts the row under a subheading, with the rows that share it. Groups appear
in the order they first occur, and rows without one come first — so a handful of
settings need no groups at all, and twenty are not a wall. Keep `description` to one
line: it sits under the control, and a three-line one makes the list ragged.

## Several files, subfolders and singletons

A plugin folder is not a QML module, so type resolution follows plain QML file
rules:

- **Siblings resolve by name.** `MyPanel.qml` can use `Helper {}` from
  `Helper.qml` next to it with no import at all.
- **Subfolders need a relative directory import.** From the plugin root,
  `import "widgets"`; from inside `widgets/`, `import ".."` to reach back up.
- **Singletons need a `qmldir`.** A `pragma Singleton` file resolves to
  `undefined` without one. Two lines fix it:

  ```
  # plugins/my-plugin/qmldir
  singleton MyState 1.0 MyState.qml
  ```

  and every file that reads `MyState` adds `import "."` (files in a subfolder
  use `import ".."` as usual). Listing only the singleton is enough — the other
  files in the folder keep resolving implicitly.

## Reading settings from QML

```qml
import qs.core

readonly property var settings: PluginConfig.of("my-plugin")
// settings.format, settings.showDate, ... defaults already filled in
```

It's a plain property: bind to it and the UI follows changes live, with no reload.

`plugins.json` is read asynchronously, so until `PluginConfig.loaded` turns true
every setting reads as its manifest default. Binding is unaffected — the binding
updates when the file lands. But if your plugin *acts* on a stored value rather
than just displaying it, wait for it, or you will act on the defaults once at
every startup:

```qml
Timer {
    interval: 600
    running: true
    onTriggered: {
        if (!PluginConfig.loaded) { restart(); return }
        // ... now the stored values are real
    }
}
```

Writing is rarely needed (the GUI does it), but available:

```qml
PluginConfig.set("my-plugin", "format", "HH:mm")
PluginConfig.reset("my-plugin", "format")     // back to the manifest default
```

Anything the manifest never declared is preserved too, so a plugin can stash
runtime state in the same place. `plugins/material-you-colors` uses that for an
`appliedSnapshot` key: it records the settings that were in effect at the end of
the last successful run, so the plugin can tell "the shell just restarted and
nothing changed" from "I was just enabled" without a control appearing in the GUI
for it.

## Theming: use `Theme`, not `Appearance`

`Appearance` is the shell's whole palette - fifty-odd colour roles, five rounding
steps, nine font sizes, fourteen animation curves. `import qs.core` gives you
`Theme`, which is the shortlist, named for what you are drawing rather than for
which Material role it happens to be:

```qml
Rectangle {
    color: Theme.raised
    radius: Theme.radius.m

    StyledText {
        text: "hello"
        color: Theme.text
        font.pixelSize: Theme.font.m
    }
}
```

Everything on it is a live binding onto the Material You palette generated from
the wallpaper, so a plugin that uses it recolours with the wallpaper and is
readable in light *and* dark with no branching and nothing to listen to.

### Surfaces stack, and they are translucent

This is the one thing worth reading twice. The shell composites layers, and each
one is computed to look right **painted on the layer below it**, with an alpha
that follows the user's transparency setting. `Theme.raised` over the wrong base -
or straight onto the wallpaper - comes out around 10% alpha and nearly invisible.

| Use | For |
| --- | --- |
| `Theme.panel` | a window the shell owns: a bar, a sidebar, a popup |
| `Theme.raised` | a card or row **inside a panel**. The usual one |
| `Theme.high` | a block inside a block |
| `Theme.top` | the innermost step: selected, focused |
| `Theme.solid` | **opaque.** Desktop widgets, and anything else over the wallpaper |

Text pairs with them: `Theme.text` for body text, `Theme.textDim` for captions and
units, `Theme.textFaint` for hints and placeholders, and `Theme.textOnPanel` for
text sitting directly on `Theme.panel`.

### The rest

```qml
Theme.accent  Theme.onAccent            // the wallpaper's colour, and what reads on it
Theme.accentBlock / .onAccentBlock      // a filled accent card
Theme.accentMuted / .onAccentMuted      // chips and toggles that shouldn't shout
Theme.error   Theme.errorBlock / .onErrorBlock
Theme.notice  Theme.noticeBlock / .onNoticeBlock   // Material has no warning role
Theme.outline Theme.outlineDim          // hairlines; already low contrast
Theme.dark                              // bool

Theme.font.xs|s|m|l|xl  .family  .mono  // m is body text
Theme.pad.xs|s|m|l|xl                   // m is the default gap
Theme.radius.xs|s|m|l|full              // m is a card, full is a pill
Theme.state.hover|press|focus|drag|disabled     // opacities, not colours

Theme.fade(colour, 0.5)                 // same colour, more transparent
Theme.mix(a, b, 0.3)
Theme.on(anyBackground)                 // readable text on an arbitrary colour
Theme.harmonize(brandColour)            // pull it towards the wallpaper palette
Theme.role("colTertiaryHover")          // escape hatch, by Appearance role name
```

Use the shell's curves, or your widget will move without feeling like it belongs:

```qml
Behavior on color { animation: Theme.anim.fast.colorAnimation.createObject(this) }
Behavior on width { animation: Theme.anim.normal.numberAnimation.createObject(this) }
```

`anim` has `fast` (colours, hovers), `normal` (position and size), `enter`, `exit`
and `bounce`.

`Appearance` is still there for a role this does not cover. Reaching for it means
opting out of the guarantee that light mode looks right.

## Base types

`import qs.core` gives you:

### PluginBarWidget

```qml
PluginBarWidget {
    id: root
    pluginId: "my-plugin"          // this is what gives you `settings`
    tooltip: qsTr("What this is")
    onClicked: doSomething()

    StyledText {
        text: Qt.formatDateTime(new Date(), root.settings.format)
        color: root.colText        // already right for the current pill style
    }
}
```

Without asking, you get:

| | |
| --- | --- |
| `colText`, `colTextDim`, `colAccent` | correct for every `bar.cornerStyle` and both modes. Hand-picking one here is the most common way a bar widget ends up unreadable in a style its author never tried |
| `settings` | this plugin's settings, manifest defaults filled in |
| `vertical`, `mirrored` | set by the bar; lay your content out along `vertical` |
| `tooltip` | honours the user's click-to-show setting |
| `popup` | a `Component` for a richer panel; `hoverTarget` is wired for you and it stays unbuilt until first hover |
| `clicked`, `rightClicked`, `middleClicked`, `scrolled(up)` | signals |
| `hovered`, `containsPress` | for your own state layers |
| `interactive` | set false for pure decoration, so it stops eating clicks |

Sizing for both orientations is handled. Your content has to size itself - use a
layout or a sized item, and don't anchor it to fill the widget. The internal
`MouseArea` is declared *before* your content, so a widget with its own
`MouseArea` keeps priority.

### PluginPopup

A hover panel with the shell's surface, shadow, radius, edge placement and
animation. Set it as a bar widget's `popup`:

```qml
popup: Component {
    PluginPopup {
        title: qsTr("Battery")
        subtitle: BatteryState.summary()
        icon: "battery_android_full"

        PluginRow { label: qsTr("Health"); value: "91%" }
        PluginSeparator {}
        PluginRow { label: qsTr("Draw"); value: "12.4 W"; shown: rateKnown }
    }
}
```

Leave `title`/`subtitle`/`icon` out for a bare panel with just your content.

### PluginRow, PluginCard, PluginSeparator

The three layouts every status panel re-invents, and the three most often got
slightly wrong.

`PluginRow` is a label on the left and a value on the right, with the value flush
to the edge however long the label gets. Use `shown:` rather than `visible:` so a
value the hardware didn't report takes up no space:

```qml
PluginRow { label: qsTr("Cycles"); value: `${cycles}`; shown: cyclesKnown }
```

`PluginCard` is a correct surface with padding, and optionally `interactive: true`
plus `onClicked`. `PluginSeparator` is a hairline at the right opacity.

### PluginBackgroundWidget

```qml
PluginBackgroundWidget {
    pluginId: "my-plugin"
    widgetId: "myDeskClock"     // must match the manifest entry id
    implicitWidth: 300
    implicitHeight: 140

    // Over the wallpaper, so draw an opaque backing of your own.
    Rectangle { anchors.fill: parent; radius: Theme.radius.m; color: Theme.solid }
}
```

Draggable, remembers its position per widget, hides itself when the screen is
locked unless the user opted in, and exposes `settings` and `colText`.

### Panels and services

Plain Quickshell:

```qml
// MyPanel.qml
import Quickshell
import Quickshell.Wayland

PanelWindow {
    visible: GlobalStates.myPanelOpen
    anchors { top: true; right: true }
    implicitWidth: 400
    implicitHeight: 300
    WlrLayershell.layer: WlrLayer.Overlay
    // ...
}
```

```qml
// MyService.qml - keybinds, IPC, timers
import Quickshell
import qs.services

Scope {
    CompositorGlobalShortcut {
        name: "toggleMyPanel"           // same name as in the manifest
        description: "Toggle my panel"
        onPressed: GlobalStates.myPanelOpen = !GlobalStates.myPanelOpen
    }

    IpcHandler {
        target: "myPlugin"
        function toggle(): void { GlobalStates.myPanelOpen = !GlobalStates.myPanelOpen }
    }
}
```

Use `CompositorGlobalShortcut`, not `GlobalShortcut` directly: it no-ops on
compositors that don't support it. Shortcut names must be unique - registering a
name twice crashes the shell.

## What you can import

| Module | Contents |
| --- | --- |
| `qs.core` | `PluginRegistry`, `PluginConfig`, `PluginBarWidget`, `PluginBackgroundWidget`, `PluginSettingsForm` |
| `qs.modules.common` | `Appearance` (colours, fonts, sizes, animations), `Config`, `Directories`, `Persistent` |
| `qs.modules.common.widgets` | `StyledText`, `MaterialSymbol`, `RippleButton`, `ContentPage`, `ContentSection`, `ConfigSwitch`, `ConfigSlider`, ... |
| `qs.modules.common.functions` | `ColorUtils`, `FileUtils`, `StringUtils`, `DateTimeUtils`, ... |
| `qs.services` | `DateTime`, `Weather`, `Audio`, `Network`, `Bluetooth`, `Battery`, `MprisController`, `Translation`, `WM`, ... |
| `qs` | `GlobalStates` |
| `Quickshell*`, `QtQuick*` | Everything Quickshell and Qt provide |

Use `Translation.tr("...")` for user-visible strings.

Do **not** import from `qs.modules.ii.*` - that's the illogical-impulse panel
family's internals and is free to change. If you need something from it, it
belongs in `modules/common` instead; open an issue.

The stock panels under `plugins/` are the one exception: they ship with the
shell, so `plugins/lock` and `plugins/overlay` do reach into `qs.modules.ii.bar`
and `qs.modules.ii.sidebarRight` for a component each. They get to break with
those modules; your plugin doesn't have to.

### Importing a module nothing else imports

If you import a `qs.*` module that no core file already imports, add it to
`core/PluginModuleAnchors.qml` as well.

A `qs.foo` module only exists once the engine has *compiled* an `import qs.foo`
statement. Everything reachable by static imports from `shell.qml` is compiled
before anything runs, so those modules are all registered in time. Plugins are
found on disk at runtime and loaded from a URL, so their imports are compiled far
too late to register anything, and a module only a plugin imports is never
registered at all:

```
module "qs.modules.common.panels.lock" is not installed
```

That is a whole plugin failing to load, silently, with only a line in the log.
`PluginModuleAnchors` is in the static graph and exists purely to import those
modules; adding a duplicate is harmless. `scripts/check-qml.sh` phase 2 loads every
plugin entry point with only the imports the shell really has, so a forgotten
anchor fails the check instead of shipping.

### Don't name a type after a singleton

Two types with the same name, one of them a singleton, resolve to whichever the
engine bound to the name first. The loser fails with `qmldir defines type as
singleton, but no pragma Singleton found`, and which one loses depends on load
order - so it can work for months and then not. `plugins/overlay`'s notes widget is
called `NotesWidget` and not `Notes` for exactly this reason: `qs.services` already
exports a `Notes` singleton. `check-qml.sh` phase 3 checks this.

## Enable state and the config file

`~/.config/illogical-impulse/plugins.json`, written by the GUI:

```json
{
    "my-plugin": {
        "enabled": true,
        "settings": { "format": "HH:mm" },
        "widgets": { "myDeskClock": { "enable": true, "x": 120, "y": 80 } }
    }
}
```

It's safe to edit by hand while the shell is running - the file is watched and
changes apply immediately. Deleting the file resets every plugin to its manifest
defaults.

Turning a plugin off destroys everything it contributed; turning it on
constructs it again. Neither requires a shell reload. Editing a `manifest.json`
also takes effect immediately (it's watched too); editing your plugin's `.qml`
needs a reload.

## Nix

Plugins committed under `plugins/` are installed with the shell automatically -
the whole folder is copied into the store, so no flake edit is needed to add one.

For an out-of-tree plugin, add it to your NixOS config:

```nix
programs.end4.plugins.my-plugin = ./path/to/my-plugin;
```

`runtimeDeps` from every installed manifest are resolved against `pkgs` and added
to the shell's `PATH`, so a plugin can call `jq` or `curl` without the user
installing anything.

## Debugging

- **Settings → Plugins** lists broken plugins with the reason (bad JSON,
  `id` not matching the folder, unsupported `apiVersion`).
- Load failures are logged as `[plugins] <id>: could not load <file>`; watch them
  with `journalctl --user -f -t quickshell` or by running `qs` in a terminal.
- `scripts/check-qml.sh plugins` compiles every plugin file and prints the ones
  whose imports or types don't resolve, without starting a shell or touching the
  one you're running. It exits non-zero if anything failed; a clean tree prints
  `failures=0` and nothing else.
- A plugin that fails to load can't take the shell down with it - the rest keeps
  running.

## Checklist

- [ ] Folder name matches `id`.
- [ ] `apiVersion` is 1.
- [ ] Every `entry` file exists and its root type is right for its kind.
- [ ] No `required property` on the root of an entry file - the loader can't fill
      those in.
- [ ] Every user-visible string wrapped in `Translation.tr(...)`.
- [ ] Every setting the plugin reads is declared in `settings`.
- [ ] Shortcut names are unique.
