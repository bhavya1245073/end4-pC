// Bar widget: a drawn capsule, an optional label, and a popup with the detail.
//
// The reading you want almost every time is "roughly how full", which is a shape and
// not a number - so the capsule is the widget and the number is optional. Rate,
// health, cycles and the estimate are a hover away rather than crammed in.
//
// Note what this file does *not* do: pick text colours for the current bar style,
// wire up hover, decide when tooltips are allowed, lay out a popup, or read
// plugins.json. PluginBarWidget and PluginPopup handle all of it.

import QtQuick
import QtQuick.Layouts
import qs.core
import qs.modules.common.widgets

PluginBarWidget {
    id: root

    pluginId: "battery"

    // "none" | "percent" | "time"
    readonly property string labelMode: root.settings.label ?? "percent"

    readonly property bool hideWhenFull: root.settings.hideWhenFull ?? false

    // `??` binds looser than `&&`, so these are deliberately separate.
    visible: BatteryState.available && !(root.hideWhenFull && BatteryState.full)

    // BatteryState decides the exceptions; the base type decides what "normal" looks
    // like on whichever pill style the user picked.
    readonly property color colBattery: BatteryState.accent(root.colText)

    popup: Component {
        PluginPopup {
            title: qsTr("Battery")
            subtitle: BatteryState.summary()
            icon: BatteryState.charging ? "bolt" : BatteryState.critical ? "battery_alert" : BatteryState.pluggedIn ? "power" : "battery_android_full"
            iconBlock: BatteryState.critical ? Theme.errorBlock : Theme.accentBlock
            iconColor: BatteryState.critical ? Theme.onErrorBlock : Theme.accent

            // The same capsule the bar shows, wide enough to read properly. Repeating
            // the shape rather than swapping in a plain progress bar keeps the popup
            // and the bar recognisably the same widget.
            BatteryPill {
                Layout.alignment: Qt.AlignLeft
                Layout.bottomMargin: Theme.pad.xs

                value: BatteryState.level
                pulse: BatteryState.pulse
                colFill: BatteryState.accent(Theme.textDim)
                capsuleLength: 196
                capsuleThickness: 16
            }

            PluginSeparator {
                shown: detailRows.visibleChildren.length > 0
            }

            // Every row is conditional. This laptop reports no energy_full and no
            // power_now, so health, cycles and draw rate are absent or zero, and a
            // panel confidently showing "Health 0%" is worse than one showing nothing.
            ColumnLayout {
                id: detailRows

                Layout.fillWidth: true
                spacing: Theme.pad.xs

                PluginRow {
                    label: qsTr("Power draw")
                    value: `${BatteryState.rate.toFixed(1)} W`
                    shown: BatteryState.rateKnown
                }

                PluginRow {
                    label: BatteryState.charging ? qsTr("Until full") : qsTr("Time remaining")
                    value: BatteryState.duration(BatteryState.secondsLeft)
                    shown: BatteryState.estimateUsable
                }

                PluginRow {
                    label: qsTr("Health")
                    value: `${BatteryState.health}%`
                    shown: BatteryState.healthKnown
                    valueColor: BatteryState.health < 80 ? Theme.error : Theme.textDim
                }

                PluginRow {
                    label: qsTr("Charge cycles")
                    value: `${BatteryState.cycles}`
                    shown: BatteryState.cyclesKnown
                }
            }
        }
    }

    GridLayout {
        // Along the bar, whichever way the bar runs.
        columns: root.vertical ? 1 : 2
        layoutDirection: root.mirrored ? Qt.RightToLeft : Qt.LeftToRight
        rowSpacing: 1
        columnSpacing: 6

        // The capsule draws horizontally; in a vertical bar it stands up, which means
        // swapping the space it asks for.
        Item {
            Layout.alignment: Qt.AlignCenter

            implicitWidth: root.vertical ? pill.implicitHeight : pill.implicitWidth
            implicitHeight: root.vertical ? pill.implicitWidth : pill.implicitHeight

            BatteryPill {
                id: pill

                anchors.centerIn: parent
                rotation: root.vertical ? -90 : 0

                value: BatteryState.level
                pulse: BatteryState.pulse
                colFill: root.colBattery
                capsuleLength: root.settings.capsuleLength ?? 26
                capsuleThickness: root.vertical ? 12 : 13
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignCenter

            spacing: 1
            visible: root.labelMode !== "none"

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter

                // Outside the capsule on purpose: a bolt inside a 13px capsule is
                // unreadable over a fill that is also moving and recolouring.
                text: BatteryState.icon()
                visible: text.length > 0
                fill: 1
                iconSize: Theme.font.s
                color: root.colBattery
            }

            StyledText {
                Layout.alignment: Qt.AlignVCenter

                text: root.labelMode === "time" && BatteryState.estimateUsable ? BatteryState.duration(BatteryState.secondsLeft) : `${BatteryState.percent}%`
                font.pixelSize: root.vertical ? Theme.font.xs : Theme.font.s
                font.weight: BatteryState.critical ? Font.DemiBold : Font.Normal
                color: root.colBattery

                Behavior on color {
                    animation: Theme.anim.fast.colorAnimation.createObject(this)
                }
            }
        }
    }
}
