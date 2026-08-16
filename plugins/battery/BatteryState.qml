// Everything derived from the battery, in one place.
//
// The bar widget, its popup and the desktop widget all need to answer the same
// questions - what colour is this, what should it say, how long is left - and if
// each worked it out for itself they would drift apart. A singleton so there is
// one answer.
//
// Thresholds come from the shell's own battery config rather than this plugin's
// settings, so the widget turns red at the same level that the OSD warns and the
// suspend logic arms. Two sets of thresholds would be worse than none.

pragma Singleton

import Quickshell
import QtQuick
import qs.core
import qs.services

Singleton {
    id: root

    readonly property bool available: Battery.available

    readonly property real level: Battery.percentage
    readonly property int percent: Math.round(root.level * 100)

    readonly property bool charging: Battery.isCharging
    readonly property bool pluggedIn: Battery.isPluggedIn

    // UPowerDeviceState.FullyCharged
    readonly property bool full: Battery.chargeState === 4 || (root.pluggedIn && root.percent >= 100)

    readonly property bool low: Battery.isLow && !root.charging
    readonly property bool critical: Battery.isCritical && !root.charging

    // Only pulse for the two states that want acting on.
    readonly property bool pulse: root.charging || root.critical

    // Raw hardware numbers, each with a companion telling you whether to trust it.
    // On a machine with no energy_full or power_now these are zero, and a panel that
    // shows "Health 0%" is worse than one that shows nothing - so the guard is part
    // of the API rather than something each widget has to remember.
    readonly property real rate: Battery.energyRate
    readonly property bool rateKnown: Battery.energyRate > 0.01

    readonly property int health: Math.round(Battery.health)
    readonly property bool healthKnown: Battery.health > 0

    readonly property int cycles: Battery.chargeCycles
    readonly property bool cyclesKnown: Battery.chargeCycles > 0

    // A remaining-time estimate is worse than nothing while the rate is still
    // settling, which is exactly when you are most likely to look at it.
    readonly property real secondsLeft: root.charging ? Battery.timeToFull : Battery.timeToEmpty
    readonly property bool estimateUsable: !root.full && root.secondsLeft > 0 && root.rateKnown

    // The base colour is the widget's, since a bar pill and a desktop widget sit on
    // different surfaces; only the exceptions are decided here.
    //
    // Low and critical share a colour on purpose. `pulse` is what separates them, and
    // two shades of red a few percent apart is a distinction nobody reads - whereas
    // "the red one is breathing" is unmissable.
    function accent(neutral: color): color {
        if (root.low || root.critical)
            return Theme.error;
        if (root.charging)
            return Theme.notice;
        return neutral;
    }

    function icon(): string {
        if (root.charging)
            return "bolt";
        if (root.full)
            return "power";
        if (root.critical)
            return "battery_alert";
        if (root.pluggedIn)
            return "power";
        return "";
    }

    // "1h 24m", "24m", "<1m". Hours and minutes only: seconds are noise on
    // something this slow, and days are never the answer for a laptop.
    function duration(seconds: real): string {
        if (!(seconds > 0))
            return "";

        const total = Math.round(seconds / 60);
        const hours = Math.floor(total / 60);
        const minutes = total % 60;

        if (total < 1)
            return Translation.tr("<1m");
        if (hours < 1)
            return Translation.tr("%1m").arg(minutes);
        return Translation.tr("%1h %2m").arg(hours).arg(minutes);
    }

    // One line, for a tooltip or the popup's subtitle.
    function summary(): string {
        if (!root.available)
            return Translation.tr("No battery");
        if (root.full)
            return Translation.tr("Fully charged");

        const left = root.estimateUsable ? root.duration(root.secondsLeft) : "";

        if (root.charging)
            return left ? Translation.tr("Charging \u00b7 %1 until full").arg(left) : Translation.tr("Charging");
        if (root.pluggedIn)
            return Translation.tr("Plugged in");

        return left ? Translation.tr("%1 remaining").arg(left) : Translation.tr("On battery");
    }
}
