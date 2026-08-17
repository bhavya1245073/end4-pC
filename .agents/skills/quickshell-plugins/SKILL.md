---
name: quickshell-plugins
description: Build and modify plugins for the end4-pC Quickshell desktop shell, and safely edit its core. Use for any work in the end4-pC fork or a shell tree containing core/PluginRegistry.qml — bar widgets, desktop widgets, quick toggles, panels, background services, settings pages and sections, launcher actions, keybinds, plugin IPC commands, Material You theming of QML widgets, the performance contract that keeps toggling a plugin at one frame, the built-in profiler, and the check-qml.sh / check-icons.sh verification workflow. Covers the plugin API (Theme, PluginBarWidget, PluginPopup, PluginRow, PluginCard, PluginConfig, PluginIpc), the three built-in registries, the manifest format, the failure modes that silently kill a plugin, and what the plugin system cannot do.
compatibility: Needs a Wayland session to run scripts/check-qml.sh (Quickshell will not start without one). Quickshell 0.3+, Qt 6.7+.
---

# Quickshell plugins (end4-pC)

A plugin is **one folder** with a `manifest.json`. Nothing else installs it: no
core file to edit, no import to register, no Nix change.

Work from this document. The tree is ~565 QML files and reading it to answer
"what colour should this text be" is how you end up with a widget that is
invisible in light mode.

## Where to put it — decide this first

Two trees can hold plugins, and picking the wrong one costs a
commit-push-flake-bump cycle on every iteration.

| Put it here | When | Install step |
| --- | --- | --- |
| `~/nixos-pc/modules/home/quickshell/plugins/<id>/` | **anything personal to this machine** — the default answer | drop the folder, `rebuild` |
| `~/Projects/end4-pC/plugins/<id>/` | it belongs to the shell itself and should ship with the fork | commit, push, `nix flake update end4-pc`, `rebuild` |

The NixOS config auto-discovers every folder under
`modules/home/quickshell/plugins/` that holds a `manifest.json` and copies it in
beside the shell's own. There is **no Nix to write** — no `programs.end4.plugins`
entry, no module edit. Scaffold one:

```bash
cd ~/nixos-pc
./scripts/new-plugin.sh weather-pill                        # bar widget
./scripts/new-plugin.sh weather-pill --kind desktopWidget   # desktop widget
rebuild
```

**Flakes only see git-tracked files.** An untracked plugin folder evaluates to
nothing, installs nothing and reports no error — the plugin simply is not there.
`new-plugin.sh` runs `git add -N` for you; by hand, do it yourself:

```bash
git -C ~/nixos-pc add -N modules/home/quickshell/plugins/weather-pill
```

A local plugin shadows a fork plugin of the same name, which is how to iterate on
a shipped one without touching the fork. `programs.end4.plugins = { x = /abs/path; }`
still exists, but only for a plugin living somewhere else entirely.

Working local example: `modules/home/quickshell/plugins/quote-of-the-day/` — bar
widget, desktop widget, an `ipc` target, two shortcuts, a plugin-local singleton,
a `.js` data file and 8 settings.

Everything below applies to both trees; only the install step differs.

## Orientation

| Path | What |
| --- | --- |
| `core/` | the plugin system. `PluginRegistry`, `PluginConfig`, `Theme`, the registries, base types |
| `plugins/<id>/` | one plugin |
| `modules/common/widgets/` | the shell's widget library (`StyledText`, `MaterialSymbol`, …) |
| `modules/common/Appearance.qml` | the full palette. Prefer `Theme` |
| `modules/ii/` | the illogical-impulse panel family: bar, sidebars, settings, background |
| `services/` | singletons: `Battery`, `Audio`, `Network`, `DateTime`, `Translation`, `WM` … |
| `scripts/check-qml.sh` | six phases, the last one runs the shell. **Run this.** |
| `scripts/check-icons.sh` | Material Symbol names vs the installed font |
| `docs/PLUGINS.md` | the authoring guide this skill summarises |
| `docs/ARCHITECTURE.md` | core vs plugin, the registries, the performance layer |

