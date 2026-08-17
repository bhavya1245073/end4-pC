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
                          "ipc": { "target": "myPanel", "function": "toggle" } } ],
    "searchProviders":[ { "id": "units", "entry": "UnitProvider.qml" } ],
    "contextMenuItems":[{ "id": "notes", "label": "New note", "icon": "note_add",
                          "order": 35, "panel": "notes" } ],
    "osdIndicators": [ { "id": "coffee", "entry": "CoffeeOsd.qml" } ],
    "sidebarTabs":    [ { "id": "tasks", "label": "Tasks", "icon": "checklist",
                          "entry": "TasksTab.qml", "order": 45 } ]
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
| `shortcuts` | A keybind, registered as `quickshell:<id>`. Give it `exec` (argv array) or `ipc` (`{ target, function }`) and the shell handles it with no QML from you. `suggestedKey` is documentation, shown in the plugin's page under **Keybinds** and by `ipc call plugins shortcuts`; nothing binds a key for you. Omit both `exec` and `ipc` to declare a shortcut you handle yourself with `CompositorGlobalShortcut`. |
| `ipc` | Commands on the shell's command line. Root type: `PluginIpc`. Every annotated function becomes `qs -c end4-pC ipc call <target> <function>`; `target` defaults to the plugin id. See below. |
| `searchProviders` | Live results in the launcher, mixed in with apps and the shell's own answers. Root type: `PluginSearchProvider` - set `prefix` to claim a prefix like `=`, or leave it empty to answer every query. |
| `contextMenuItems` | A row in the desktop right-click menu. Declarative: `panel` opens a panel, `ipc` calls a command, `exec` runs argv, `url` opens a link, `entry` names a submenu. `badge` names a `PluginBus` topic whose value is shown on the right. `$menuX`, `$menuY` and `$screen` are substituted, so a row can open something where the click happened. |
| `osdIndicators` | An on-screen display of your own - the volume/brightness style overlay. `OsdRegistry.show("<plugin>:<id>")` raises it; the shell handles the timeout, the stacking and the animation. |
| `sidebarTabs` | A full-height tab in the left sidebar, next to Intelligence, Translator, Media and Anime - which are rows in the same registry. `order` sorts it (the shell's are 10/20/30/40), `requires` gates it on a dotted config path. Pages load lazily, so a tab costs nothing until it is shown. |

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
| `core/PanelRegistry.qml` | every panel the shell can open, whether it is open, its arguments, and which panels are mutually exclusive |
| `core/SidebarTabRegistry.qml` | left sidebar tabs, the shell's four included |
| `core/ContextMenuRegistry.qml` | desktop right-click rows |
| `core/OsdRegistry.qml` | on-screen displays |

None of these are consulted by more than one host. If you find yourself adding a
widget in two places, one of them is wrong.

### Commands and keybinds

A plugin can add its own commands to the shell's command line. Point the manifest at a
file whose root is a `PluginIpc`:

```json
"provides": { "ipc": [{ "entry": "GifIpc.qml" }] }
```

```qml
import qs.core

PluginIpc {
    target: "gifs"                       // defaults to the plugin id

    function open(): void {
        GifPicker.open();
    }

    function search(query: string): void {
        GifPicker.search(query);
    }
}
```

```
qs -c end4-pC ipc call gifs open
qs -c end4-pC ipc call gifs search "cat"
```

Annotate parameters and return types - `void` included. Quickshell needs the types to
marshal a call, and an unannotated function is not exposed at all.

For a keybind, prefer `provides.shortcuts` over binding a shell command. A shortcut is
registered as a `quickshell:` global, which the compositor dispatches straight to the
running shell instead of spawning a process:

```json
"shortcuts": [{
    "id": "gifPicker",
    "description": "Open the GIF picker",
    "suggestedKey": "SUPER, plus",
    "ipc": { "target": "gifs", "function": "open" }
}]
```

```conf
# hyprland
bind = SUPER, plus, global, quickshell:gifPicker
```

Nothing binds a key for you - the shell has no business editing your compositor config -
but it will tell you exactly what to write:

```
qs -c end4-pC ipc call plugins shortcuts    # every declared keybind + the bind line
qs -c end4-pC ipc call plugins commands     # every IPC target plugins own
qs -c end4-pC ipc call plugins list         # what is installed, and on or off
qs -c end4-pC ipc call plugins toggle dock
```

`plugins/battery` is the worked example: `BatteryIpc.qml` plus a `shortcuts` entry that
calls it.

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

## System facades

Everything below is a singleton in `qs.core`. They exist so a plugin never has to know
that brightness is `brightnessctl` on one machine and DDC on another, that the CPU
temperature lives in a different `hwmon` node on every laptop, or that "is the
microphone in use" means walking Pipewire link groups. Read a property, call a
function.

They are also the answer to the most common way a plugin breaks: shelling out.
`Quickshell.execDetached(["bash", "-c", "..."])` with anything user-supplied in the
string is a command injection, costs a process per call, and gives you no result. If
you find yourself writing one, the thing you want is probably already here.

| Singleton | What it is | Some properties | Some functions |
| --- | --- | --- | --- |
| `ContextMenuRegistry` | Items in the desktop right-click menu, built-in and plugin alike. | `builtins`, `all` | `opensSubmenu`, `badgeValue`, `activate` |
| `OsdRegistry` | Every OSD indicator the shell can show, built-in and plugin alike. | `builtins`, `current`, `builtinBase`, `all`, `ids` | `find`, `urlFor`, `show` |
| `PanelRegistry` | Every panel the shell can open, and whether it is open. | `builtins`, `contributed`, `all`, `ids`, `states`, `revision` | `state`, `isOpen`, `groupOf`, `describe`, `open`, `close`, `toggle`, `set` |
| `PluginApps` | Installed applications: find them, launch them, pin them. | `all`, `count`, `pinned`, `categories` | `byId`, `find`, `search`, `inCategory`, `launch`, `launchWith`, `open`, `isPinned` |
| `PluginAudio` | Volume, per-app streams, and the audio spectrum. | `ready`, `sink`, `source`, `volume`, `muted`, `maxVolume` | `setVolume`, `changeVolume`, `setMuted`, `toggleMute`, `setInputVolume`, `toggleInputMute`, `playSound`, `acquireSpectrum` |
| `PluginBluetooth` | Bluetooth adapters and devices. | `available`, `enabled`, `connected`, `connectedCount`, `scanning`, `adapterName` | `toggle`, `setEnabled`, `scan`, `connectTo`, `disconnectFrom` |
| `PluginBus` | The event bus: how two plugins that have never heard of each other talk. | `topics`, `cellComponent` | `emit`, `publish`, `on`, `once`, `off`, `retained`, `value`, `has` |
| `PluginCommands` | `qs -c end4-pC ipc call plugins ...` - the plugin system's own command line. |  |  |
| `PluginConfig` | Per-plugin settings store. | `path`, `data`, `loaded`, `bags`, `bagKeys`, `emptyBag` | `of`, `value`, `set`, `reset`, `resetAll`, `setEnabled`, `widgetState`, `widgetValue` |
| `PluginDialogs` | Modal dialogs, drawn by the shell rather than by another program. | `current`, `queue`, `open` | `confirm`, `prompt`, `choose`, `alert`, `resolve`, `cancel`, `openFile`, `saveFile` |
| `PluginDisplay` | Screen brightness, gamma and night light. | `focusedMonitor`, `brightness`, `available`, `monitors`, `nightLight`, `gamma` | `setBrightness`, `step`, `increase`, `decrease`, `setBrightnessOn`, `setGamma` |
| `PluginFs` | Files, without the ceremony. | `home`, `configDir`, `cacheDir`, `dataDir`, `stateDir`, `runtimeDir` | `expand`, `url`, `dirname`, `basename`, `extension`, `join`, `read`, `readJson` |
| `PluginMedia` | Whatever is playing, whichever player it is in. | `player`, `available`, `isPlaying`, `title`, `artist`, `album` | `playPause`, `next`, `previous`, `play`, `pause`, `pauseAll`, `seek`, `seekFraction` |
| `PluginNetwork` | Wi-Fi, ethernet, and VPNs. | `online`, `type`, `wifiEnabled`, `wifiScanning`, `connecting`, `ssid` | `toggleWifi`, `enableWifi`, `rescan`, `connect`, `disconnect`, `refreshVpns` |
| `PluginNotifications` | Notifications: what arrived, what to do about it, and whether to be quiet. | `history`, `popups`, `count`, `unreadCount`, `hasAny`, `byApp` | `toggleDnd`, `setDnd`, `dismiss`, `clearAll`, `markAllRead`, `dismissPopups`, `invokeAction`, `send` |
| `PluginPower` | Power actions, battery, and sleep inhibitors. | `hasBattery`, `percent`, `isCharging`, `isLow`, `isCritical`, `isPluggedIn` | `lock`, `suspend`, `hibernate`, `reboot`, `rebootToFirmware`, `powerOff`, `logout`, `inhibit` |
| `PluginPrivacy` | Is anything using the microphone, the camera, or the screen right now. | `micInUse`, `screenSharing`, `micApps`, `screenApps`, `cameraInUse`, `cameraApps` | `refreshCamera` |
| `PluginRegistry` | Plugin discovery and registry. | `apiVersion`, `minApiVersion`, `pluginPaths`, `userPluginsDir`, `pluginsDir`, `pluginDirs` | `collectInstalled`, `sectionsFor`, `collect`, `pluginsByName`, `collectFrom`, `resolve`, `dirOf`, `get` |
| `PluginSearch` | Owns the live search providers plugins contribute, and aggregates their answers for the launcher. | `query`, `providerCount`, `results` | `run` |
| `PluginStorage` | Persistent per-plugin state that is not a *setting*. | `stores`, `loaded`, `storeComponent` | `of` |
| `PluginSystem` | Hardware telemetry, read from the kernel rather than parsed out of other programs. | `interval`, `diskInterval`, `paused`, `historyLength`, `cpu`, `memory` | `discover`, `refresh`, `refreshDisks` |
| `PluginTimer` | Time, without a Timer per idea. | `stats`, `handleComponent` | `after`, `next`, `every`, `debounce`, `throttle`, `cron`, `at`, `stopAll` |
| `PluginUtils` | Safe stand-ins for the things plugins otherwise shell out for. | `notifyAppName`, `fetchTimeout` | `copy`, `copyTyped`, `paste`, `notify`, `fetchJson`, `fetchText`, `exec`, `run` |
| `PluginWM` | Windows, workspaces and monitors, without caring which compositor is running. | `compositor`, `supportsWorkspaces`, `toplevel`, `activeWindow`, `windows`, `workspaces` | `focusWorkspace`, `nextWorkspace`, `previousWorkspace`, `focusWindow`, `closeWindow`, `closeActive`, `moveWindowToWorkspace`, `moveActiveToWorkspace` |
| `SidebarTabRegistry` | Tabs in the left sidebar, the shell's own and plugins' alike. | `builtins`, `all`, `buttons`, `ids` | `indexOf` |

*(Generated from `core/api.json`; `scripts/api.sh <name>` prints any of them in full.)*

### The ones you will reach for first

```qml
import qs.core

PluginBarWidget {
    pluginId: "vitals"
    tooltip: qsTr("CPU %1% · %2°C").arg(Math.round(PluginSystem.cpu.usage * 100)).arg(PluginSystem.cpu.temperature)

    PluginSparkline {
        values: PluginSystem.cpu.history       // already a rolling window
        color: Theme.accent
    }
}
```

`PluginSystem` polls `/proc` and `/sys` directly, once, for every plugin that asks -
CPU (per-core, temperature, frequency, load averages), memory, swap, GPU load and
VRAM, per-interface network rates, and mounted disks. Ten plugins reading it cost the
same as one.

`PluginUtils` is the small stuff you would otherwise shell out for: `copy`, `paste`,
`notify`, `fetchJson`, `fetchText`, `exec`, `run` (argv with a callback for stdout),
`pipe` (send a payload down stdin - the safe way to feed a program arbitrary text) and
`copyFile` (a file on the clipboard with a MIME type).

`PluginWM` is compositor-agnostic. `PluginWM.compositor` says which one is running,
but `focusWorkspace(3)`, `closeActive()` and `moveActiveToWorkspace(2)` do the right
thing on both, and `PluginWM.activeWindow` is one shape regardless.

`PluginPower.inhibit("burning a disc")` holds a real `systemd-inhibit` and hands you a
token to release. `PluginPrivacy.cameraInUse` is true when something has `/dev/video0`
open, which Pipewire cannot tell you. `PluginAudio.acquireSpectrum()` is reference
counted, so the FFT process runs while at least one widget wants it and stops when the
last one goes away.

## Panels

Every window the shell can open - its own and every plugin's - is a row in
`PanelRegistry`, addressed by id:

```qml
PanelRegistry.toggle("sidebarRight")
PanelRegistry.open("desktopMenu", { x: mouseX, y: mouseY, screen: screen.name })
PanelRegistry.close("launcher")
PanelRegistry.closeAll()
```

```bash
qs -c end4-pC ipc call panels list
qs -c end4-pC ipc call panels toggle sidebarRight
qs -c end4-pC ipc call panels state launcher
```

A plugin's `panels` entry is registered automatically, so `PanelRegistry.toggle("notes")`
works from anywhere - another plugin, a keybind, the command line - without importing
anything from the plugin that owns it.

To *react* to a panel opening, bind to its state rather than polling:

```qml
PanelState {
    panel: "launcher"
    onOpenChanged: if (open) refresh()
}
```

Or inside the panel itself:

```qml
PluginPopup {
    // args are whatever the caller passed to open()
    readonly property real spawnX: PanelRegistry.state("desktopMenu").args.x ?? 0
}
```

This replaced a singleton of booleans (`GlobalStates.sidebarRightOpen`, and twenty more)
that every panel, every bar button and every keybind referred to by name. A plugin
could not add one, because adding one meant editing core. `GlobalStates` still exists,
but only for things that are genuinely global session state - whether the screen is
locked, whether Super is held.

Panels in the same `group` close each other: opening the launcher closes the sidebar,
because both are in the `overlay` group. Declare it in the manifest
(`"group": "overlay"`) and exclusivity is handled.

## State, storage and events

### PluginStorage - remember things that are not settings

A setting is something the user sets in the settings GUI. A note's text, a to-do list,
the last window you had open, a cached exchange rate - none of those are settings, and
none of them belong in the manifest's `settings` schema.

```qml
import qs.core

Item {
    // Infers the plugin id from the folder it is in.
    PluginStore { id: store }

    Component.onCompleted: {
        store.set("lastOpened", Date.now())
        store.append("history", { text: "hello", at: Date.now() })
    }

    // Reading is a plain property read, and it updates when the value changes.
    StyledText { text: `${store.count("history")} entries` }
}
```

Key-value: `get`, `set`, `has`, `remove`, `keys`, `clear`, `update`.
Collections: `list`, `count`, `append`, `prepend`, `push` (append with a cap and
de-duplication), `find`, `upsert`, `removeFrom`, `removeWhere`, `clearList`.

It lives in the same `plugins.json` the settings live in, under a `storage` key, which
means one file, one watcher and one coalesced writer for all plugin state. Writing in a
loop is fine.

### PluginBus - talk to a plugin you have never heard of

```qml
// The publisher
PluginBus.publish("weather:current", { tempC: 21, icon: "sunny" })   // retained
PluginBus.emit("weather:refreshed")                                   // fire and forget

// The subscriber, anywhere else, with no import of the publisher
PluginBusListener {
    topic: "weather:*"                  // wildcards work
    replayRetained: true                // get the current value immediately
    onMessage: (topic, payload) => console.log(topic, payload.tempC)
}
```

`publish` retains: a subscriber that appears later still sees the last value.
`PluginBus.retained("weather:current")` hands back a live cell you can bind to, so a
widget can render another plugin's data without either plugin knowing the other
exists. This is how the desktop's file-drop reaches the dropover plugin - core emits
`desktop:filesDropped` and does not know whether anything is listening.

### PluginTimer - one place for everything time-shaped

```qml
PluginTimer.after(500, () => doIt())                    // once
PluginTimer.every(60000, () => refresh())               // repeating, returns a handle
PluginTimer.debounce("search", 250, () => run(query))   // last call wins
PluginTimer.throttle("scroll", 100, () => update())     // first now, rest coalesced
PluginTimer.cron("*/15 8-9 * * 1-5", () => standUp())   // real cron expressions
PluginTimer.at(new Date(tomorrow), () => goodMorning()) // absolute time
```

Every form returns a handle with `stop()` and `isRunning`. `PluginTimer.stats` lists
what is running, which is usually how you find the timer you forgot to stop.

### PluginFs - files, asynchronously

`read`, `readJson`, `readLines`, `write`, `writeJson`, `append`, `updateJson` all take
a callback and hand back a uniform result object (`{ ok, path, text, data, error }`).
`mkdir`, `remove`, `copy`, `move`, `exists`, `list` do the obvious thing. `readSync`
exists for `/proc` and `/sys`, where an async read would be a poll behind.

```qml
PluginFsWatch {
    path: "~/.config/thing/state.json"
    json: true
    onChanged: apply(data)          // fires on every write, parsed
}
```

## UI building blocks

`import qs.core` and none of this needs styling: every one of them reads `Theme`, so a
plugin's UI changes with the wallpaper along with the rest of the shell.

| Type | For |
| --- | --- |
| `PluginBarWidget` | a bar item. Handles pill styles, both bar orientations, tooltips, click and scroll |
| `PluginBackgroundWidget` | a desktop widget. Handles dragging, snapping, persistence |
| `PluginPopup` | a popup anchored to a bar widget |
| `PluginDrawer` | a panel that slides in from an edge, optionally reserving space |
| `PluginFloatingWindow` | a movable, resizable window whose geometry is remembered |
| `PluginHud` | a transient overlay: `flash()` and it fades itself out |
| `PluginCard`, `PluginDesktopCard` | the shell's surfaces, with its hover and press response |
| `PluginRow`, `PluginSettingRow`, `PluginSeparator` | settings rows, the same ones the shell's own pages use |
| `PluginForm` | a whole form from a field list, using the manifest's settings schema |
| `PluginSections` | where a plugin's settings sections land on a page |
| `PluginIconButton`, `PluginChip`, `PluginBadge` | the interactive small parts |
| `PluginTabs`, `PluginListView` | a tab strip with a sliding indicator; a searchable list with an empty state |
| `PluginSparkline`, `PluginGauge` | a chart and a radial meter, both Canvas-based and repainting only on change |
| `PluginAppear`, `PluginTransition` | entrance animation, staggered, in one line |
| `PluginSpectrum` | audio spectrum points, reference counted |
| `PluginStore`, `PluginBusListener`, `PluginFsWatch`, `PanelState` | declarative wrappers for the singletons above |

### Motion

`Theme.motion` is the shell's animation vocabulary: four durations
(`instant`, `quick`, `normal`, `slow`), seven curves (`standard`, `decel`, `accel`,
`emphasized`, `spring`, `bounce`, `linear`), and `Theme.motion.delay(index)` for
staggering a list without every widget inventing its own timing.

```qml
PluginAppear {
    index: model.index          // staggered, capped so a long list does not crawl
}
```

A plugin that uses `Theme.motion` moves like the shell. A plugin that hardcodes
`duration: 200; easing.type: Easing.OutQuad` does not, and it shows.

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
