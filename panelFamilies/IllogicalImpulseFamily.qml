// The illogical-impulse panel family: the parts of the shell that plugins
// extend rather than replace.
//
// Everything self-contained has moved to `plugins/` and is loaded by PluginHost.
// What is left hosts extension points: the bars host bar widgets, the background
// hosts desktop widgets, Settings hosts plugin pages, and the sidebars are the
// panels those widgets open onto.

import QtQuick
import Quickshell

import qs.modules.common
import qs.modules.ii.background
import qs.modules.ii.bar
import qs.modules.ii.settings
import qs.modules.ii.sidebarLeft
import qs.modules.ii.sidebarRight
import qs.modules.ii.verticalBar

Scope {
    PanelLoader { extraCondition: !Config.options.bar.vertical; component: Bar {} }
    PanelLoader { extraCondition: Config.options.bar.vertical; component: VerticalBar {} }
    PanelLoader { component: Background {} }
    PanelLoader { component: NiriBackdrop {} }
    PanelLoader { component: SidebarLeft {} }
    PanelLoader { component: SidebarRight {} }
    PanelLoader { component: Settings {} }
}