Paths above are relative to the fork checkout (`~/Projects/end4-pC`). A plugin
being developed in the NixOS config still imports `qs.core`, `qs.services` and
the rest exactly the same way — it is copied into the same tree at build time — but
`check-qml.sh` only sees what is in the fork, so verify a local plugin by
rebuilding and reading `qs log` (see **Verify**).

## The 60-second plugin

Don't hand-write one. The scaffolder emits a working plugin, and the two richest templates
show the whole SDK:

```bash
scripts/new-plugin.sh tasks --type=window   # window + panel + bar pill + IPC + intents + keybind + undo
scripts/new-plugin.sh gifs  --type=picker   # PluginContentView over PluginHttp, with a persisted collection
scripts/new-plugin.sh hi                    # a bar widget, the smallest useful thing
```

Every template is validated on the way out. What one looks like by hand:

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
caught by `scripts/check-qml.sh` (phases 2 and 3). Neither is obvious from reading
your own code. Phases 4–10 catch more of the same character — see **Verify**.

A third belongs beside them, because it is the one that bites hardest and no compile
catches it: **a `pragma Singleton` file with no `qmldir` line still resolves** — as the
*type*, not the instance. Every call on it then fails with `is not a function` and every
property reads `undefined`. Two lines fix it, and `scripts/new-plugin.sh` now writes them:

```
# plugins/my-plugin/qmldir
singleton MyState 1.0 MyState.qml
```

And the pragma must be on **line 1** — the scanner gives up at the first `{`, including one
inside a comment above it.

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
be complete, not minimal. 25 modules are anchored, including every
`qs.modules.ii.background.widgets.*` submodule (a desktop widget loaded by URL
otherwise cannot see its own siblings) and both quick-toggle style directories:

```
qs.core  qs.services  qs.modules.common  qs.modules.common.widgets
qs.modules.common.functions  qs.modules.common.utils  qs.modules.common.models
qs.modules.common.models.gCloud  qs.modules.common.panels.lock
qs.modules.common.widgets.widgetCanvas  qs.modules.ii.bar
qs.modules.ii.sidebarRight.volumeMixer
qs.modules.ii.sidebarRight.quickToggles.androidStyle
qs.modules.ii.sidebarRight.quickToggles.classicStyle
qs.modules.ii.background.widgets  + .calendar .clock .images .media .notes
                                    .resources .usercard .visualizer .weather
                                    .worldclock
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

## Never shell out — look here first

The single most common way plugin code goes wrong is
`Quickshell.execDetached(["bash", "-c", ...])`. It costs a process, gives you no
result, and if any part of the string came from outside the plugin it is a command
injection. Every one of these is a singleton in `qs.core`:

| Want | Use |
| --- | --- |
| CPU / memory / GPU / net / disk numbers | `PluginSystem.cpu.usagePercent`, `.memory.usedFormatted`, `.gpu.usagePercent`, `.network.downloadFormatted`, `.disks.forPath("/")` |
| volume, per-app streams, spectrum | `PluginAudio`, `PluginSpectrum` |
| what is playing | `PluginMedia.title`, `.playPause()` |
| windows, workspaces, monitors | `PluginWM` — works on Hyprland and Niri both |
| battery, suspend, lock, inhibitors | `PluginPower` |
| brightness, night light | `PluginDisplay` |
| Wi-Fi, VPNs | `PluginNetwork` |
| Bluetooth | `PluginBluetooth` |
| is the mic/camera/screen in use | `PluginPrivacy` |
| notifications, do-not-disturb | `PluginNotifications` |
| installed apps, launching, pinning | `PluginApps` |
| ask the user something | `PluginDialogs.confirm/prompt/choose/alert`, `openFile`, `saveFile` |
| read or write a file | `PluginFs`, `PluginFsWatch` |
| any kind of timer | `PluginTimer.after/every/debounce/throttle/cron/at` |
| remember something between runs | `PluginStore` / `PluginStorage` |
| talk to another plugin | `PluginBus` / `PluginBusListener`, or `PluginIntent.call("other:action", args)` to invoke it |
| HTTP with a cache, a timeout and cancellation | `PluginHttp.get/post` — never `curl`, never bare `XMLHttpRequest` |
| "Copied", "Saved", "Could not reach the API" | `PluginToast.show/success/error/notice` |
| undo for something destructive | `PluginHistory.recordWithToast({ label, undo, redo })` |
| what the user is doing right now | `PluginContext.focusedApp`, `.selectedText`, `.clipboard`, `.activeMonitor` |
| should I be running at all | `PluginLifecycle.awake`, `.animate`, `.pollFactor` |
| a list of favourites/pins/recents | `PluginStorage.collection(id, key)` — `add`/`toggle`/`has`/`list`/`clear` |
| everything above, with permissions checked | `PluginUtils.as(pluginId)` — a scoped facade |
| clipboard, notify, run a command | `PluginUtils.copy/notify/run/pipe/copyFile` |

`scripts/api.sh <name>` prints any of them in full, from the generated catalogue in
`core/api.json`. Check there before writing a `Process`.

Prefer the scoped facade in plugin code:

```qml
readonly property var utils: PluginUtils.as("my-plugin")

