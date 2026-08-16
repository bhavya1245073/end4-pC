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
    "launcherActions":[ { "id": "hello", "exec": ["notify-send", "hi"] },
                        { "id": "backup", "script": "scripts/backup.sh" } ],
    "shortcuts":      [ { "name": "toggleMyPanel", "description": "Toggle my panel",
                          "suggestedKey": "SUPER, M" } ]
}
```

| Kind | What it does |
| --- | --- |
| `panels` | A window. Loaded once at shell scope while the plugin is on. Root type: `PanelWindow` (or a `Scope` holding several). |
| `services` | A non-visual object: timers, file watchers, `Process`, `IpcHandler`. Loaded once at shell scope. Root type: `Scope` or any `QtObject`. |
| `barWidgets` | Selectable in **Settings → Bar** and placeable in any of the three bar sections. `pillColor` is one of `primary`, `secondary`, `tertiary`, `primaryContainer`, `secondaryContainer`, `tertiaryContainer`, `layer0`, `layer1`. `materialPill: false` opts out of the pill in the Material bar style. `multipleAllowed: true` lets the widget be added more than once. |
| `desktopWidgets` | Draggable widget on the wallpaper. Toggle in **Settings → Desktop → Widgets → From plugins**. |
| `settingsPages` | A whole page in the settings sidebar, for when the generated form isn't enough. `order` sorts them (default 100). |
| `launcherActions` | `>`-prefixed launcher action. Either `exec` (argv array) or `script` (path inside the plugin). Anything typed after the action name is appended as arguments. |
| `shortcuts` | *Declarative metadata only*: it documents the keybind and lets the NixOS module generate it. The handler itself lives in your QML (see below). |

Ids must be unique across plugins for the same kind. A `barWidgets` entry that
reuses a built-in id (`clockWidget`, `media`, ...) **replaces** the built-in - that
is the supported way to swap out a stock widget.

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

## Base types

`import qs.core` gives you:

### PluginBarWidget

```qml
PluginBarWidget {
    id: root
    readonly property var settings: PluginConfig.of("my-plugin")

    StyledText {
        text: Qt.formatDateTime(new Date(), root.settings.format)
        color: Appearance.colors.colOnLayer1
    }
}
```

Handles sizing for both bar orientations. `vertical` and `mirrored` are set for
you; `isMaterial` tells you which bar style is active. Your content has to size
itself - use a layout or a sized item, and don't anchor it to fill the widget.

### PluginBackgroundWidget

```qml
PluginBackgroundWidget {
    pluginId: "my-plugin"
    widgetId: "myDeskClock"     // must match the manifest entry id
    implicitWidth: 300
    implicitHeight: 140
    // ... content
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
