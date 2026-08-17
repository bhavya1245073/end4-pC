# How this fork is put together

Upstream is one large QML tree where every panel, bar widget and quick toggle is wired
in by hand. This fork splits it into a **core** that provides infrastructure and
extension points, and **plugins** that provide features.

```
shell.qml                  bootstrap; loads the panel family + PluginHost
core/                      the plugin system: registries, config, base types, perf
panelFamilies/             the panels that host extension points
modules/common/            shared widgets, functions, Appearance, Config
modules/ii/                the extension hosts themselves (bar, sidebars, ...)
services/                  shared long-lived services
plugins/<id>/              one feature per folder, discovered at runtime
scripts/                   check and scaffold helpers
docs/                      this, plus PLUGINS.md
.agents/skills/            the plugin-authoring skill, for agents
```

## Core vs plugin

A feature belongs in `plugins/` unless something else has to reach into it. What is
left in `modules/ii/` is there because plugins extend it:

| Stays in core | Why |
| --- | --- |
| `bar`, `verticalBar` | host `barWidgets` |
| `background` | hosts `desktopWidgets` |
| `settings` | renders `settingsPages`, `settingsSections`, generated forms |
| `sidebarLeft`, `sidebarRight` | the panels bar widgets open onto; host `quickToggles` and `sidebarTabs` |

Everything else ships as a plugin — twenty of them, nineteen enabled by default:
`dock`, `overview`, `lock`, `overlay`, `polkit`, `region-selector`, `session-screen`,
`notification-popup`, `media-controls`, `on-screen-display`, `on-screen-keyboard`,
`screen-corners`, `screen-translator`, `wallpaper-selector`, `desktop-menu`,
`dropover`, `frame`, `material-you-colors`, `battery`, and `example-clock` as the
reference.

Nothing imports them and no file lists them: `PluginHost` instantiates whatever
`PluginRegistry` found on disk. Deleting a folder removes the feature; adding one adds
it.

## Built-ins are rows in the same tables plugins fill

The rule that shaped most of `core/`: **a host never enumerates its built-ins.** If a
host has a list of what ships with it, a plugin can never join that list, and the two
paths drift — the vertical bar had blacklisted `media` from the pill while the
horizontal bar had blacklisted `activeWindow`, and nobody could have noticed.

So each kind of thing has one registry holding built-ins and plugin contributions in
the same shape. A host reads one list and cannot tell which is which.

| Registry | Table of |
| --- | --- |
| `BarWidgetRegistry` | bar widgets: file, name, icon, pill preference, pill colour, repeatability |
| `DesktopWidgetRegistry` | desktop widgets: file, name, icon, where the enabled flag lives |
| `QuickToggleRegistry` | quick toggles: file per panel style, dialog, required compositor |
| `PanelRegistry` | every window the shell can open: whether it is open, its arguments, its exclusivity group |
| `SidebarTabRegistry` | left sidebar tabs, the shell's four included |
| `ContextMenuRegistry` | desktop right-click rows, as declarative verbs |
| `OsdRegistry` | on-screen displays |
| `PluginSearch` | launcher search providers |

This is what removed `AndroidToggleDelegateChooser.qml` (17 `DelegateChoice` branches
× 11 property assignments), a hardcoded 11-row widget list in `WidgetsSubmenu.qml`, a
19-entry duplicate in `BarConfig.qml`, a 167-line block of hand-written loaders in
`Background.qml`, two parallel arrays in `SidebarLeftContent.qml`, and roughly 290
references to named booleans on `GlobalStates`.

### Panels: from named booleans to a registry

The clearest case. Panel visibility was a singleton of booleans -
`GlobalStates.sidebarRightOpen`, `overviewOpen`, `launcherOpen`, twenty-odd of them -
and every panel, bar button, keybind, hot corner and context menu row named one
directly. A plugin could not add a panel to that list without editing core, and core
had to know each panel's name to close it.

`PanelRegistry` holds a row per panel with its open state, the arguments it was opened
with, and its group. Everything addresses panels by id:

```qml
PanelRegistry.toggle("sidebarRight")
PanelRegistry.open("desktopMenu", { x: mouseX, y: mouseY, screen: screen.name })
```

```bash
qs -c end4-pC ipc call panels toggle overview
```

Coordinates that used to be their own globals - `dropShelfX`, `desktopMenuY`,
`wallpaperSelectorTarget` - are now just arguments to `open()`, which is why they are
no longer core's business. Panels in the same group close each other, so the
six full-screen overlays stopped needing to close each other by name.

`GlobalStates` still exists, holding what is genuinely global session state: whether
the screen is locked, whether Super is held, which settings page is showing.

### The desktop menu has no branches left

