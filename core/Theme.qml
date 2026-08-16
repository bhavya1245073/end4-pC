pragma Singleton

// The theming API for plugins.
//
// `Appearance` is the shell's own palette and it is enormous: fifty-odd colour
// roles, five rounding steps, nine font sizes, fourteen animation curves. A plugin
// author - human or otherwise - should not have to learn which of
// `colOnSecondaryContainer`, `colOnSurfaceVariant` and `colOnLayer1` is the right
// one for text on a bar pill, and getting it wrong is invisible until the user
// switches to light mode.
//
// So this is the shortlist, in the vocabulary of "what am I drawing" rather than
// "which Material role is this". It follows the Material You palette generated from
// the wallpaper automatically, in both light and dark, with no work from the plugin.
//
//     import qs.core
//
//     Rectangle {
//         color: Theme.surface
//         radius: Theme.radius.m
//         StyledText { color: Theme.text; font.pixelSize: Theme.font.m }
//     }
//
// Everything here is a live binding, so a plugin that uses it recolours with the
// wallpaper for free. Nothing needs to be reloaded and nothing needs to listen.
//
// `Appearance` is still there if you need a role this does not cover. Reach for it
// knowing you are opting out of the guarantee that light mode looks right.


import Quickshell
import QtQuick
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root

    // True when the generated scheme is dark. Prefer picking colours from here over
    // branching on this, but it is occasionally the only way (picking an asset, say).
    readonly property bool dark: Appearance.m3colors.darkmode

    // ------------------------------------------------------------------ surfaces
    //
    // The shell stacks translucent layers: each one is computed to look right painted
    // *on top of the one below it*, with an alpha that follows the user's transparency
    // setting. So these are not interchangeable background colours - `surface` over
    // the wrong base, or over a wallpaper, can come out almost invisible.
    //
    //   panel  a window the shell owns (a bar, a sidebar, a popup)
    //   raised a block inside a panel: a card, a grouped list row  <- the usual one
    //   high   a block inside a block
    //   top    the innermost step, for something selected or focused
    //
    // Over the wallpaper, or anywhere with no shell panel behind it, use `solid`.

    readonly property color panel: Appearance.colors.colLayer0
    readonly property color raised: Appearance.colors.colLayer1
    readonly property color high: Appearance.colors.colLayer2
    readonly property color top: Appearance.colors.colLayer3

    // Kept as aliases because "surface" is what everyone reaches for first.
    readonly property color surface: root.raised
    readonly property color surfaceHigh: root.high

    // Fully opaque, for a desktop widget or anything drawn straight onto the
    // wallpaper, where a translucent layer has nothing to composite against.
    readonly property color solid: Appearance.m3colors.m3surfaceContainer
    readonly property color solidHigh: Appearance.m3colors.m3surfaceContainerHigh

    // A hairline. Already low-contrast; do not also fade it.
    readonly property color outline: Appearance.colors.colOutline
    readonly property color outlineDim: Appearance.colors.colOutlineVariant

    // For anything that has to sit over the wallpaper, or over a scrim.
    readonly property color scrim: Appearance.colors.colScrim
    readonly property color shadow: Appearance.colors.colShadow

    // ---------------------------------------------------------------------- text
    //
    // Paired with the surfaces above: `text` is readable on `raised`, `high` and `top`,
    // and on `solid`. On `panel` specifically, use `textOnPanel`.

    // Body text.
    readonly property color text: Appearance.colors.colOnLayer2

    // Secondary text: captions, units, "3 items". Still legible; not competing.
    readonly property color textDim: Appearance.colors.colOnLayer1

    // Tertiary text: hints, placeholders, disabled labels.
    readonly property color textFaint: Appearance.colors.colSubtext

    // Text directly on a panel background rather than on a block inside it.
    readonly property color textOnPanel: Appearance.colors.colOnLayer0

    // --------------------------------------------------------------- accents
    //
    // `accent` is the wallpaper's colour, and is what a plugin should reach for to
    // look like it belongs. `onAccent` is the only readable text colour on top of it.

    readonly property color accent: Appearance.colors.colPrimary
    readonly property color onAccent: Appearance.colors.colOnPrimary

    // A filled accent block big enough to hold text - a card, a selected row.
    readonly property color accentBlock: Appearance.colors.colPrimaryContainer
    readonly property color onAccentBlock: Appearance.colors.colOnPrimaryContainer

    // The quieter accent, for chips and toggles that should not shout.
    readonly property color accentMuted: Appearance.colors.colSecondaryContainer
    readonly property color onAccentMuted: Appearance.colors.colOnSecondaryContainer

    // --------------------------------------------------------------- semantics
    //
    // Material has no warning or success role, so these are the closest honest
    // mappings rather than invented colours: they stay inside the generated scheme
    // and therefore still look deliberate in light mode.

    readonly property color error: Appearance.m3colors.m3error
    readonly property color errorBlock: Appearance.colors.colErrorContainer
    readonly property color onErrorBlock: Appearance.colors.colOnErrorContainer

    // Distinct from accent and from error, which is all "warning" and "success"
    // really need from a generated palette.
    readonly property color notice: Appearance.colors.colTertiary
    readonly property color noticeBlock: Appearance.colors.colTertiaryContainer
    readonly property color onNoticeBlock: Appearance.colors.colOnTertiaryContainer

    // ------------------------------------------------------------------- states
    //
    // Material draws interaction as a translucent layer over the base colour rather
    // than as a different colour, which is why these are opacities and not colours.
    // `StateLayer` applies them for you; these are for drawing one by hand.

    readonly property QtObject state: QtObject {
        readonly property real hover: 0.08
        readonly property real focus: 0.10
        readonly property real press: 0.10
        readonly property real drag: 0.16
        readonly property real disabled: 0.38
    }

    // --------------------------------------------------------------------- scale

    // Font sizes. `m` is body text.
    readonly property QtObject font: QtObject {
        readonly property int xs: Appearance.font.pixelSize.smallest
        readonly property int s: Appearance.font.pixelSize.smaller
        readonly property int m: Appearance.font.pixelSize.normal
        readonly property int l: Appearance.font.pixelSize.larger
        readonly property int xl: Appearance.font.pixelSize.huge
        readonly property string family: Appearance.font.family.main
        readonly property string mono: Appearance.font.family.monospace
    }

    // Spacing and padding. `m` is the default gap between related things.
    readonly property QtObject pad: QtObject {
        readonly property int xs: 2
        readonly property int s: 4
        readonly property int m: 8
        readonly property int l: 12
        readonly property int xl: 20
    }

    // Corner radii. `m` is a card; `full` is a pill.
    readonly property QtObject radius: QtObject {
        readonly property int xs: Appearance.rounding.unsharpenmore
        readonly property int s: Appearance.rounding.verysmall
        readonly property int m: Appearance.rounding.normal
        readonly property int l: Appearance.rounding.large
        readonly property int full: Appearance.rounding.full
    }

    // ------------------------------------------------------------------ motion
    //
    // Components, for `Behavior on x { animation: Theme.anim.fast.number... }`.
    // Using these rather than a hand-written NumberAnimation is what makes a plugin
    // move like the rest of the shell instead of merely moving.

    readonly property QtObject anim: QtObject {
        // Colour changes, hovers, small state flips.
        readonly property QtObject fast: Appearance.animation.elementMoveFast

        // Position and size changes the eye should follow.
        readonly property QtObject normal: Appearance.animation.elementMove

        // Something appearing.
        readonly property QtObject enter: Appearance.animation.elementMoveEnter

        // Something leaving.
        readonly property QtObject exit: Appearance.animation.elementMoveExit

        // A press acknowledgement.
        readonly property QtObject bounce: Appearance.animation.clickBounce
    }

    // ---------------------------------------------------------------- utilities

    // Same colour, more transparent. `amount` 0..1, where 1 is invisible.
    function fade(base: color, amount: real): color {
        return ColorUtils.transparentize(base, amount);
    }

    // Blend two colours. `amount` is how much of `b`.
    function mix(a: color, b: color, amount: real): color {
        return ColorUtils.mix(b, a, amount);
    }

    // A readable text colour for an arbitrary background - a wallpaper sample, a
    // user-chosen colour, an album cover. `m3surface` and `m3onSurface` are always
    // one light and one dark, swapping with the scheme, so picking the one that
    // contrasts works in both modes.
    function on(background: color): color {
        const a = Appearance.m3colors.m3surface;
        const b = Appearance.m3colors.m3onSurface;
        const wantLight = ColorUtils.isDark(background);
        return ColorUtils.isDark(a) === wantLight ? b : a;
    }

    // Pull an arbitrary colour towards the wallpaper's palette, so third-party
    // assets and hard-coded brand colours stop looking pasted on.
    function harmonize(base: color): color {
        return ColorUtils.adaptToAccent(base, root.accent);
    }

    // Anything from `Appearance` by role name, for the rare case this shortlist does
    // not cover: Theme.role("colTertiaryHover"). Returns transparent if unknown, so
    // a typo is a visible mistake rather than a crash.
    function role(name: string): color {
        return Appearance.colors[name] ?? Appearance.m3colors[name] ?? "transparent";
    }
}