utils.get(url, { cacheTtl: 60000, owner: root }, r => ...)   // needs "network"
utils.copy(text)                                              // needs "clipboard"
utils.toast(qsTr("Copied"))
utils.record(qsTr("Cleared"), { undo: restore, redo: clear })
utils.collection("favourites").toggle(item)
```

It carries the plugin id, so the `permissions` in the manifest are actually enforced and a
refused call names who was refused.

If you do need to run something: `PluginUtils.run(argv, callback)` for output,
`PluginUtils.pipe(argv, payload, callback)` to feed it stdin. Never build a shell
string around data. If a shell is genuinely unavoidable, put the script in the `-c`
argument and pass data as `$1`, `$2` — never interpolate it into the script text.

## Panels

Every window in the shell, its own and every plugin's, is a row in `PanelRegistry`:

```qml
PanelRegistry.toggle("sidebarRight")
PanelRegistry.open("myPanel", { x: mouseX, y: mouseY })   // args, not globals
PanelRegistry.close("myPanel")
```

```bash
qs -c end4-pC ipc call panels list        # every panel and whether it is open
qs -c end4-pC ipc call panels toggle overview
```

A plugin's `panels` entry is registered automatically, so anything can open it by id
without importing the plugin. To react to a panel, bind rather than poll:

```qml
PanelState { panel: "launcher"; onOpenChanged: if (open) refresh() }
```

Inside the panel, read what the caller passed:
`PanelRegistry.state("myPanel").args.x`.

Do **not** add a `property bool somethingOpen` to a singleton for this. That is what
this replaced: ~290 references to named booleans that no plugin could join.

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

**A popup with anything clickable in it must set `dismiss: "manual"`.** The default,
`"pill"`, closes the popup as soon as the pointer leaves the bar widget — and since
the popup is a separate Wayland surface, the pointer has to leave the widget to reach
it, so a button in it can never be clicked.

```qml
PluginPopup {
    dismiss: "manual"     // click to open, stays until click-outside or Escape
    PluginCard { interactive: true; onClicked: act() }
}
```

Do not try to fix `"pill"` by also tracking hover on the popup. That trades "closes
too early" for "stuck on screen", because it depends on a pointer-leave event
arriving for a surface that maps and unmaps under the cursor, and when one is missed
there is nothing left to close the popup. `"manual"` covers the screen with a
transparent catcher instead: the card takes clicks, everything else closes it, and no
part of it is a race.

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

### The rest of the kit

All in `qs.core`, all themed, none of them needing styling from you:

| Type | For |
| --- | --- |
| `PluginContentView` | **the one to reach for** — grid/list/detail over a list of things, with debounced search, category chips, arrow keys, hover actions, progressive images, empty and loading states |
| `PluginProgressiveImage` | still thumbnail now, animated preview on hover, decoded at draw size |
| `PluginErrorBoundary` | loads plugin QML and draws the error where the plugin should have been |
| `PluginDropTarget`, `PluginDraggable` | accept drops (decoded paths, correct highlight) and drag out into other applications |
| `PluginSurface` | one file for bar pill / flyout / full window; the host picks the slot |
| `PluginBackdropBlur`, `PluginGlowBorder`, `PluginMeshGradient` | blur of the shell's wallpaper, a focus/drag glow, an animated palette gradient |
| `PluginIntentHandler` | implements a declared action, when an IPC function of the same name is not the shape you want |
| `PluginDrawer` | a panel sliding in from an edge, optionally reserving space |
| `PluginFloatingWindow` | movable, resizable, geometry remembered across restarts |
| `PluginHud` | a transient overlay — `flash()` and it fades itself out |
| `PluginForm` | a whole form from a field list (same schema as manifest `settings`) |
| `PluginTabs`, `PluginListView` | tab strip with a sliding indicator; searchable list with an empty state |
| `PluginSparkline`, `PluginGauge` | a chart and a radial meter, repainting only on change |
| `PluginIconButton`, `PluginChip`, `PluginBadge` | the interactive small parts, with hover/press/focus already right |
| `PluginAppear` | staggered entrance animation in one line: `PluginAppear { index: model.index }` |
| `PluginDesktopCard` | a desktop widget surface, opaque and correctly shadowed |

### Motion

Use `Theme.motion`, never a hardcoded duration or curve:

```qml
Behavior on opacity {
    NumberAnimation { duration: Theme.motion.fast; easing.bezierCurve: Theme.motion.standard; easing.type: Easing.Bezier }
}
```

Durations: `instant` 90, `fast` 200, `medium` 350, `slow` 500, `enter` 400, `exit` 200.
Curves: `spatial`, `spatialFast`, `effects`, `emphasized`, `decelerate`, `accelerate`,
`standard`. And `Theme.motion.delay(index)` for staggering. A plugin using them moves like the shell;
one using `duration: 200; Easing.OutQuad` visibly does not.

## What a plugin can provide

Every kind is an array under `provides`. Each entry needs an `id`; most need
`entry` (a QML file, resolved relative to the plugin folder).

| Kind | What it does | Extra fields |
| --- | --- | --- |
| `barWidgets` | a widget the user can place in the bar | `name`, `icon`, `pillColor`, `materialPill`, `multipleAllowed` |
| `desktopWidgets` | a draggable desktop widget | `name`, `icon`, `enabledByDefault` |
| `quickToggles` | a tile in the sidebar's quick settings panel | `classicEntry`, `menu`, `requires` |
| `panels` | a window the plugin owns, addressable through `PanelRegistry` | `label`, `group` |
| `services` | a non-visual always-on object: timers, watchers | — |
| `ipc` | commands on the shell's command line | root type `PluginIpc` |
| `settingsPages` | a whole page in Settings, with a nav entry | `name`, `icon`, `order` |
| `settingsSections` | a section injected into an **existing** Settings page | `page`, `order` |
| `launcherActions` | a result in the launcher | `exec` |
| `shortcuts` | a keybind, bound as `quickshell:<id>` | `description`, `suggestedKey`, plus `exec` **or** `ipc` |
| `searchProviders` | live results in the launcher | root type `PluginSearchProvider`; set `prefix` to claim one |
| `contextMenuItems` | a row in the desktop right-click menu | `label`, `icon`, `order`, and one of `panel` / `ipc` / `exec` / `url` / `entry`; `badge` names a bus topic |
| `osdIndicators` | an OSD of your own, raised with `OsdRegistry.show()` | — |
| `sidebarTabs` | a full-height tab in the left sidebar | `label`, `icon`, `order`, `requires` |
| `actions` | something the plugin can be asked to do, reachable from the launcher, a keybind, the CLI and other plugins | `label`, `description`, `icon`, `keywords`, `schema` |

And one top-level key beside `provides`:

| Key | What it does |
| --- | --- |
| `permissions` | `network`, `clipboard`, `storage`, `system-exec`, `notifications`, `window-manager`. Shown to the user before they enable the plugin, revocable afterwards, and enforced for anything routed through `PluginUtils.as(id)` or `PluginHttp`. |

An `actions` entry needs no separate implementation if the plugin already exposes an IPC
function of the same name — declaring it is enough. Arguments are validated against `schema`
first, so the function can read them without guarding.

`settingsSections` is how a plugin's settings sit next to the related built-in
ones *and disappear when the plugin is switched off*. Host pages render
`PluginSections { page: "Interface" }`.

```json
"settingsSections": [
    { "id": "dock", "page": "Interface", "entry": "DockSettings.qml", "order": 20 }
]
```

`quickToggles` needs one file for both panel styles — inherit
`AndroidQuickToggleButton` and it works in the classic panel too. Supply
`classicEntry` only if you want a different file there. It shows up in the unused
toggle tray and drags into the grid like any built-in.

### Commands and keybinds

`ipc` gives the plugin its own command line. Point at a file whose root is a
`PluginIpc`; every **annotated** function becomes a command:

```qml
import qs.core

