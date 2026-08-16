// A telemetry chart: a line, an area, or bars, from a plain array of numbers.
//
//     PluginSparkline {
//         width: 120
//         height: 36
//         values: PluginSystem.cpu.history
//         maximum: 100
//     }
//
//     PluginSparkline {
//         values: PluginSystem.network.downloadHistory
//         autoScale: true               // no fixed ceiling: scale to the window
//         style: PluginSparkline.Bars
//         color: Theme.notice
//     }
//
// Drawn on a Canvas, repainted only when the data changes - not on a timer - so a chart that
// is fed once a second costs one repaint a second, and one that is off screen costs nothing.
//
// `autoScale` is for quantities with no natural maximum, like network throughput. It scales to
// the largest value in the window with a floor, so an idle line sits at the bottom instead of
// jittering at full height over rounding noise.
//
// Values arrive oldest-first, which is what PluginSystem's history properties give.

import QtQuick
import qs.core
import qs.modules.common

Canvas {
    id: root

    enum Style {
        Line,
        Area,
        Bars
    }

    property var values: []

    // Ceiling for the y axis. Ignored when autoScale is on.
    property real maximum: 100
    property real minimum: 0

    property bool autoScale: false

    // Never scale below this, so an all-zero series is a flat line at the bottom rather than
    // noise amplified to full height.
    property real autoScaleFloor: 1

    property int style: PluginSparkline.Style.Area

    property color color: Theme.accent
    property color fillColor: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.22)
    property real lineWidth: 2

    // Draw a baseline at the bottom, so an empty chart still reads as a chart.
    property bool showBaseline: true
    property color baselineColor: Theme.outlineFaint

    // Rounded caps and joins look better at small sizes; square is more honest for bars.
    property bool smooth_: true

    implicitWidth: 100
    implicitHeight: 32

    onValuesChanged: root.requestPaint()
    onColorChanged: root.requestPaint()
    onStyleChanged: root.requestPaint()
    onWidthChanged: root.requestPaint()
    onHeightChanged: root.requestPaint()

    readonly property real __scale: {
        if (!root.autoScale)
            return Math.max(root.autoScaleFloor, root.maximum - root.minimum);
        let peak = root.autoScaleFloor;
        for (const value of root.values)
            peak = Math.max(peak, value);
        return peak - root.minimum;
    }

    onPaint: {
        const context = root.getContext("2d");
        context.reset();
        context.clearRect(0, 0, root.width, root.height);

        if (root.showBaseline) {
            context.strokeStyle = root.baselineColor;
            context.lineWidth = 1;
            context.beginPath();
            context.moveTo(0, root.height - 0.5);
            context.lineTo(root.width, root.height - 0.5);
            context.stroke();
        }

        const values = root.values ?? [];
        if (values.length === 0)
            return;

        const scale = root.__scale;
        const inset = root.lineWidth / 2;
        const usable = Math.max(1, root.height - root.lineWidth);
        const y = value => root.height - inset - Math.max(0, Math.min(1, (value - root.minimum) / scale)) * usable;

        if (root.style === PluginSparkline.Style.Bars) {
            // One bar per sample, with a hairline gap. Below about three pixels a gap costs
            // more than it communicates, so it is dropped.
            const slot = root.width / values.length;
            const gap = slot > 3 ? 1 : 0;
            context.fillStyle = root.color;
            for (let i = 0; i < values.length; i++) {
                const top = y(values[i]);
                context.fillRect(i * slot, top, Math.max(1, slot - gap), root.height - top);
            }
            return;
        }

        // A single sample has no line to draw, so it becomes a dot - otherwise the first
        // second of a chart's life looks broken.
        if (values.length === 1) {
            context.fillStyle = root.color;
            context.beginPath();
            context.arc(root.width / 2, y(values[0]), root.lineWidth, 0, Math.PI * 2);
            context.fill();
            return;
        }

        const step = root.width / (values.length - 1);

        if (root.style === PluginSparkline.Style.Area) {
            context.beginPath();
            context.moveTo(0, root.height);
            for (let i = 0; i < values.length; i++)
                context.lineTo(i * step, y(values[i]));
            context.lineTo(root.width, root.height);
            context.closePath();
            context.fillStyle = root.fillColor;
            context.fill();
        }

        context.beginPath();
        context.lineWidth = root.lineWidth;
        context.strokeStyle = root.color;
        context.lineJoin = root.smooth_ ? "round" : "miter";
        context.lineCap = root.smooth_ ? "round" : "butt";
        for (let i = 0; i < values.length; i++) {
            const px = i * step;
            const py = y(values[i]);
            if (i === 0)
                context.moveTo(px, py);
            else
                context.lineTo(px, py);
        }
        context.stroke();
    }
}
