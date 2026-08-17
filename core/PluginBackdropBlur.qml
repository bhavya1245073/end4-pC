// Blur of what is behind a surface, as far as a Wayland client can honestly manage.
//
// ## What is actually possible
//
// A layer-shell client cannot read the compositor's framebuffer. There is no protocol for
// "give me the pixels behind my surface", and there will not be one - it is the same
// capability a screen recorder needs, and it is gated for the same reason. Every "acrylic"
// effect in a Wayland shell is therefore one of three things:
//
//   1. Blurring something the client already has. The wallpaper is the useful case: the shell
//      draws it, so it can sample it. This is what the effect does.
//   2. Asking the compositor to blur behind the surface. Hyprland can do this
//      (`layerrule = blur, namespace`) and it is genuinely the compositor's own blur of real
//      content behind the window - including other applications. Nothing in QML can turn it
//      on, so `compositorHint` documents the one line a user adds, and `PluginFX.blurRule`
//      generates it.
//   3. A flat translucent fill and calling it glass. Common, and it looks like what it is.
//
// This does 1 and tells you about 2, because pretending a client-side blur of the wallpaper is
// a backdrop blur is how you get a card that looks perfect over the desktop and obviously
// wrong over a browser window.
//
//     PluginBackdropBlur {
//         anchors.fill: parent
//         radius: Theme.radius.l
//     }
//
// Over the desktop that is indistinguishable from a real backdrop blur. Over a window it is a
// tinted panel - which is exactly what the compositor rule fixes, and what `PluginFX.blurRule`
// prints.

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.core
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    // Corner radius of the blurred region.
    property real radius: 0

    // 0..1. Above ~0.75 the wallpaper stops being recognisable and the effect reads as noise.
    property real strength: 0.62

    // Tint over the blur. The surface colour at low alpha is what makes text on top readable,
    // and without it a light wallpaper makes any label unreadable.
    property color tint: Theme.solid
    property real tintAlpha: 0.55

    // Desaturating the blur keeps a colourful wallpaper from fighting the accent colour.
    property real saturation: 0.35

    // Whether the wallpaper source could be found. False on a screen with no wallpaper surface,
    // where the tint alone is used.
    readonly property bool sampling: wallpaperSource.sourceItem !== null

    // The layer rule a user adds to blur *everything* behind this surface, including other
    // windows. Printed by PluginFX.blurRule() too.
    readonly property string compositorHint: PluginFX.blurRule(root.QsWindow?.window?.WlrLayershell?.namespace ?? "quickshell:pluginWindow")

    // What to blur. The shell's wallpaper item, found once rather than assumed, so this keeps
    // working when the background module is restructured.
    ShaderEffectSource {
        id: wallpaperSource
        anchors.fill: parent
        visible: false
        live: PluginLifecycle.animate     // a still wallpaper needs no re-sampling
        recursive: false
        hideSource: false
        sourceItem: PluginFX.wallpaperItem
        // Sample the region of the wallpaper this surface covers, in the wallpaper's own
        // coordinates - otherwise every blurred card shows the top-left corner of the desktop.
        sourceRect: PluginFX.wallpaperItem
            ? Qt.rect(
                root.mapToItem(PluginFX.wallpaperItem, 0, 0).x,
                root.mapToItem(PluginFX.wallpaperItem, 0, 0).y,
                root.width,
                root.height)
            : Qt.rect(0, 0, 0, 0)
    }

    // Rounded with a stencil clip rather than a mask effect: the blur is already an offscreen
    // pass, and masking it would be a second one over the same pixels.
    ClippingRectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"

        MultiEffect {
            id: blur
            anchors.fill: parent
            visible: root.sampling
            source: wallpaperSource
            blurEnabled: true
            // 64 is the point past which more costs frames without looking different.
            blurMax: 64
            blur: Math.max(0, Math.min(1, root.strength))
            saturation: root.saturation - 1   // MultiEffect takes -1..0 as desaturation
        }
    }

    // The tint, and the whole effect when there is nothing to sample.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, root.sampling ? root.tintAlpha : 0.92)
    }

    // A hairline edge. Without it a blurred card has no boundary against a busy wallpaper and
    // looks like a smudge.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        border.width: 1
        border.color: Theme.fade(Theme.outline, 0.3)
    }
}
