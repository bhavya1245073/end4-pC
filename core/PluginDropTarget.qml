// Accepts things dragged onto it, with the URI decoding and the hover feedback already done.
//
// What this replaces, in every widget that wants a file dropped on it:
//
//     DropArea {
//         keys: ["text/uri-list"]
//         onEntered: highlight = true
//         onExited: highlight = false
//         onDropped: drop => {
//             const paths = drop.urls.map(u => decodeURIComponent(u.toString().replace("file://", "")))
//             ...
//         }
//     }
//     Rectangle { border.color: highlight ? accent : "transparent" ... }
//
// Every one of those is subtly wrong somewhere. `replace("file://", "")` strips the scheme
// anywhere in the string, so a path containing "file://" is corrupted. Forgetting
// decodeURIComponent means a file called "my report.pdf" arrives as "my%20report.pdf" and
// every subsequent operation on it fails. `onExited` does not fire if the drop is accepted, so
// the highlight sticks. Getting all of it right per widget is why so few widgets accept drops.
//
//     PluginDropTarget {
//         anchors.fill: parent
//         onFilesDropped: paths => shelf.park(paths)
//     }
//
// Signals are clean by the time they reach you: `filesDropped` gets real filesystem paths,
// `textDropped` gets text, `urlsDropped` gets non-file URLs (a link dragged from a browser).

import QtQuick
import qs.core
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    // What to accept. Anything not listed is refused, so a widget that wants files does not
    // light up for dragged text.
    property bool acceptFiles: true
    property bool acceptText: true

    // Extra MIME types, for a plugin with its own drag payloads.
    property var mimeTypes: []

    // Visual feedback. `false` if the surrounding widget draws its own.
    property bool showHighlight: true
    property real highlightRadius: Theme.radius.m
    property string highlightIcon: "download"
    property string highlightText: ""

    readonly property bool dragging: dropArea.containsDrag
    readonly property bool acceptable: root.dragging && root.__wanted(dropArea.drag)

    // Real filesystem paths, decoded.
    signal filesDropped(var paths);

    // Plain text.
    signal textDropped(string text);

    // URLs that are not files - a link from a browser, a magnet URI.
    signal urlsDropped(var urls);

    // Everything, for a target that wants to decide for itself.
    signal dropped(var payload);

    DropArea {
        id: dropArea
        anchors.fill: parent

        keys: {
            const wanted = [];
            if (root.acceptFiles)
                wanted.push("text/uri-list");
            if (root.acceptText)
                wanted.push("text/plain");
            return wanted.concat(root.mimeTypes ?? []);
        }

        onDropped: drop => {
            const payload = { paths: [], urls: [], text: "" };

            if (drop.hasUrls) {
                for (const url of drop.urls) {
                    const asString = url.toString();
                    if (asString.startsWith("file://"))
                        payload.paths.push(root.__pathOf(asString));
                    else
                        payload.urls.push(asString);
                }
            }

            if (drop.hasText)
                payload.text = drop.text ?? "";

            // Accept before emitting: a handler may open a window or start a copy, and the
            // source application is waiting to be told the drag succeeded. Telling it after a
            // slow handler is how "the file manager froze for a second" happens.
            drop.acceptProposedAction();

            if (payload.paths.length > 0)
                root.filesDropped(payload.paths);
            if (payload.urls.length > 0)
                root.urlsDropped(payload.urls);
            // Text that came alongside files is the files' own URI list in another flavour, and
            // emitting it as text would make a target act twice on one drop.
            if (payload.text.length > 0 && payload.paths.length === 0 && payload.urls.length === 0)
                root.textDropped(payload.text);

            root.dropped(payload);
        }
    }

    // The highlight. Drawn above the content it decorates, click-through by construction
    // (nothing here takes input) and gone the instant the drag ends - including on a successful
    // drop, which the raw DropArea signals do not guarantee.
    Rectangle {
        anchors.fill: parent
        visible: root.showHighlight && root.dragging
        radius: root.highlightRadius
        color: Theme.fade(Theme.accent, 0.10)
        border.width: 2
        border.color: Theme.fade(Theme.accent, 0.75)

        opacity: root.dragging ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Theme.motion.fast
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: Theme.pad.xs
            visible: root.highlightText.length > 0 || root.highlightIcon.length > 0

            MaterialSymbol {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.highlightIcon.length > 0
                text: root.highlightIcon
                iconSize: Theme.font.xl
                color: Theme.accent
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.highlightText.length > 0
                text: root.highlightText
                color: Theme.accent
                font.pixelSize: Theme.font.s
            }
        }
    }

    function __wanted(drag: var): bool {
        if (!drag)
            return false;
        if (drag.hasUrls && root.acceptFiles)
            return true;
        if (drag.hasText && root.acceptText)
            return true;
        return false;
    }

    // "file:///home/me/my%20report.pdf" -> "/home/me/my report.pdf"
    //
    // Anchored to the start so a path containing the scheme as a substring survives, and
    // decoded so the result is a path the filesystem recognises.
    function __pathOf(url: string): string {
        const withoutScheme = String(url ?? "").replace(/^file:\/\//, "");
        try {
            return decodeURIComponent(withoutScheme);
        } catch (e) {
            // A malformed escape sequence would otherwise throw inside a drop handler and lose
            // the whole drop rather than one path.
            return withoutScheme;
        }
    }
}