PluginIpc {
    target: "gifs"                          // defaults to the plugin id

    function open(): void { GifPicker.open() }
    function search(query: string): void { GifPicker.search(query) }
}
```

```
qs -c end4-pC ipc call gifs open
qs -c end4-pC ipc call gifs search "cat"
```

Annotate parameter *and* return types, `void` included. Quickshell needs them to
marshal a call; an unannotated function is silently not exposed.

`shortcuts` needs no QML at all:

```json
"shortcuts": [
    { "id": "gifPicker", "description": "Open the GIF picker",
      "suggestedKey": "SUPER, plus", "ipc": { "target": "gifs", "function": "open" } },
    { "id": "powerSave", "exec": ["powerprofilesctl", "set", "power-saver"] }
]
```

Bind it as `bind = SUPER, plus, global, quickshell:gifPicker`. Prefer this over
binding `qs ipc call ...`: a `quickshell:` global is dispatched straight to the
running shell, while a bound command spawns a process per press.

Nothing edits the user's compositor config. Tell them what to write by asking the
shell:

```bash
qs -c end4-pC ipc call plugins shortcuts   # every keybind + the exact bind line
qs -c end4-pC ipc call plugins commands    # IPC targets plugins own
qs -c end4-pC ipc call plugins list        # installed, on/off, what each provides
qs -c end4-pC ipc call plugins toggle dock
```

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
anywhere. What you get back is a long-lived object with one **typed QML property
per declared setting**, so `settings.foo` is a precise dependency: a write to some
other key, or to another plugin, does not re-run your binding, and the object's
identity never changes. Do not copy it into a plain object — that throws away the
precision and reintroduces a cascade where one write re-ran every plugin's every
binding.

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
scripts/doctor.sh                 # start here - manifests, singletons, icons, api, compile, live shell
scripts/doctor.sh --quick         # ~2s: everything that does not need a shell
scripts/doctor.sh --plugin gifs   # one plugin

scripts/check-qml.sh              # all ten phases
scripts/check-qml.sh plugins      # one subtree (phases 1 and 3 only)
scripts/check-icons.sh            # Material Symbol names vs the font
```

