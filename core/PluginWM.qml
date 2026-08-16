pragma Singleton

// Windows, workspaces and monitors, without caring which compositor is running.
//
//     PluginWM.activeWindow.title      // "README.md - Zed"
//     PluginWM.activeWindow.appId      // "dev.zed.Zed"
//     PluginWM.workspaces              // [{ id, name, active, occupied, windows }]
//     PluginWM.monitors                // [{ name, width, height, scale, focused }]
//     PluginWM.windows                 // [{ id, title, appId, workspaceId, focused, focus(), close() }]
//
//     PluginWM.focusWorkspace(3)
//     PluginWM.moveActiveToWorkspace(2)
//     PluginWM.closeActive()
//     PluginWM.onWorkspaceChanged: id => ...
//
// The active window comes from the Wayland foreign-toplevel protocol, so it is correct on
// Hyprland, Niri, Sway and river alike. Workspaces and per-window actions go through the
// shell's WM service, which has a backend per compositor. `PluginWM.compositor` says which
// one, and `supportsWorkspaces` says whether the concept exists at all - not every
// compositor has numbered workspaces, and a widget that assumes it does looks broken on
// the ones that do not.

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

Singleton {
    id: root

    readonly property string compositor: WM.compositor
    readonly property bool supportsWorkspaces: WM.workspaces.length > 0

    // ------------------------------------------------------------ active window

    readonly property Toplevel toplevel: ToplevelManager.activeToplevel

    readonly property QtObject activeWindow: QtObject {
        readonly property bool available: !!root.toplevel
        readonly property string title: root.toplevel?.title ?? ""
        readonly property string appId: root.toplevel?.appId ?? ""
        readonly property bool isFullscreen: root.toplevel?.fullscreen ?? false
        readonly property bool isMaximized: root.toplevel?.maximized ?? false
        readonly property bool isActivated: root.toplevel?.activated ?? false
    }

    // ------------------------------------------------------------------ lists

    // [{ id, title, appId, workspaceId, focused, focus(), close() }]
    readonly property var windows: WM.windowList.map(window => ({
        id: window.id,
        address: window.address,
        title: window.title ?? "",
        appId: window.appId ?? "",
        workspaceId: window.workspaceId ?? -1,
        focused: window.focused === true,
        focus: () => WM.focusWindow(window.id),
        close: () => WM.closeWindow(window.id)
    }))

    // [{ id, name, active, occupied, windows, focus() }]
    readonly property var workspaces: WM.workspaces.map(workspace => ({
        id: workspace.id,
        name: `${workspace.name ?? workspace.id}`,
        active: workspace.id === root.activeWorkspaceId,
        occupied: root.windows.some(window => window.workspaceId === workspace.id),
        windows: root.windows.filter(window => window.workspaceId === workspace.id),
        focus: () => WM.switchWorkspace(workspace.id)
    }))

    readonly property int activeWorkspaceId: WM.activeWorkspace?.id ?? -1
    readonly property string activeWorkspaceName: `${WM.activeWorkspace?.name ?? ""}`

    // [{ name, width, height, scale, focused, x, y, screen }]
    readonly property var monitors: Quickshell.screens.map(screen => {
        const info = WM.monitorFor(screen);
        return {
            name: screen.name,
            width: screen.width,
            height: screen.height,
            scale: info?.scale ?? 1,
            x: info?.x ?? screen.x,
            y: info?.y ?? screen.y,
            focused: WM.focusedMonitor?.name === screen.name,
            screen: screen
        };
    })

    readonly property var focusedMonitor: root.monitors.find(monitor => monitor.focused) ?? root.monitors[0] ?? null

    // --------------------------------------------------------------- control

    function focusWorkspace(id: int): void {
        WM.switchWorkspace(id);
    }

    function nextWorkspace(): void {
        WM.switchWorkspaceRelative(1);
    }

    function previousWorkspace(): void {
        WM.switchWorkspaceRelative(-1);
    }

    function focusWindow(id: var): void {
        WM.focusWindow(id);
    }

    function closeWindow(id: var): void {
        WM.closeWindow(id);
    }

    function closeActive(): void {
        const focused = root.windows.find(window => window.focused);
        if (focused)
            WM.closeWindow(focused.id);
    }

    function moveWindowToWorkspace(id: var, workspaceId: int): void {
        WM.moveWindowToWorkspace(id, workspaceId);
    }

    function moveActiveToWorkspace(workspaceId: int): void {
        const focused = root.windows.find(window => window.focused);
        if (focused)
            WM.moveWindowToWorkspace(focused.id, workspaceId);
    }

    // Geometry of the monitor a QML item's window is on, in compositor coordinates.
    function monitorGeometry(screen: var): var {
        return WM.monitorGeometry(screen);
    }

    function isFullscreenOn(monitorName: string): bool {
        return WM.fullscreenOnMonitor(monitorName);
    }

    // ---------------------------------------------------------------- signals

    signal workspaceChanged(int workspaceId)

    // Not `activeWindowChanged`: `activeWindow` is a property, so QML already generates a
    // change signal by that name and declaring it again is a hard error at load time.
    signal windowFocused(string appId, string title)

    onActiveWorkspaceIdChanged: root.workspaceChanged(root.activeWorkspaceId)
    onToplevelChanged: root.windowFocused(root.activeWindow.appId, root.activeWindow.title)

    // Also on the bus, so a plugin can react without holding a reference to this singleton
    // and without a Connections block.
    onWorkspaceChanged: PluginBus.publish("wm:workspace", { id: root.activeWorkspaceId, name: root.activeWorkspaceName })
    onWindowFocused: PluginBus.publish("wm:activeWindow", { appId: root.activeWindow.appId, title: root.activeWindow.title })
}
