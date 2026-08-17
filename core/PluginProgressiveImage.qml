// A still image now, an animated one when it matters.
//
// The blank-cell problem: an `AnimatedImage` pointed at a remote GIF shows nothing at all
// until enough of the file has arrived to decode a frame - which over a slow connection is
// seconds of empty grid. Meanwhile the same provider almost always offers a small static
// thumbnail that arrives in a tenth of the time.
//
// So both are loaded: the thumbnail immediately, the animation only when this item is the one
// being looked at, and the animation is only *shown* once it has a frame. The cell is never
// empty and never flickers back to empty.
//
//     PluginProgressiveImage {
//         thumbnail: item.thumbnail
//         preview: item.gif
//         playing: cellIsHovered
//     }
//
// ## Why `playing` is not just `visible`
//
// A grid of forty animated GIFs is forty decoders, forty timers and a frame budget gone.
// Playing only the item under the pointer is one decoder, and it is also what the user can
// actually perceive - nobody watches forty animations at once. `PluginContentView` binds
// `playing` to hover for exactly this reason.
//
// Animation additionally stops whenever `PluginLifecycle.animate` is false, so a picker left
// open behind a lock screen costs nothing.

import QtQuick
import Quickshell.Widgets
import qs.core
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    // A still image URL. Loaded as soon as the item is on screen.
    property string thumbnail: ""

    // An animated image URL. Loaded only while `playing`.
    property string preview: ""

    // Whether the animation should run. Usually bound to hover.
    property bool playing: false

    property real radius: 0

    // Shown when there is no image at all: a Material Symbol, a flat colour, or a label.
    property string fallbackIcon: ""
    property string fallbackColour: ""
    property string label: ""

    property int fillMode: Image.PreserveAspectCrop

    readonly property bool hasMedia: root.thumbnail.length > 0 || root.preview.length > 0
    readonly property bool ready: stillImage.status === Image.Ready || animation.__showing
    readonly property bool failed: stillImage.status === Image.Error
        && (root.preview.length === 0 || animation.status === AnimatedImage.Error)

    clip: true

    // Flat colour swatch, for palettes and colour pickers.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        visible: root.fallbackColour.length > 0 && !root.hasMedia
        color: root.fallbackColour.length > 0 ? root.fallbackColour : "transparent"
    }

    // Placeholder while nothing has decoded yet. A dim block rather than a spinner: forty
    // spinners in a grid is noise, and the thumbnail usually beats the eye anyway.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        visible: root.hasMedia && !root.ready
        color: Theme.fade(Theme.outline, 0.12)
    }

    // Rounded with a real stencil clip rather than a mask effect: a MultiEffect mask means an
    // offscreen texture and a second render pass *per cell*, and in a grid of forty that is the
    // difference between a smooth scroll and a stuttering one.
    ClippingRectangle {
        id: clip
        anchors.fill: parent
        radius: root.radius
        color: "transparent"

        Image {
            id: stillImage
            anchors.fill: parent
            source: root.thumbnail
            visible: root.thumbnail.length > 0 && !animation.__showing
            fillMode: root.fillMode
            asynchronous: true
            cache: true
            // Decoded at the size it is drawn at, not the size it was published at. A 600 px
            // thumbnail in a 132 px cell is four times the memory for no visible difference, and
            // in a grid of forty that is the difference between tens and hundreds of megabytes.
            sourceSize.width: Math.max(1, Math.ceil(root.width))
            sourceSize.height: Math.max(1, Math.ceil(root.height))
        }

        // The animation. `active` on the Loader is what keeps it from being built at all until
        // someone hovers - AnimatedImage starts fetching the moment it exists.
        Loader {
            id: animationLoader
            anchors.fill: parent
            active: root.preview.length > 0 && root.playing && PluginLifecycle.animate
            visible: animation.__showing

            sourceComponent: AnimatedImage {
                source: root.preview
                fillMode: root.fillMode
                asynchronous: true
                cache: false            // a GIF cached at full size is the biggest thing in the cache
                playing: root.playing && PluginLifecycle.animate
                speed: 1
            }
        }
    }

    // Tracks whether the animation has a frame worth showing. Kept here rather than read
    // through the Loader in a binding, because `animationLoader.item.status` is not a tracked
    // dependency until the item exists - so the thumbnail would never hand over.
    QtObject {
        id: animation

        property int status: AnimatedImage.Null
        readonly property bool __showing: animation.status === AnimatedImage.Ready
    }

    Connections {
        target: animationLoader.item
        enabled: animationLoader.item !== null
        function onStatusChanged(): void {
            animation.status = animationLoader.item?.status ?? AnimatedImage.Null;
        }
    }

    onPlayingChanged: {
        // Reset when the pointer leaves, so returning to a cell shows the still frame first
        // rather than a stale last frame of a decoder that has since been torn down.
        if (!root.playing)
            animation.status = AnimatedImage.Null;
    }

    // Icon fallback: no image, no colour.
    MaterialSymbol {
        anchors.centerIn: parent
        visible: !root.hasMedia && root.fallbackColour.length === 0 && root.fallbackIcon.length > 0
        text: root.fallbackIcon
        iconSize: Math.max(16, Math.min(root.width, root.height) * 0.4)
        color: Theme.textFaint
    }

    // Text fallback, for a list of things with neither image nor icon.
    StyledText {
        anchors.centerIn: parent
        width: parent.width - Theme.pad.m * 2
        visible: !root.hasMedia && root.fallbackColour.length === 0
            && root.fallbackIcon.length === 0 && root.label.length > 0
        text: root.label
        color: Theme.textDim
        font.pixelSize: Theme.font.s
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        maximumLineCount: 3
        wrapMode: Text.Wrap
    }

    // A broken URL should say so rather than leave a grey block that looks like a slow load
    // forever.
    MaterialSymbol {
        anchors.centerIn: parent
        visible: root.failed
        text: "broken_image"
        iconSize: Math.max(14, Math.min(root.width, root.height) * 0.3)
        color: Theme.fade(Theme.error, 0.7)
    }
}
