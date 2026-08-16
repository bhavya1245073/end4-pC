// Overview settings.
//
// Injected into Settings -> Interface via `settingsSections` in manifest.json.
// It lives here rather than in the core page so that it disappears when this
// plugin is switched off: controls for a plugin that is not loaded do nothing.
//
// Values still live in the shell's config.json, under `Config.options`, because
// the plugin's own code reads them from there. Only the UI moved.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.core
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ContentSection { // I see that for many the overview is important, I put it first why not
    visible: WM.compositor !== "niri"
    icon: "overview_key"
    shape: MaterialShape.Shape.Gem
    title: Translation.tr("Overview")

    GroupedList {
        ConfigSwitch {
            buttonIcon: "check"
            text: Translation.tr("Enable")
            checked: Config.options.overview.enable
            onCheckedChanged: {
                Config.options.overview.enable = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "center_focus_strong"
            text: Translation.tr("Center icons")
            checked: Config.options.overview.centerIcons
            onCheckedChanged: {
                Config.options.overview.centerIcons = checked;
            }
        }
        ConfigSpinBox {
            icon: "loupe"
            text: Translation.tr("Scale (%)")
            value: Config.options.overview.scale * 100
            from: 1
            to: 100
            stepSize: 1
            onValueChanged: {
                Config.options.overview.scale = value / 100;
            }
        }
        ConfigSelectionArray {
            text: Translation.tr("Style")
            icon: "style"
            currentValue: Config.options.overview.style
            onSelected: newValue => {
                Config.options.overview.style = newValue
            }
            options: [
                {
                    displayName: Translation.tr("Default"),
                    icon: "grid_on",
                    value: "default"
                },
                {
                    displayName: Translation.tr("Niri Like"),
                    icon: "mobiledata_arrows",
                    value: "niri"
                }
            ]
        }
    }

    ContentSubsection {
        title: Translation.tr("Default Settings")
        visible: Config.options.overview.style !== "niri"

        GroupedList {
            visible: Config.options.overview.style !== "niri"
            ConfigRow {
                uniform: true
                visible: Config.options.overview.style !== "niri"
                ConfigSpinBox {
                    icon: "splitscreen_bottom"
                    text: Translation.tr("Rows")
                    value: Config.options.overview.rows
                    from: 1
                    to: 20
                    stepSize: 1
                    onValueChanged: {
                        Config.options.overview.rows = value;
                    }
                }
                ConfigSpinBox {
                    icon: "splitscreen_right"
                    text: Translation.tr("Columns")
                    value: Config.options.overview.columns
                    from: 1
                    to: 20
                    stepSize: 1
                    onValueChanged: {
                        Config.options.overview.columns = value;
                    }
                }
            }

            ConfigRow {
                uniform: true
                visible: Config.options.overview.style !== "niri"
                Layout.alignment: Qt.AlignHCenter
                Layout.leftMargin: 24
                ConfigSelectionArray {
                    Layout.alignment: Qt.AlignHCenter
                    currentValue: Config.options.overview.orderRightLeft
                    onSelected: newValue => {
                        Config.options.overview.orderRightLeft = newValue
                    }
                    options: [
                        {
                            displayName: Translation.tr("Left to right"),
                            icon: "arrow_forward",
                            value: 0
                        },
                        {
                            displayName: Translation.tr("Right to left"),
                            icon: "arrow_back",
                            value: 1
                        }
                    ]
                }
                ConfigSelectionArray {
                    Layout.alignment: Qt.AlignHCenter
                    currentValue: Config.options.overview.orderBottomUp
                    onSelected: newValue => {
                        Config.options.overview.orderBottomUp = newValue
                    }
                    options: [
                        {
                            displayName: Translation.tr("Top-down"),
                            icon: "arrow_downward",
                            value: 0
                        },
                        {
                            displayName: Translation.tr("Bottom-up"),
                            icon: "arrow_upward",
                            value: 1
                        }
                    ]
                }
            }
        }
    }
}