`doctor.sh` is the one to run. It wraps the others and adds the checks that need a
*running* shell, which is where a whole class of failure only ever shows up: an action
declared with no handler, a permission used but not declared, a singleton that resolved to a
type. Static checks pass on all three.

Expect exit 0. Ten phases, and you need to know why each exists — every one after
the first was added because a bug got through the ones before it:

1. **Every file compiled individually.** Catches syntax and missing types. *Can
   give false negatives*: compiling an internal file the shell never loads that
   way primes the engine's type cache and can hide a real clash.
2. **Entry points, with only the imports `shell.qml` really has.** This is the
   phase that catches a missing module anchor.
3. **Type names that also name a singleton.** Deterministic. Catches failure
   mode 2.
4. **Singletons used without importing their module.**
5. **Uninitialised `required` properties in URL-loaded components.** A component
   with one cannot be constructed, so a `Loader` reports `Loader.Error` and draws
   nothing — and phases 1–4 all pass, because it compiles fine. Only reports a
   required property that *nothing in the inheritance chain initialises*, so a base
   requiring something the concrete file always sets is not flagged, and neither is
   `required property var modelData` in a nested delegate.
6. **Runtime: binding loops and cache coherence.** The only phase that runs
   anything. It loads the registries with their real consumers — bar content, both
   quick panel styles, every desktop widget — in an **invisible** window, then fails
   on `Binding loop detected` and on a memoised list disagreeing with a fresh
   computation. Both of those compile perfectly; a binding loop makes Qt *drop a
   binding*, so a property silently stops updating.

