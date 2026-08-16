// Makes the `qs.*` modules that plugins import resolvable from plugin code.
//
// This exists because of how the QML engine registers Quickshell's `qs.` modules.
// A `qs.foo.bar` module comes into existence when the engine *compiles* an
// `import qs.foo.bar` statement. Every file reachable by static imports from
// shell.qml is compiled up front, so those modules all get registered before
// anything runs.
//
// Plugins are not reachable that way. They are discovered on disk at runtime and
// loaded from a URL, so their import statements are compiled far too late to
// register anything. A module that *only* a plugin imports is therefore never
// registered, and the plugin fails to load with:
//
//     module "qs.modules.common.panels.lock" is not installed
//
// which is how the lock screen quietly stopped binding to Super+L: nothing in the
// core shell imports `qs.modules.common.panels.lock`, only `plugins/lock` does.
//
// Importing them here fixes it for every plugin at once, because this file *is*
// in the static graph - PluginHost instantiates it. Imports of modules that are
// already registered are harmless no-ops, so the list does not have to be minimal;
// it has to be complete. `scripts/check-plugin-modules.sh` enforces that, and
// fails if a plugin imports something this file has not anchored.
//
// Nothing here is instantiated. The imports are the entire point.

import QtQml

// KEEP IN SYNC: every qs.* module imported anywhere under plugins/.
import qs.core
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.models
import qs.modules.common.models.gCloud
import qs.modules.common.panels.lock
import qs.modules.common.utils
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.ii.bar
import qs.modules.ii.sidebarRight.volumeMixer
import qs.services

QtObject {}
