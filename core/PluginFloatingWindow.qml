// A movable, resizable floating window for a plugin, with geometry that survives a restart.
//
//     PluginFloatingWindow {
//         pluginId: "calculator"
//         windowId: "main"
//         title: "Calculator"
//         icon: "calculate"
//         width: 320
//         height: 420
//
//         CalculatorKeypad { anchors.fill: parent }
//     }
//
// You get: a title bar that drags the window, a corner grip that resizes it, close on Escape
// and on click-outside (both switchable), clamping to the screen, and width/height/x/y
// remembered in plugins.json under this `windowId`. Children go into the content area below
// the title bar.
//
// It is a layer-shell surface, not a real toplevel: a Wayland shell cannot create a normal
// window, so this floats above the desktop and is not in the window switcher. That is what
// makes it right for a calculator or a scratchpad and wrong for a text editor.
//
// `open` is the property to bind or toggle. A closed window keeps no surface and no timers,
// so leaving one declared costs nothing.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    // Identity. `pluginId` is what plugins.json is keyed on, `windowId` distinguishes several
    // windows belonging to one plugin, `panelId` is the PanelRegistry id it answers to (defaults to
    // `pluginId`, which is what you want unless one plugin owns several addressable windows).
    property string pluginId: ""
    property string windowId: "window"
    property string panelId: root.pluginId

    // Chrome.
    property string title: ""
    property string icon: ""
    property bool showTitleBar: true
    property bool showCloseButton: true

    // Extra buttons in the title bar, right of the title. Give it a Component of a Row or a
    // single item; PluginIconButton is the intended content.
    property Component actions: null

    // Whether the window is up. Derived, never assigned: the registry is the single source of truth.
    //
    // It has to be. A panel is opened by a keybind, by `qs ipc`, by a launcher action, by a context
    // menu and by the plugin itself, and PanelRegistry is the only thing that hears all of them. A
    // window keeping its own copy of "am I open" falls out of step with the first route it does not
    // hear about - and then toggling it works on every other press, because the registry and the
    // window disagree about which way the toggle should go.
    //
    // Route writes through show()/hide()/toggle(). Assigning `open` cannot desync it, because there
    // is nothing to assign.
    readonly property bool open: root.addressable ? panelBinding.open : root.localOpen

    // Why the panel was opened, when it was opened through the registry: PanelRegistry.open(id, args)
    // args, `{}` otherwise. Lets one window serve several entry points.
    readonly property var openArgs: panelBinding.args

    readonly property bool addressable: root.panelId.length > 0

    // The declarative half of PanelRegistry: `open`/`args` tracked as bindings, no signal handlers.
    PanelState {
        id: panelBinding
        panel: root.panelId
    }

    // Fallback for a window with no pluginId and no panelId. It works, but nothing outside the
    // plugin can reach it - see the warning in Component.onCompleted below.
    property bool localOpen: false

    // Behaviour.
    property bool closeOnEscape: true
    property bool closeOnClickOutside: false
    property bool resizable: true
    property bool draggable: true
    property bool rememberGeometry: true

    // Size limits, honoured by dragging and by the stored geometry.
    property real minimumWidth: 180
    property real minimumHeight: 120
    property real maximumWidth: 3000
    property real maximumHeight: 2000

    // Where it goes the first time, before the user has moved it. "center", "top-left",
    // "top-right", "bottom-left", "bottom-right", or "cursor".
    property string initialPosition: "center"

    // Live geometry. Assigning these moves and resizes the window.
    property real windowX: 0
    property real windowY: 0
    property real windowWidth: 320
    property real windowHeight: 240

    // Kept for API symmetry with plain Items, so `width: 400` in a declaration does the
    // expected thing.
    onWidthChanged: if (root.width > 0) root.windowWidth = root.width
    onHeightChanged: if (root.height > 0) root.windowHeight = root.height

    signal opened
    signal closed

    // Content goes here. Declared as a Component so it can live inside the lazily-created
    // window: QML wraps a child object into a Component automatically for a Component-typed
    // property, so a plugin still just writes its content as a child.
    default property Component content: null

    function show(): void {
        if (root.addressable)
            PanelRegistry.open(root.panelId, ({}));
        else
            root.localOpen = true;
    }

    function hide(): void {
        if (root.addressable)
            PanelRegistry.close(root.panelId);
        else
            root.localOpen = false;
    }

    function toggle(): void {
        if (root.addressable)
            PanelRegistry.toggle(root.panelId, ({}));
        else
            root.localOpen = !root.localOpen;
    }

    // Puts the window back where `initialPosition` says, forgetting the stored position.
    function resetGeometry(): void {
        PluginConfig.setWidgetValue(root.pluginId, root.__stateKey, "x", undefined);
        PluginConfig.setWidgetValue(root.pluginId, root.__stateKey, "y", undefined);
        root.__placed = false;
        root.__place();
    }

    readonly property string __stateKey: `window:${root.windowId}`
    property bool __placed: false

    // ---------------------------------------------------------------- geometry

    function __place(): void {
        const screen = Quickshell.screens.find(candidate => candidate.name === (PluginWM.focusedMonitor?.name ?? "")) ?? Quickshell.screens[0];
        if (!screen)
            return;

        if (root.rememberGeometry) {
            const storedWidth = PluginConfig.widgetValue(root.pluginId, root.__stateKey, "w", undefined);
            const storedHeight = PluginConfig.widgetValue(root.pluginId, root.__stateKey, "h", undefined);
            if (storedWidth !== undefined)
                root.windowWidth = Math.max(root.minimumWidth, Math.min(root.maximumWidth, storedWidth));
            if (storedHeight !== undefined)
                root.windowHeight = Math.max(root.minimumHeight, Math.min(root.maximumHeight, storedHeight));

            const storedX = PluginConfig.widgetValue(root.pluginId, root.__stateKey, "x", undefined);
            const storedY = PluginConfig.widgetValue(root.pluginId, root.__stateKey, "y", undefined);
            if (storedX !== undefined && storedY !== undefined) {
                // Clamped on restore: a window remembered on a monitor that is no longer
                // attached would otherwise be positioned off-screen and unreachable.
                root.windowX = Math.max(0, Math.min(screen.width - root.windowWidth, storedX));
                root.windowY = Math.max(0, Math.min(screen.height - root.windowHeight, storedY));
                root.__placed = true;
                return;
            }
        }

        const margin = 40;
        switch (root.initialPosition) {
        case "top-left":
            root.windowX = margin;
            root.windowY = margin;
            break;
        case "top-right":
            root.windowX = screen.width - root.windowWidth - margin;
            root.windowY = margin;
            break;
        case "bottom-left":
            root.windowX = margin;
            root.windowY = screen.height - root.windowHeight - margin;
            break;
        case "bottom-right":
            root.windowX = screen.width - root.windowWidth - margin;
            root.windowY = screen.height - root.windowHeight - margin;
            break;
        default:
            root.windowX = (screen.width - root.windowWidth) / 2;
            root.windowY = (screen.height - root.windowHeight) / 2;
            break;
        }
        root.__placed = true;
    }

    function __persist(): void {
        if (!root.rememberGeometry || !root.pluginId)
            return;
        PluginConfig.setWidgetValue(root.pluginId, root.__stateKey, "x", Math.round(root.windowX));
        PluginConfig.setWidgetValue(root.pluginId, root.__stateKey, "y", Math.round(root.windowY));
        PluginConfig.setWidgetValue(root.pluginId, root.__stateKey, "w", Math.round(root.windowWidth));
        PluginConfig.setWidgetValue(root.pluginId, root.__stateKey, "h", Math.round(root.windowHeight));
    }

    // Dragging emits a position per pointer move; writing plugins.json at pointer rate would
    // serialise the whole file dozens of times a second.
    Timer {
        id: persistTimer
        interval: 250
        onTriggered: root.__persist()
    }

    onWindowXChanged: if (root.__placed) persistTimer.restart()
    onWindowYChanged: if (root.__placed) persistTimer.restart()
    onWindowWidthChanged: if (root.__placed) persistTimer.restart()
    onWindowHeightChanged: if (root.__placed) persistTimer.restart()

    onOpenChanged: {
        if (root.open) {
            if (!root.__placed)
                root.__place();
            root.opened();
        } else {
            root.closed();
        }
    }

    Component.onCompleted: {
        if (PluginConfig.loaded)
            root.__place();

        if (!root.addressable)
            console.warn(`[pluginWindow] a PluginFloatingWindow titled "${root.title}" has no pluginId`
                + ` or panelId: show()/hide() work, but no keybind, IPC call, launcher action or`
                + ` PanelRegistry.toggle() can reach it, and its position will not be remembered.`);
    }

    // plugins.json arrives asynchronously; a window opened before it lands must still end up
    // where the user left it.
    Connections {
        target: PluginConfig
        function onLoadedChanged(): void {
            if (PluginConfig.loaded && !root.__placed)
                root.__place();
        }
    }

    // ------------------------------------------------------------------ surface

    LazyLoader {
        activeAsync: root.open

        PanelWindow {
            id: panel

            visible: root.open
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: `quickshell:pluginWindow:${root.pluginId}:${root.windowId}`
            // Keyboard focus on demand: a floating window that steals focus while it is merely
            // visible makes typing anywhere else impossible.
            WlrLayershell.keyboardFocus: root.closeOnEscape ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

            anchors {
                top: true
                left: true
                right: true
                bottom: true
            }

            // The surface covers the screen and the card is positioned *inside* it, rather than
            // the surface being card-sized and moved with layer-shell margins.
            //
            // Margins are protocol state: every change is a configure round-trip through the
            // compositor, so a window dragged that way is always at least a frame behind the
            // pointer and visibly rubber-bands on a busy frame. Moving an Item within an
            // already-mapped surface is client-side and lands in the same frame as the pointer
            // event that caused it. Resizing has the same problem and the same fix.
            //
            // The cost is one full-screen transparent surface per open window, which is why it is
            // behind a LazyLoader keyed on `open`.

            // Input only where the card is, so the desktop and the applications under the rest of
            // the surface stay clickable. `Region { item: frame }` is the whole card; no mask at
            // all means the whole screen, which is what click-outside dismissal needs.
            //
            // Not `Region { item: null }` for that case - an empty region accepts nothing, so the
            // window would take no clicks whatsoever.
            mask: root.closeOnClickOutside ? null : cardRegion

            Region {
                id: cardRegion
                item: frame
            }

            // Click-outside dismissal, when asked for. On the same surface rather than a second
            // one below it: two surfaces meant two configure sequences and an ordering the
            // compositor was free to interleave.
            TapHandler {
                enabled: root.closeOnClickOutside
                onTapped: root.hide()
            }

            // Click-outside needs a surface covering the screen, which is a real cost, so it
            // exists only when asked for.
            HoverHandler {
                id: insideHover
            }

            // A real shadow, now that the card no longer fills its surface: it lifts the window
            // off whatever application is behind it.
            StyledRectangularShadow {
                target: frame
            }

            Rectangle {
                id: frame
                x: root.windowX
                y: root.windowY
                width: root.windowWidth
                height: root.windowHeight
                radius: Appearance.rounding.normal
                color: Theme.solid
                border.width: 1
                border.color: Theme.fade(Theme.outline, 0.25)
                focus: true
                Keys.onEscapePressed: if (root.closeOnEscape) root.hide()

                // Swallows clicks that land on the card but miss everything in it, so a click on
                // the card's own padding does not fall through to the dismiss handler behind it.
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 0
                    spacing: 0

                    // ---------------------------------------------------------- title bar
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.showTitleBar ? 38 : 0
                        visible: root.showTitleBar

                        // Dragging moves the window by changing its margins. Deltas are taken
                        // in screen space so the pointer stays on the same pixel of the bar
                        // rather than drifting as the window catches up.
                        DragHandler {
                            id: dragHandler
                            enabled: root.draggable
                            target: null
                            property real startX: 0
                            property real startY: 0
                            onActiveChanged: {
                                if (active) {
                                    startX = root.windowX;
                                    startY = root.windowY;
                                }
                            }
                            onTranslationChanged: {
                                if (!active)
                                    return;
                                const screen = panel.screen;
                                root.windowX = Math.max(0, Math.min((screen?.width ?? 4000) - root.windowWidth, startX + translation.x));
                                root.windowY = Math.max(0, Math.min((screen?.height ?? 3000) - root.windowHeight, startY + translation.y));
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.pad.l
                            anchors.rightMargin: Theme.pad.s
                            spacing: Theme.pad.s

                            MaterialSymbol {
                                visible: root.icon.length > 0
                                text: root.icon
                                iconSize: Theme.font.l
                                color: Theme.accent
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: root.title
                                font.pixelSize: Theme.font.m
                                font.weight: Font.DemiBold
                                color: Theme.text
                                elide: Text.ElideRight
                            }

                            Loader {
                                sourceComponent: root.actions
                            }

                            PluginIconButton {
                                visible: root.showCloseButton
                                icon: "close"
                                tooltip: qsTr("Close")
                                onClicked: root.hide()
                            }
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: 1
                            color: Theme.fade(Theme.outline, 0.25)
                        }
                    }

                    // ------------------------------------------------------------ content
                    Loader {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        sourceComponent: root.content
                    }
                }

                // ------------------------------------------------------------- resize grip
                Item {
                    visible: root.resizable
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    width: 18
                    height: 18

                    DragHandler {
                        target: null
                        property real startWidth: 0
                        property real startHeight: 0
                        onActiveChanged: {
                            if (active) {
                                startWidth = root.windowWidth;
                                startHeight = root.windowHeight;
                            }
                        }
                        onTranslationChanged: {
                            if (!active)
                                return;
                            root.windowWidth = Math.max(root.minimumWidth, Math.min(root.maximumWidth, startWidth + translation.x));
                            root.windowHeight = Math.max(root.minimumHeight, Math.min(root.maximumHeight, startHeight + translation.y));
                        }
                    }

                    Canvas {
                        anchors.fill: parent
                        onPaint: {
                            const context = getContext("2d");
                            context.reset();
                            context.strokeStyle = Theme.textFaint;
                            context.lineWidth = 1;
                            // Three short diagonals, the conventional grip.
                            for (const offset of [4, 8, 12]) {
                                context.beginPath();
                                context.moveTo(width - offset, height - 2);
                                context.lineTo(width - 2, height - offset);
                                context.stroke();
                            }
                        }
                    }

                    HoverHandler {
                        cursorShape: Qt.SizeFDiagCursor
                    }
                }
            }
        }
    }

    // Click-outside dismissal now lives on the window's own surface - see the `mask` above - so
    // there is no second surface to keep in step with the first.
}
