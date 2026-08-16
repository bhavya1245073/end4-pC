// Base type for a plugin's desktop widget.
//
// Mirrors the built-in AbstractBackgroundWidget, except that position and
// visibility live in plugins.json instead of the shell's config.json (a
// JsonAdapter would drop keys belonging to plugins that aren't installed).
//
// Usage, from plugins/<id>/MyWidget.qml:
//
//     PluginBackgroundWidget {
//         pluginId: "my-plugin"
//         widgetId: "myWidget"
//         implicitWidth: 300
//         implicitHeight: 160
//         StyledText { anchors.centerIn: parent; text: "hi" }
//     }
//
// Screen geometry defaults to the canvas the widget was dropped on, so nothing
// needs to be injected by the loader.

import QtQuick
import qs
import qs.modules.common
import qs.modules.common.widgets.widgetCanvas

AbstractWidget {
    id: root

    required property string pluginId
    required property string widgetId

    // The canvas, not `parent`: the parent is the Loader that fetched this file, and a
    // Loader takes its size from the item inside it, so `parent.width` is this widget's
    // own width. Clamping a stored position against that gives zero every time.
    readonly property real screenWidth: root.canvas?.width ?? 0
    readonly property real screenHeight: root.canvas?.height ?? 0
    readonly property real scaledScreenWidth: root.screenWidth
    readonly property real scaledScreenHeight: root.screenHeight
    readonly property real wallpaperScale: 1

    // Convenience for plugin authors: `settings.mySetting`.
    readonly property var settings: PluginConfig.of(root.pluginId)

    property bool visibleWhenLocked: Config.options.lock.showWidgets

    // Legible over the wallpaper as long as the widget draws some backing of its
    // own (see the example plugin). Override it if yours doesn't.
    property color colText: Appearance.colors.colOnLayer0

    readonly property real storedX: PluginConfig.widgetValue(root.pluginId, root.widgetId, "x", 0)
    readonly property real storedY: PluginConfig.widgetValue(root.pluginId, root.widgetId, "y", 0)

    property real targetX: Math.max(0, Math.min(root.storedX, root.scaledScreenWidth - root.width))
    property real targetY: Math.max(0, Math.min(root.storedY, root.scaledScreenHeight - root.height))

    x: root.targetX
    y: root.targetY

    draggable: !Config.options.background.widgetsLocked

    visible: opacity > 0
    opacity: (GlobalStates.screenLocked && !root.visibleWhenLocked) ? 0 : 1
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    scale: (root.draggable && root.containsPress) ? 1.05 : 1
    Behavior on scale {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }

    // AbstractWidget drags by assigning x/y directly, which clobbers the
    // bindings above; restore them once the new position is stored.
    onReleased: {
        PluginConfig.setWidgetValue(root.pluginId, root.widgetId, "x", root.x);
        PluginConfig.setWidgetValue(root.pluginId, root.widgetId, "y", root.y);
        root.x = Qt.binding(() => root.targetX);
        root.y = Qt.binding(() => root.targetY);
    }
}