`check-icons.sh` catches a bug with no error message at all: an unknown Material
Symbol name is not an error and draws no placeholder — the font just renders the
string, so `icon: "power_plug"` writes the word PLUG across your widget at icon
size. It validates by rendering each name and measuring: a real ligature collapses
to one glyph, a missing one stays as text.

Compiling is not running. To catch binding errors in one component, instantiate it:

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

**A probe window must be `visible: false`.** A visible `PanelWindow` in a probe
paints layer-shell surfaces over the user's desktop. Note that this makes every
descendant report `visible === false`, so a visibility-guarded walk has to be
relaxed inside a probe. And a probe that calls `setEnabled` or writes
`Config.options.*` is writing the real config — back it up and restore it.

**A probe measures a model of the shell, not the shell.** Two rounds of probe
benchmarks put the cost of toggling a plugin at 13 ms while the real shell
stuttered for 390 ms, because a probe has no settings window open, no compositor
round trips for real layer-shell surfaces, and none of the GPU work of a real
frame. When something feels slow, measure the running shell:

```bash
qs -c end4-pC ipc call perf start "toggling dock"
#  ...do the slow thing...
qs -c end4-pC ipc call perf report    # worst stall, % of wall blocked, buckets
qs -c end4-pC ipc call perf cache     # how many files are pre-compiled
qs -c end4-pC ipc call perf lists     # derived-list churn (misses climbing = churn)
qs -c end4-pC ipc call perf plugin dock false   # toggle without clicking
```

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
  `QuickToggleRegistry`, in the same shape as plugin contributions, so a host reads
  one list and cannot tell the difference. Adding one in a second place is how the
  two bars drifted into blacklisting different widgets from the pill.
- **A derived list must be identity-stable.** QML rebuilds a Repeater, recreates an
  Instantiator's delegates and re-runs a binding by comparing an array's
  *identity*, never its contents — so a list recomputed because of an unrelated
  dependency hands every consumer a new array equal to the old one, and they all
  rebuild. Wrap it: `Stable.list("myRegistry.all", (() => { ... })())`. Use
  `Stable.ids()` for string arrays and `Stable.index(key, list)` for an id map.
- **Memo state goes in `Memo.js`, not in properties.** A memo reads the cache it
  also writes, and doing that with QML properties inside a binding is a dependency
  cycle: Qt reports a binding loop and *drops a binding*, so the property silently
  stops updating. `.pragma library` variables are plain JS and invisible to the
  property system.
