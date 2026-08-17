// Makes its content draggable into other applications.
//
// Dragging a file out of a shell widget into Discord, Firefox or a file manager needs
// `Drag.active`, `Drag.dragType`, `Drag.mimeData`, `Drag.supportedActions`, an image to drag,
// a threshold so a click is not a drag, and a cursor that changes - and the widget has to keep
// working as a button. Getting that combination right is why almost nothing in a shell can be
// dragged out.
//
//     PluginDraggable {
//         path: item.filePath           // a file: the usual case
//         onClicked: open(item)
//
//         Image { source: item.thumbnail }
//     }
//
// Or text, or both:
//
//     PluginDraggable { text: quote.body }
//
// ## The drag image is the widget itself
//
// Rendered with grabToImage at drag start, so what the user drags is what they were looking
// at. Without it the drag shows nothing under the cursor, which reads as "the drag did not
// start" and makes people let go.
//
// ## Why a threshold matters
//
// Without one, a drag starts on any press and the widget stops being clickable - two pixels of
// pointer travel during a click is normal. `Drag.active` is therefore driven by the drag
// handler's own threshold rather than by press state.

import QtQuick
import qs.core
import qs.modules.common

Item {
    id: root

    // What to drag. A path is offered as a file URI (what file managers and chat apps want);
    // text is offered as text/plain. Both may be set - the receiver picks.
    property string path: ""
    property string text: ""

    // Extra MIME data for plugin-to-plugin drags: { "application/x-my-thing": "payload" }
    property var mimeData: ({})

    property bool enabled: true

    // What the content is. Defaults to the first child, which is the common case.
    default property alias content: contentHolder.data

    readonly property bool dragging: dragArea.drag.active

    signal clicked();
    signal dragStarted();
    signal dragFinished();

    implicitWidth: childrenRect.width
    implicitHeight: childrenRect.height

    Item {
        id: contentHolder
        anchors.fill: parent
    }

    Item {
        id: payload

        // The dragged item is this proxy, not the content: dragging the content itself moves it
        // out of the layout it lives in, and a RowLayout child that has been moved never goes
        // back - the layout keeps its stale position. A zero-size proxy has nothing to corrupt.
        anchors.fill: parent

        Drag.active: dragArea.drag.active
        // Automatic is what crosses the process boundary into other applications; Internal only
        // moves things within this QML scene.
        Drag.dragType: Drag.Automatic
        Drag.supportedActions: Qt.CopyAction
        Drag.mimeData: {
            const data = Object.assign({}, root.mimeData ?? {});
            if (root.path.length > 0)
                data["text/uri-list"] = root.__uriOf(root.path);
            if (root.text.length > 0)
                data["text/plain"] = root.text;
            else if (root.path.length > 0 && data["text/plain"] === undefined)
                // A chat box that does not understand URI lists still gets something useful.
                data["text/plain"] = root.path;
            return data;
        }

        Drag.onDragStarted: root.dragStarted()
        Drag.onDragFinished: root.dragFinished()
    }

    MouseArea {
        id: dragArea
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true

        cursorShape: !root.enabled ? Qt.ArrowCursor
            : dragArea.drag.active ? Qt.ClosedHandCursor
            : dragArea.containsMouse ? Qt.OpenHandCursor
            : Qt.ArrowCursor

        drag.target: payload
        // Enough travel that a click is never a drag, little enough that a deliberate drag
        // feels immediate.
        drag.threshold: 8

        onPressed: {
            // The drag image has to exist before the drag starts, and grabToImage is
            // asynchronous - so it is taken on press, not on drag start, or the first drag of
            // any item has no image.
            if (!root.enabled || (root.path.length === 0 && root.text.length === 0 && Object.keys(root.mimeData ?? {}).length === 0))
                return;
            contentHolder.grabToImage(result => {
                payload.Drag.imageSource = result.url;
            });
        }

        onClicked: {
            if (!dragArea.drag.active)
                root.clicked();
        }

        onReleased: {
            if (payload.Drag.active)
                payload.Drag.drop();
        }
    }

    // "/home/me/my report.pdf" -> "file:///home/me/my%20report.pdf"
    //
    // Encoded per path segment: encodeURIComponent would escape the separators too, and a
    // receiver given "file:///home%2Fme" cannot find the file.
    function __uriOf(path: string): string {
        const absolute = PluginFs.expand(String(path ?? ""));
        return "file://" + absolute.split("/").map(segment => encodeURIComponent(segment)).join("/");
    }
}