Rows in `ContextMenuRegistry` are declarative verbs - `panel`, `ipc`, `exec`, `url`,
`entry` for a submenu - with `$menuX`, `$menuY` and `$screen` substituted at activation
and `badge` naming a `PluginBus` topic to display. The delegate that draws a row has
one code path, and a plugin's row and a built-in row are the same kind of object.

## What core/ contains

**Discovery and state**

| File | Does |
| --- | --- |
| `PluginRegistry` | finds plugins, parses manifests, tracks enabled/active/loaded, flattens `provides` |
| `PluginConfig` | per-plugin settings and widget state in `plugins.json` |
| `PluginManifest` | one manifest's FileView |
| `PluginHost` | instantiates services, panels, IPC and shortcuts at shell scope |
| `PluginLoader` | loads one plugin file, contained so a broken plugin logs instead of crashing |
| `PluginModuleAnchors` | statically imports every `qs.*` module plugin code imports |

`PluginModuleAnchors` is the non-obvious one. A `qs.foo` module only exists if
something statically imports it, and plugins are loaded dynamically — so without an
anchor a plugin's `import qs.modules.common.widgets` resolves at author time and fails
at runtime, most visibly on the lock screen. It must be complete, not minimal; there
are 25 imports in it.

**Base types plugins inherit** — `PluginBarWidget`, `PluginBackgroundWidget`,
`PluginPopup`, `PluginDrawer`, `PluginFloatingWindow`, `PluginHud`, `PluginRow`,
`PluginCard`, `PluginDesktopCard`, `PluginSeparator`, `PluginSettingRow`,
`PluginSettingsForm`, `PluginSections`, `PluginForm`, `PluginShortcut`, `PluginIpc`,
`PluginIconButton`, `PluginChip`, `PluginBadge`, `PluginTabs`, `PluginListView`,
`PluginSparkline`, `PluginGauge`, `PluginAppear`, `PluginTransition`,
`PluginSearchProvider`, `PluginSpectrum`, `PluginStore`, `PluginBusListener`,
`PluginFsWatch`, `PanelState`, and `Theme`, which is the whole theming API a plugin
needs. `core/api.json` is the generated catalogue of all of them; `scripts/api.sh
<name>` prints one.

**System facades** — the reason a plugin never has to shell out. `PluginSystem`
(CPU, memory, GPU, network, disks, read straight from `/proc` and `/sys`, once for
every reader), `PluginAudio`, `PluginMedia`, `PluginWM` (compositor-agnostic),
`PluginPower`, `PluginDisplay`, `PluginNetwork`, `PluginBluetooth`, `PluginPrivacy`,
`PluginNotifications`, `PluginApps`, `PluginDialogs`, `PluginFs`, `PluginTimer`,
`PluginStorage`, `PluginBus`, `PluginUtils`, `PluginHttp`, `PluginContext`.

Three of those exist because the obvious implementation was wrong rather than merely
missing. `PluginPrivacy` replaced a `Privacy.qml` that assigned arrays to `bool`
properties, so an empty list read as `true`. Its camera detection uses `fuser` on
`/dev/video*`, because an application that opens the device directly is invisible to
Pipewire. `PluginUtils.pipe` exists because the alternative - `bash -c` with a payload
interpolated into the string - was how the clipboard service handled arbitrary copied
text.

**The platform layer** — what a plugin gets without asking, added because every plugin was
reimplementing it:

| File | Does | The failure it replaces |
| --- | --- | --- |
| `PluginErrorBoundary` | loads plugin QML and draws the error in its place | a widget that fails to compile leaves a gap indistinguishable from "not configured" |
| `PluginIntent` | one addressable verb per plugin action, from the launcher, the CLI, a keybind or a peer plugin | plugins could not call each other at all - a plugin cannot import another plugin |
| `PluginIntentHandler` | implements one action, for when an IPC function is the wrong shape | — |
| `PluginHttp` | HTTP with a TTL cache, a timeout, real status codes and owner-scoped cancellation | `curl` in a `Process`, no cache, error pages parsed as data, callbacks writing to destroyed objects |
| `PluginToast` + `PluginToastHost` | one queue, one surface, above everything | a `Rectangle` and a `Timer` per plugin, drawn inside the popup the click had just closed |
| `PluginHistory` | one global undo stack, Ctrl+Z, and an Undo button in the toast | no undo anywhere |
| `PluginLifecycle` | `awake`/`animate`/`pollFactor` from `ext-idle-notify` and the battery | forty GIFs animating behind a lock screen |
| `PluginPermissions` | declared capabilities, shown before enabling and revocable after | nothing to read before trusting a plugin |
| `PluginContentView` | grid/list/detail with debounced search, keyboard navigation, hover actions, empty and loading states | ~200 lines per picker, each getting a different part wrong |
| `PluginProgressiveImage` | thumbnail then animation, decoded at draw size | blank cells for seconds, and full-size decodes in a 132 px grid |
| `PluginDropTarget`, `PluginDraggable` | drops with decoded paths; drags into other applications | `replace("file://", "")`, missing `decodeURIComponent`, highlights that stick |
| `PluginFX` + `PluginBackdropBlur`/`GlowBorder`/`MeshGradient` | effects, honest about what a Wayland client can sample | "acrylic" that is a flat fill |
| `PluginSurface` + `PluginResponsive` | one file per plugin, five surfaces | five files with five copies of the state logic |

