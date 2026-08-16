// One panel's open state, as a declarative object.
//
//     PanelState {
//         id: panel
//         panel: "overview"
//         onOpenChanged: if (open) searchField.forceActiveFocus()
//     }
//
//     PanelWindow { visible: panel.open }
//
// The same thing as `PanelRegistry.state(id)` with a nicer shape: `open` and `args` as plain
// properties, `show()`/`hide()`/`toggle()` for acting on it, and `opened`/`closed` signals for the
// common "do something when it appears" case.
//
// Binding to this rather than to PanelRegistry itself keeps the dependency narrow: it changes when
// this one panel changes, not when any panel does.

import QtQuick
import qs.core

QtObject {
    id: root

    // Panel id, as declared in a manifest or by PanelRegistry's built-ins.
    property string panel: ""

    readonly property var state: PanelRegistry.state(root.panel)

    readonly property bool open: root.state?.open ?? false

    // Whatever open() was called with. `{}` when opened without arguments.
    readonly property var args: root.state?.args ?? ({})

    // When it was last opened, as a millisecond timestamp - for a panel that behaves differently
    // if it was just shown.
    readonly property real openedAt: root.state?.at ?? 0

    signal opened(var args)
    signal closed

    function show(args: var): void { PanelRegistry.open(root.panel, args); }
    function hide(): void { PanelRegistry.close(root.panel); }
    function toggle(args: var): void { PanelRegistry.toggle(root.panel, args); }

    onOpenChanged: root.open ? root.opened(root.args) : root.closed()
}