- **A cache key and its value must come from the same instant.** Keying on
  `activeIds` while computing from `active` — a binding derived *from* activeIds —
  cached a pre-change result under a post-change key, permanently. It shipped as
  zero plugin panels with every plugin enabled.
- **Never bind to `.length` of an array you mutate in place.** `push`/`shift` on
  the array a `var` property holds emits nothing, so
  `readonly property bool idle: queue.length === 0` is evaluated once and never
  again. `ComponentCache` shipped with this and silently compiled nothing.
- **Anything loaded by URL should be pre-compiled.** `Loader.source` compiles *and*
  instantiates; the compile is the expensive half and it lands on the UI thread.
  `Prewarm` warms everything reachable from a manifest or a registry — add new kinds
  there. Do not bind a long-lived `Loader.component` to `ComponentCache.get(url)`:
  it is null until warm, and null → Component would reload a showing item.
- **Unloading is for things expensive to *keep*, not expensive to *build*.**
  `PluginSections` unloaded a settings section when its plugin went off, which cost
  390 ms of blocked UI thread per toggle — the entire reason some plugins felt
  laggy and others did not. It now builds once and only changes `visible`; Qt Quick
  Layouts exclude invisible items, so it collapses identically. `asynchronous: true`
  is not a substitute; the incubator still works on this thread.
- **`settings` has real properties — bind to the key, not the object.**
  `PluginConfig.of(id)` returns a long-lived object generated from the manifest
  schema, so `settings.format` is a precise dependency and its identity never
  changes. Do not copy it into a new object or build your own settings map: that
  reintroduces the cascade where one write re-ran every plugin's every binding.
- **Annotate function return types.** `function find(id: string): var` — otherwise
  Qt logs "insufficiently annotated" per call.
- **Never gate a `Loader` on its own `source`.** `active: source != ""` is a
  binding loop; Qt drops a binding and nothing loads.
- **No `required property` in anything loaded by URL.** See phase 5.
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

- **Launcher search providers** — a plugin can add a static `launcherActions`
  entry, but cannot answer a query dynamically.
- **No sandboxing.** A plugin is QML in the shell's process with the shell's
  privileges. It can read any file, spawn any process, and break the shell. There
  is no permission model; `runtimeDeps` is convenience, not confinement.
- **No inter-plugin API.** Plugins cannot import each other. Talk over
  `PluginIpc`, or put the shared part in `modules/common/` and anchor it.
- **No hot reload.** Editing a plugin needs `qs kill && qs`, or `qr` in devMode.
- **Notification actions, OSD content, bar layout *regions*, `Background`'s shader
  list, and the desktop right-click menu's top-level items** are not extension
  points yet. (The menu's **Widgets** submenu is — it reads
  `DesktopWidgetRegistry`.)
- **A plugin cannot add keys to `config.json`.** Use `plugins.json`, or write to
  an existing `Config.options` key.
- **A panel using `Variants` still blocks while it loads.** Quickshell documents
  that `Variants` has no async support, so `activeAsync` cannot help it. That is one
  plugin's cost rather than every plugin's, which is the best available outcome.

## References

- [Full API reference](references/API.md) — every provides field, every `Theme`
  member, every base-type property, the registries, the performance contract
- `docs/PLUGINS.md` in the tree — the authoring guide
- `docs/ARCHITECTURE.md` — core vs plugin, what happens when you toggle a plugin,
  the performance layer, the six check phases
- `plugins/example-clock/` — bar widget + desktop widget + launcher action
- `plugins/battery/` — the fullest example: drawn graphics, a plugin singleton, a
  popup, both widget kinds, an `ipc` target and a shortcut that calls it
- `plugins/material-you-colors/` — a service, `IpcHandler`, acting on stored
  state, 20 grouped settings