`PluginIntent` is the one that changes what is possible rather than what is convenient.
Plugin QML is loaded from a URL, so its singletons are in no module another plugin can name -
which is why cross-plugin features were never written. An intent is a string, and a string
always resolves. An action also needs no handler object when the plugin already exposes an
IPC function of that name, so the common case is a manifest entry and nothing else.

**Theming** — `Theme` plus `Palette.js`, which generates a full Material 3 tonal
palette from one colour in CIELCh, so a plugin can theme itself from an album cover or
a wallpaper without the shell's colour pipeline being involved.

**Performance** — see below: `ComponentCache`, `Prewarm`, `Stable`, `Memo.js`, `Perf`.

`Memo.js` also holds the handle caches for `PluginStorage.of`, `.collection` and
`PluginUtils.as`. Those look like they belong in properties, and cannot be: each reads the
cache it also writes, and a QML property read-then-written inside one binding evaluation is a
dependency cycle - `readonly property var store: PluginStorage.of("x")`, the documented
usage, produced "Binding loop detected" and Qt dropped the binding.

**Command line** — `PluginCommands` provides the `plugins`, `panels`, `intent`, `history`,
`http` and `caps` IPC targets.

## What happens when you toggle a plugin

Worth following, because every step is there to keep the click cheap.

1. The GUI calls `PluginRegistry.setEnabled`, which writes `PluginConfig`.
2. `PluginConfig.mutate` copies on write **down the path being changed only**, so the
   other nineteen plugins' entries keep their object identity.
3. `data` changes; `syncBags` skips every plugin whose settings object is unchanged
   *by identity*, and for the rest assigns into a long-lived per-plugin object. A typed
   QML property assigned its current value notifies nobody, so only bindings reading
   the key that actually changed re-run.
4. `recomputeActive` updates `activeIds`; `activeSet` follows. Anything that only
   *reads* whether a plugin is on (bar, launcher, GUI) updates now, immediately.
5. `loadedIds` follows one frame later, so the frame that acknowledges the click gets
   painted before anything is built.
6. `PluginHost`'s `Instantiator`s are modelled on `installedPanels`/`installedServices`
   — lists that change only when a plugin appears or disappears **on disk**. The
   toggled plugin's `LazyLoader.activeAsync` flips; nothing else is touched.
7. The component is already compiled, because `Prewarm` did it between frames after
   startup. Only instantiation is left.

Measured in the running shell with the settings window open: worst stall 13–15 ms,
0% of wall blocked, for every plugin. Before this work, several took 350–390 ms and
one earlier revision froze for over a minute.

## The performance layer

Four things, each fixing a class of cost rather than an instance of it.

**`ComponentCache` + `Prewarm`.** Setting `Loader.source` compiles the file and then
instantiates it, and the compile is the expensive half. `ComponentCache` compiles off
the critical path via `Qt.createComponent(url, Component.Asynchronous)`, one file per
tick; because the engine caches compiled units per URL, a later `source: url` only
pays instantiation. `Prewarm` feeds it everything reachable from a manifest or a
built-in registry — 84 files. Anything new that is loaded by URL should be added there.

**`Stable` (over `Memo.js`).** QML decides whether to rebuild a Repeater or re-run a
binding by comparing an array's **identity**, never its contents. A derived list
recomputed because of an unrelated dependency therefore hands every consumer a new
array equal to the old one, and they all rebuild. `Stable.list(key, value)` returns
the previous array when the new one serialises identically. The state lives in a
`.pragma library` script, not in properties, because a memo reads what it writes and
doing that with QML properties inside a binding is a dependency cycle — Qt reports a
binding loop and drops a binding.

**Per-plugin settings objects.** `PluginConfig.of(id)` returns an object whose
properties are generated from the plugin's manifest schema. The alternative — one big
`effective` map — meant any write rebuilt every plugin's settings and handed everyone a
new object, at pointer rate while dragging a desktop widget.

**`Perf`.** A frame-stall profiler in the shell, off until asked:

```
qs -c end4-pC ipc call perf start "what I am about to do"
qs -c end4-pC ipc call perf report
```

