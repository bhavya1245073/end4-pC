# How this fork is put together

Upstream is one large QML tree where every panel is wired in by hand. This fork
splits it into a **core** that provides infrastructure and extension points, and
**plugins** that provide features.

```
shell.qml                  bootstrap; loads the panel family + PluginHost
core/                      the plugin system: registry, config, base types
panelFamilies/             the panels that host extension points
modules/common/            shared widgets, functions, Appearance, Config
modules/ii/                the extension hosts themselves (bar, sidebars, ...)
services/                  shared long-lived services
plugins/<id>/              one feature per folder, discovered at runtime
scripts/                   shell/python helpers
```

## Core vs plugin

A feature belongs in `plugins/` unless something else has to reach into it.
What is left in `modules/ii/` is there because plugins extend it:

| Stays in core | Why |
| --- | --- |
| `bar`, `verticalBar` | host `barWidgets` from plugins |
| `background` | hosts `desktopWidgets` from plugins |
| `settings` | renders `settingsPages` and the generated plugin forms |
| `sidebarLeft`, `sidebarRight` | the panels bar widgets open onto |

Everything else ships as a plugin: `dock`, `overview`, `lock`, `overlay`,
`polkit`, `region-selector`, `session-screen`, `notification-popup`,
`media-controls`, `on-screen-display`, `on-screen-keyboard`, `screen-corners`,
`screen-translator`, `wallpaper-selector`, `desktop-menu`, `dropover`, `frame`,
`material-you-colors`.

Each is a folder with a `manifest.json` declaring `provides.panels`. Nothing
imports them and no file lists them — `PluginHost` loads whatever
`PluginRegistry` found on disk. Deleting a plugin folder removes the feature;
adding one adds it.

The stock panels keep their existing pages under **Settings**, reading
`Config.options.*` as before. Their manifests declare no `settings` schema: the
generated form under **Settings → Plugins** is for plugins that don't have a
hand-written page.

## Why this shape

Upstream merges are the constraint. A feature spliced into shared files
conflicts every time upstream edits those files; a feature in its own folder
does not. So the core is deliberately small and boring, and the interesting
parts live where a merge can't reach them.

Two rules keep it that way:

1. **Nothing imports a plugin.** Plugins depend on core, never the reverse, and
   never on each other.
2. **Shared code goes in `modules/common/`,** not in whichever plugin needed it
   first.

Rule 1 has two grandfathered exceptions, both one component wide:
`plugins/lock` uses `SysTray` from `qs.modules.ii.bar`, and `plugins/overlay`
uses the volume mixer rows from `qs.modules.ii.sidebarRight.volumeMixer`. Moving
those two components into `modules/common/widgets/` would remove the last edges.

## Working on it

- Writing a plugin: [PLUGINS.md](PLUGINS.md).
- `scripts/new-plugin.sh <id>` scaffolds one.
- `scripts/check-qml.sh [subtree]` compiles every QML file in the tree and
  reports the ones whose imports or types do not resolve. It exits non-zero if
  anything failed, so it works as a pre-commit hook. A clean tree reports
  `failures=0`; if you see a wall of "module ... is not installed", read the
  comment at the top of the script.
- Pulling upstream in: merge `upstream/main` into this branch. Because features
  moved with `git mv`, rename detection follows upstream edits into
  `plugins/<id>/` on its own.
