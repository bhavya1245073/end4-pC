import QtQuick
import Quickshell
import qs.modules.common

/*
 * Widget to be placed on a WidgetCanvas
 */
MouseArea {
    id: root
    property alias animateXPos: xBehavior.enabled
    property alias animateYPos: yBehavior.enabled
    property bool draggable: true
    property int gridSize: 12
    property bool snapEnabled: true
    readonly property bool dragging: drag.active

    acceptedButtons: Qt.LeftButton | Qt.RightButton
    drag.target: draggable ? dragProxy : undefined
    cursorShape: (draggable && containsPress) ? Qt.ClosedHandCursor : draggable ? Qt.OpenHandCursor : Qt.ArrowCursor

    onClicked: (mouse) => {
        if (mouse.button === Qt.RightButton) {
            Config.options.background.widgetsLocked = !Config.options.background.widgetsLocked
        }
    }

    function center() {
        root.x = (root.parent.width - root.width) / 2
        root.y = (root.parent.height - root.height) / 2
    }

    function snap(value) {
        return Math.round(value / root.gridSize) * root.gridSize
    }

    function findCanvas(item) {
        var p = item
        while (p) {
            if (p.isWidgetCanvas === true) return p
            p = p.parent
        }
        return null
    }

    // The canvas this widget lives on, for subclasses that need its size.
    //
    // Resolved rather than assumed to be `parent`: widgets are loaded through a Loader,
    // and a Loader takes its size from the item inside it, so `parent.width` is the
    // widget's own width. Anything clamping a position against it therefore clamps to
    // zero, which pins every widget to the top-left corner and makes dragging snap
    // straight back.
    //
    // Resolved on completion because the walk needs the whole chain to exist, and
    // `root.parent` does not change when the Loader above it gets parented, so a plain
    // binding on `parent` would never re-evaluate.
    property var canvas: null

    function resolveCanvas() {
        root.canvas = root.findCanvas(root.parent)
    }

    onParentChanged: root.resolveCanvas()
    Component.onCompleted: root.resolveCanvas()

    function updateCenterHighlight() {
        var canvas = findCanvas(root.parent)
        if (!canvas) return
        var widgetCenterX = dragProxy.x + root.width / 2
        var widgetCenterY = dragProxy.y + root.height / 2
        var threshold = root.gridSize
        var nearX = Math.abs(widgetCenterX - canvas.width / 2) < threshold
        var nearY = Math.abs(widgetCenterY - canvas.height / 2) < threshold
        canvas.setCenterActive(nearX, nearY)
    }

    Item {
        id: dragProxy
        parent: root.parent
        x: root.x
        y: root.y

        onXChanged: if (root.dragging) root.updateCenterHighlight()
        onYChanged: if (root.dragging) root.updateCenterHighlight()
    }

    Binding {
        target: root
        property: "x"
        value: root.snapEnabled ? root.snap(dragProxy.x) : dragProxy.x
        when: root.dragging
        restoreMode: Binding.RestoreNone
    }
    Binding {
        target: root
        property: "y"
        value: root.snapEnabled ? root.snap(dragProxy.y) : dragProxy.y
        when: root.dragging
        restoreMode: Binding.RestoreNone
    }

    onDraggingChanged: {
        var canvas = findCanvas(root.parent)
        if (canvas) canvas.setDragging(dragging)

        if (!dragging && canvas) {
            var left = root.x
            var right = root.x + root.width
            var top = root.y
            var bottom = root.y + root.height
            var verticalLines = [left, right]
            var horizontalLines = [top, bottom]

            var widgetCenterX = root.x + root.width / 2
            var widgetCenterY = root.y + root.height / 2
            if (Math.abs(widgetCenterX - canvas.width / 2) < root.gridSize / 2)
                verticalLines.push(canvas.width / 2)
            if (Math.abs(widgetCenterY - canvas.height / 2) < root.gridSize / 2)
                horizontalLines.push(canvas.height / 2)

            if (Config.options.background.showSnapLines)
                canvas.flashLines(verticalLines, horizontalLines)
        }

        dragProxy.x = root.x
        dragProxy.y = root.y
    }

    Behavior on x {
        id: xBehavior
        enabled: !root.dragging
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    Behavior on y {
        id: yBehavior
        enabled: !root.dragging
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
}