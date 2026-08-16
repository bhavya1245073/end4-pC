// A radial meter, with colour thresholds.
//
//     PluginGauge {
//         value: PluginSystem.cpu.usagePercent
//         label: "CPU"
//         caption: PluginSystem.cpu.tempFormatted
//     }
//
//     PluginGauge {
//         value: PluginSystem.disks.root.usedPercent
//         thresholds: [{ at: 80, color: Theme.notice }, { at: 92, color: Theme.error }]
//     }
//
// `value` is a percentage by default; set `maximum` for anything else. The arc animates to new
// values, so a two-second poll does not look like a jump, and the animation is skipped for the
// first value so a gauge does not sweep up from zero every time it is created.
//
// Thresholds are ordered by `at` and the highest one reached wins - which is how "warn at 80,
// alarm at 92" is meant to read. Without them the arc is the accent colour.

import QtQuick
import qs.core
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    property real value: 0
    property real maximum: 100
    property real minimum: 0

    // Centre text. `label` is small and above, `caption` small and below; the big number in
    // the middle is generated from the value unless `text` is set.
    property string label: ""
    property string caption: ""
    property string text: ""

    // [{ at: <value>, color: <color> }] - highest reached wins.
    property var thresholds: []

    property color color: Theme.accent
    property color trackColor: Theme.outlineFaint
    property real thickness: 6

    // Degrees. The default leaves a gap at the bottom, which reads as a dial rather than a pie.
    property real startAngle: 135
    property real sweepAngle: 270

    property bool animated: true
    property bool showValue: true

    implicitWidth: 84
    implicitHeight: 84

    readonly property real fraction: {
        const span = root.maximum - root.minimum;
        if (!(span > 0))
            return 0;
        return Math.max(0, Math.min(1, (root.value - root.minimum) / span));
    }

    readonly property color activeColor: {
        let chosen = root.color;
        const sorted = (root.thresholds ?? []).slice().sort((a, b) => a.at - b.at);
        for (const threshold of sorted) {
            if (root.value >= threshold.at)
                chosen = threshold.color;
        }
        return chosen;
    }

    // The animated value the arc is actually drawn from. Starts equal to the first real value
    // so a freshly created gauge does not sweep.
    property real __displayed: 0
    property bool __primed: false

    onFractionChanged: {
        if (!root.__primed) {
            root.__displayed = root.fraction;
            root.__primed = true;
            return;
        }
        root.__displayed = root.fraction;
    }

    Behavior on __displayed {
        enabled: root.animated && root.__primed
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.OutCubic
        }
    }

    Canvas {
        id: canvas
        anchors.fill: parent

        // Repaint on the things that change the picture, and nothing else.
        Connections {
            target: root
            function on__DisplayedChanged(): void { canvas.requestPaint(); }
            function onActiveColorChanged(): void { canvas.requestPaint(); }
            function onThicknessChanged(): void { canvas.requestPaint(); }
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            const context = getContext("2d");
            context.reset();
            context.clearRect(0, 0, width, height);

            const centreX = width / 2;
            const centreY = height / 2;
            const radius = Math.min(width, height) / 2 - root.thickness / 2;
            if (radius <= 0)
                return;

            const toRadians = degrees => (degrees - 90) * Math.PI / 180;
            const from = toRadians(root.startAngle);
            const to = toRadians(root.startAngle + root.sweepAngle);

            context.lineWidth = root.thickness;
            context.lineCap = "round";

            context.beginPath();
            context.strokeStyle = root.trackColor;
            context.arc(centreX, centreY, radius, from, to, false);
            context.stroke();

            if (root.__displayed <= 0)
                return;

            context.beginPath();
            context.strokeStyle = root.activeColor;
            context.arc(centreX, centreY, radius, from, toRadians(root.startAngle + root.sweepAngle * root.__displayed), false);
            context.stroke();
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: -2

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.label.length > 0
            text: root.label
            font.pixelSize: Theme.font.xs
            color: Theme.textFaint
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.showValue
            text: root.text.length > 0 ? root.text : `${Math.round(root.value)}`
            font.pixelSize: Theme.font.l
            font.weight: Font.DemiBold
            color: Theme.text
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.caption.length > 0
            text: root.caption
            font.pixelSize: Theme.font.xs
            color: Theme.textFaint
        }
    }
}
