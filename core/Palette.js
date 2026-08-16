.pragma library

// Tonal palettes and Material 3 colour roles from one source colour.
//
// Used by Theme.createPaletteFromColor(), which is how a plugin themes itself to something it
// found at runtime - album art, a wallpaper sample, a service's brand colour - instead of being
// limited to the shell's own accent.
//
// ## What this is, precisely
//
// Material 3 defines a tonal palette as "one hue and chroma, sampled at thirteen tones", where
// tone is CIELAB L*. That is implemented here exactly: the source colour is converted to CIELCh,
// its hue and chroma are held, and L* is set to each tone. Colours that fall outside sRGB have
// their chroma reduced until they fit, which is what Google's HCT does as well.
//
// The difference from HCT is the space hue and chroma are read in: HCT uses CAM16, this uses
// CIELCh(ab). The tone axis is identical, so ramps line up; hue can differ by a degree or two on
// very saturated blues, where CAM16's hue is perceptually better. That is a fair trade for ~150
// lines of arithmetic instead of a CAM16 implementation, and it is the same arithmetic in both
// directions, so a round trip is stable.
//
// Everything here is a pure function of numbers and hex strings - no QML, no Qt - so it can be
// reasoned about and tested on its own.

// ---------------------------------------------------------------------------- sRGB

function clamp(value, low, high) {
    return Math.max(low, Math.min(high, value));
}

function hexToRgb(hex) {
    let text = `${hex}`.trim();
    if (text.startsWith("#"))
        text = text.slice(1);
    // #rgb shorthand, and #aarrggbb as Qt writes it.
    if (text.length === 3)
        text = text.split("").map(character => character + character).join("");
    if (text.length === 8)
        text = text.slice(2);
    if (text.length !== 6)
        return { r: 0, g: 0, b: 0 };
    return {
        r: parseInt(text.slice(0, 2), 16),
        g: parseInt(text.slice(2, 4), 16),
        b: parseInt(text.slice(4, 6), 16)
    };
}

function rgbToHex(rgb) {
    const part = value => Math.round(clamp(value, 0, 255)).toString(16).padStart(2, "0");
    return `#${part(rgb.r)}${part(rgb.g)}${part(rgb.b)}`;
}

// sRGB transfer function, in both directions. The linear values are what all the matrix
// arithmetic below operates on; skipping this step is the single most common way colour
// interpolation goes wrong.
function linearize(channel) {
    const normalized = channel / 255;
    return normalized <= 0.04045
        ? normalized / 12.92
        : Math.pow((normalized + 0.055) / 1.055, 2.4);
}

function delinearize(channel) {
    const encoded = channel <= 0.0031308
        ? channel * 12.92
        : 1.055 * Math.pow(channel, 1 / 2.4) - 0.055;
    return encoded * 255;
}

// ------------------------------------------------------------------------ XYZ / Lab

// D65, matching sRGB's own white point.
const WHITE_X = 95.047;
const WHITE_Y = 100.0;
const WHITE_Z = 108.883;

function rgbToXyz(rgb) {
    const r = linearize(rgb.r) * 100;
    const g = linearize(rgb.g) * 100;
    const b = linearize(rgb.b) * 100;
    return {
        x: r * 0.4124564 + g * 0.3575761 + b * 0.1804375,
        y: r * 0.2126729 + g * 0.7151522 + b * 0.0721750,
        z: r * 0.0193339 + g * 0.1191920 + b * 0.9503041
    };
}

function xyzToRgb(xyz) {
    const r = (xyz.x * 3.2404542 + xyz.y * -1.5371385 + xyz.z * -0.4985314) / 100;
    const g = (xyz.x * -0.9692660 + xyz.y * 1.8760108 + xyz.z * 0.0415560) / 100;
    const b = (xyz.x * 0.0556434 + xyz.y * -0.2040259 + xyz.z * 1.0572252) / 100;
    return { r: delinearize(r), g: delinearize(g), b: delinearize(b) };
}

function labF(t) {
    const epsilon = 216 / 24389;
    const kappa = 24389 / 27;
    return t > epsilon ? Math.cbrt(t) : (kappa * t + 16) / 116;
}

function labFInverse(t) {
    const epsilon = 216 / 24389;
    const kappa = 24389 / 27;
    const cubed = t * t * t;
    return cubed > epsilon ? cubed : (116 * t - 16) / kappa;
}

function xyzToLab(xyz) {
    const fx = labF(xyz.x / WHITE_X);
    const fy = labF(xyz.y / WHITE_Y);
    const fz = labF(xyz.z / WHITE_Z);
    return {
        l: 116 * fy - 16,
        a: 500 * (fx - fy),
        b: 200 * (fy - fz)
    };
}