A timer asked to fire every 8 ms cannot fire on time if the UI thread is busy, so the
gap between ticks is the block, with no instrumentation of the code being measured.
Gaps are bucketed rather than averaged, because a mean hides the one outlier a user
notices. This exists because two rounds of careful probe benchmarks put the cost of a
toggle at 13 ms while the shell plainly stuttered: a probe has no settings window open,
no compositor round trips for real layer-shell surfaces, and none of the GPU work of a
real frame. Measure the shell, not a model of it.

## Why this shape

Upstream merges are the constraint. A feature spliced into shared files conflicts every
time upstream edits those files; a feature in its own folder does not. So the core is
deliberately small and boring, and the interesting parts live where a merge cannot
reach them.

Three rules keep it that way:

1. **Nothing imports a plugin.** Plugins depend on core, never the reverse, and never
   on each other.
2. **Shared code goes in `modules/common/`,** not in whichever plugin needed it first.
3. **A host never enumerates built-ins.** They go in a registry, in the same shape as
   plugin contributions.

Rule 1 has two grandfathered exceptions, both one component wide: `plugins/lock` uses
`SysTray` from `qs.modules.ii.bar`, and `plugins/overlay` uses the volume mixer rows
from `qs.modules.ii.sidebarRight.volumeMixer`. Moving those two into
`modules/common/widgets/` would remove the last edges.

## Checks

`scripts/doctor.sh` is the entry point. It runs the others, and adds what only a *running*
shell can answer:

| Check | Why static analysis cannot do it |
| --- | --- |
| actions declared with no handler | resolution depends on which plugins are loaded and what registered |
| permissions used but not declared | observed at the call site, not visible in the source |
| singletons with no `qmldir` line | the file compiles; it just resolves to the type instead of the instance |
| `qs.*` modules a plugin imports but nothing anchors | the import is valid, it simply is not registered yet at load time |

That last pair is worth stating plainly: **a `pragma Singleton` file without a `qmldir`
entry still resolves.** Every call on it fails with `is not a function` and every property
reads `undefined`, with no warning anywhere, because a type reference to an uninstantiated
component is legal QML. `scripts/new-plugin.sh` now writes the `qmldir`, and the doctor
checks for it.

`scripts/check-qml.sh [subtree]` has ten phases and exits non-zero on any failure, so
it works as a pre-commit hook. The later phases exist because each caught a bug that
compiled cleanly:

| Phase | Finds |
| --- | --- |
| 1 | files whose imports or types do not resolve (610 files) |
| 2 | URL-loaded entry points that fail with only `shell.qml`'s imports (43) |
| 3 | singleton name clashes |
| 4 | singletons used without importing their module (111 singletons, every module) |
| 5 | uninitialised `required` properties in URL-loaded components |
| 6 | **runtime**: binding loops, and memoised lists that disagree with a fresh computation |
| 7 | `pragma Singleton` the scanner cannot reach |
| 8 | manifests that do not match `core/manifest.schema.json` |
| 9 | a stale `core/api.json` |
| 10 | **runtime**: errors logged with every panel open |

Phase 5 exists because a `required property` makes a component unconstructible, so a
`Loader` reports `Loader.Error` and draws nothing — invisible to phases 1–4, which only
compile. Phase 6 loads the registries with their real consumers in an invisible window,
because a dropped binding and a poisoned cache both compile perfectly.

Phase 7 exists because Quickshell's scanner stops looking for `pragma Singleton` at the
first `{` in the file — including one inside a comment — so a singleton with a header
comment above the pragma is silently not a singleton. Three files shipped that way.

Phase 10 is the newest and the widest: it launches the shell against a scratch config,
opens every panel in `PanelRegistry` plus the settings window, and fails on any
`ReferenceError`, `TypeError`, binding loop or failed load. It exists because all nine
static phases passed while the running shell logged two real defects — a function called
in one file and defined in another, and an assignment to a `Control`'s read-only
`mirrored` that `hasOwnProperty` had cleared. Both are the same shape: a name that
resolves at compile time and is wrong at run time.

Phase 4 originally checked only `core/` and `services/`; it now derives the module path
of every directory containing a singleton, which immediately found two missing
`qs.modules.common.functions` imports that would each have been a runtime
`ReferenceError`.

`scripts/check-icons.sh` validates every Material Symbol name against the installed
font by rendering it and measuring. An unknown ligature is not an error and draws no
placeholder — the font just renders the string, so `icon: "power_plug"` puts the word
PLUG in the UI at icon size. 378 names.

## Working on it

- Writing a plugin: [PLUGINS.md](PLUGINS.md). For agents:
  `.agents/skills/quickshell-plugins/`.
- `scripts/new-plugin.sh <id>` scaffolds one.
- `qs -c end4-pC ipc call plugins list` / `shortcuts` / `commands` to see what is
  registered.
- Pulling upstream in: merge `upstream/main` into this branch. Because features moved
  with `git mv`, rename detection follows upstream edits into `plugins/<id>/` on its
  own.
