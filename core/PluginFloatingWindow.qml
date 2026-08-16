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
    // windows belonging to one plugin.
    property string pluginId: ""
    property string windowId: "window"

    // Chrome.
    property string title: ""
    property string icon: ""
    property bool showTitleBar: true
    property bool showCloseButton: true

    // Extra buttons in the title bar, right of the title. Give it a Component of a Row or a
    // single item; PluginIconButton is the intended content.
    property Component actions: null

    property bool open: false

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

    function show(): void { root.open = true; }
    function hide(): void { root.open = false; }
    function toggle(): void { root.open = !root.open; }

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
            }
            margins {
                left: root.windowX
                top: root.windowY
            }

            implicitWidth: root.windowWidth
            implicitHeight: root.windowHeight

            Keys.onEscapePressed: if (root.closeOnEscape) root.open = false

            // Click-outside needs a surface covering the screen, which is a real cost, so it
            // exists only when asked for.
            HoverHandler {
                id: insideHover
            }

            Rectangle {
                id: frame
                anchors.fill: parent
                radius: Appearance.rounding.normal
                color: Theme.solid
                border.width: 1
                border.color: Theme.outlineFaint

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
                                onClicked: root.open = false
                            }
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: 1
                            color: Theme.outlineFaint
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

    // Click-outside dismissal, as its own transparent full-screen surface below the window.
    LazyLoader {
        activeAsync: root.open && root.closeOnClickOutside

        PanelWindow {
            visible: root.open && root.closeOnClickOutside
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: `quickshell:pluginWindowDismiss:${root.pluginId}`
            anchors { top: true; left: true; right: true; bottom: true }

            TapHandler {
                onTapped: root.open = false
            }
        }
    }
}