function labToXyz(lab) {
    const fy = (lab.l + 16) / 116;
    const fx = fy + lab.a / 500;
    const fz = fy - lab.b / 200;
    return {
        x: labFInverse(fx) * WHITE_X,
        y: labFInverse(fy) * WHITE_Y,
        z: labFInverse(fz) * WHITE_Z
    };
}

function labToLch(lab) {
    const chroma = Math.sqrt(lab.a * lab.a + lab.b * lab.b);
    let hue = Math.atan2(lab.b, lab.a) * 180 / Math.PI;
    if (hue < 0)
        hue += 360;
    return { l: lab.l, c: chroma, h: hue };
}

function lchToLab(lch) {
    const radians = lch.h * Math.PI / 180;
    return {
        l: lch.l,
        a: Math.cos(radians) * lch.c,
        b: Math.sin(radians) * lch.c
    };
}

// ------------------------------------------------------------------------ tones

function inGamut(rgb) {
    const slack = 0.5;
    return rgb.r >= -slack && rgb.r <= 255 + slack
        && rgb.g >= -slack && rgb.g <= 255 + slack
        && rgb.b >= -slack && rgb.b <= 255 + slack;
}

// One tone of a tonal palette: the given hue at the given tone, as saturated as sRGB allows up
// to `chroma`.
//
// Reducing chroma rather than clipping RGB is what keeps a ramp looking like one colour: clipping
// a channel shifts the hue, so tone 90 of a red would come out pink and tone 20 brown.
function toneHex(hue, chroma, tone) {
    const wanted = clamp(tone, 0, 100);

    let low = 0;
    let high = chroma;
    let best = null;

    // Twenty halvings resolve chroma to about 0.0001 of a unit, well past what eight bits per
    // channel can show.
    for (let step = 0; step < 20; step++) {
        const middle = (low + high) / 2;
        const rgb = xyzToRgb(labToXyz(lchToLab({ l: wanted, c: middle, h: hue })));
        if (inGamut(rgb)) {
            best = rgb;
            low = middle;
        } else {
            high = middle;
        }
        if (high - low < 0.0001)
            break;
    }

    if (best === null)
        best = xyzToRgb(labToXyz(lchToLab({ l: wanted, c: 0, h: hue })));

    return rgbToHex({
        r: clamp(best.r, 0, 255),
        g: clamp(best.g, 0, 255),
        b: clamp(best.b, 0, 255)
    });
}

// The thirteen tones Material 3 names, plus the ones its 2023 surface roles need.
const TONES = [0, 4, 5, 6, 10, 12, 17, 20, 22, 24, 25, 30, 35, 40, 50, 60, 70, 80, 87, 90, 92, 94, 95, 96, 98, 99, 100];

// { hue, chroma, tone: fn, tones: { 0: "#...", ... } }
function tonalPalette(hue, chroma) {
    const tones = ({});
    for (const tone of TONES)
        tones[tone] = toneHex(hue, chroma, tone);
    return {
        hue: hue,
        chroma: chroma,
        tones: tones,
        tone: function (value) {
            return tones[value] ?? toneHex(hue, chroma, value);
        }
    };
}

function paletteFromHex(hex) {
    const lch = labToLch(xyzToLab(rgbToXyz(hexToRgb(hex))));
    return tonalPalette(lch.h, lch.c);
}

// ------------------------------------------------------------------------ scheme

// The six palettes a Material 3 scheme is built from, derived from one source colour the way the
// default ("tonal spot") variant does it: secondary and tertiary are the source hue turned, and
// the neutrals keep the hue at very low chroma so greys are tinted by it rather than dead grey.
function palettesFromHex(hex) {
    const source = labToLch(xyzToLab(rgbToXyz(hexToRgb(hex))));
    const hue = source.h;
    const chroma = Math.max(source.c, 8);

    return {
        primary: tonalPalette(hue, Math.max(chroma, 36)),
        secondary: tonalPalette(hue, 16),
        tertiary: tonalPalette((hue + 60) % 360, 24),
        neutral: tonalPalette(hue, 4),
        neutralVariant: tonalPalette(hue, 8),
        error: tonalPalette(25, 84)
    };
}

// Every Material 3 role, for one source colour and one mode.
//
// The tone assignments are the specification's own: primary is 40 in light and 80 in dark, its
// container 90 and 30, and so on. They are listed literally rather than computed because that is
// what they are - a table - and a reader checking one role against the spec should be able to
// find it on one line.
function schemeFromHex(hex, dark) {
    const p = palettesFromHex(hex);
    const t = (palette, tone) => p[palette].tone(tone);

    if (dark) {
        return {
            source: `${hex}`,
            dark: true,

            primary: t("primary", 80),
            onPrimary: t("primary", 20),
            primaryContainer: t("primary", 30),
            onPrimaryContainer: t("primary", 90),
            inversePrimary: t("primary", 40),

            secondary: t("secondary", 80),
            onSecondary: t("secondary", 20),
            secondaryContainer: t("secondary", 30),
            onSecondaryContainer: t("secondary", 90),

            tertiary: t("tertiary", 80),
            onTertiary: t("tertiary", 20),
            tertiaryContainer: t("tertiary", 30),
            onTertiaryContainer: t("tertiary", 90),

            error: t("error", 80),
            onError: t("error", 20),
            errorContainer: t("error", 30),
            onErrorContainer: t("error", 90),

            background: t("neutral", 6),
            onBackground: t("neutral", 90),
            surface: t("neutral", 6),
            onSurface: t("neutral", 90),
            surfaceDim: t("neutral", 6),
            surfaceBright: t("neutral", 24),
            surfaceContainerLowest: t("neutral", 4),
            surfaceContainerLow: t("neutral", 10),
            surfaceContainer: t("neutral", 12),
            surfaceContainerHigh: t("neutral", 17),
            surfaceContainerHighest: t("neutral", 22),
            surfaceVariant: t("neutralVariant", 30),
            onSurfaceVariant: t("neutralVariant", 80),
            inverseSurface: t("neutral", 90),
            inverseOnSurface: t("neutral", 20),

            outline: t("neutralVariant", 60),
            outlineVariant: t("neutralVariant", 30),
            shadow: t("neutral", 0),
            scrim: t("neutral", 0)
        };
    }

    return {
        source: `${hex}`,
        dark: false,

        primary: t("primary", 40),
        onPrimary: t("primary", 100),
        primaryContainer: t("primary", 90),
        onPrimaryContainer: t("primary", 10),
        inversePrimary: t("primary", 80),

        secondary: t("secondary", 40),
        onSecondary: t("secondary", 100),
        secondaryContainer: t("secondary", 90),
        onSecondaryContainer: t("secondary", 10),

        tertiary: t("tertiary", 40),
        onTertiary: t("tertiary", 100),
        tertiaryContainer: t("tertiary", 90),
        onTertiaryContainer: t("tertiary", 10),

        error: t("error", 40),
        onError: t("error", 100),
        errorContainer: t("error", 90),
        onErrorContainer: t("error", 10),

        background: t("neutral", 98),
        onBackground: t("neutral", 10),
        surface: t("neutral", 98),
        onSurface: t("neutral", 10),
        surfaceDim: t("neutral", 87),
        surfaceBright: t("neutral", 98),
        surfaceContainerLowest: t("neutral", 100),
        surfaceContainerLow: t("neutral", 96),
        surfaceContainer: t("neutral", 94),
        surfaceContainerHigh: t("neutral", 92),
        surfaceContainerHighest: t("neutral", 90),
        surfaceVariant: t("neutralVariant", 90),
        onSurfaceVariant: t("neutralVariant", 30),
        inverseSurface: t("neutral", 20),
        inverseOnSurface: t("neutral", 95),

        outline: t("neutralVariant", 50),
        outlineVariant: t("neutralVariant", 80),
        shadow: t("neutral", 0),
        scrim: t("neutral", 0)
    };
}

// Perceptual lightness of a colour, 0..100 - the same number the tone axis uses, so
// `tone(hex) > 60` is a meaningful "is this light".
function toneOf(hex) {
    return xyzToLab(rgbToXyz(hexToRgb(hex))).l;
}

// Whichever of two candidates is more readable on `background`, by WCAG contrast ratio.
function readableOn(background, candidates) {
    const luminance = hex => {
        const rgb = hexToRgb(hex);
        return 0.2126 * linearize(rgb.r) + 0.7152 * linearize(rgb.g) + 0.0722 * linearize(rgb.b);
    };
    const backgroundLuminance = luminance(background);
    let best = candidates[0];
    let bestRatio = -1;
    for (const candidate of candidates) {
        const candidateLuminance = luminance(candidate);
        const lighter = Math.max(backgroundLuminance, candidateLuminance);
        const darker = Math.min(backgroundLuminance, candidateLuminance);
        const ratio = (lighter + 0.05) / (darker + 0.05);
        if (ratio > bestRatio) {
            bestRatio = ratio;
            best = candidate;
        }
    }
    return { color: best, ratio: bestRatio };
}
