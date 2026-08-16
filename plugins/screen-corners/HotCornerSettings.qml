// Hot corner settings.
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

ContentSection {
    icon: "screenshot_frame_2"
    shape: MaterialShape.Shape.Gem
    title: Translation.tr("Hot Corners")

    ContentSubsection {
        title: Translation.tr("Top")

        GroupedList {
            ConfigSwitch {
                buttonIcon: "check"
                text: Translation.tr("Enable")
                checked: Config.options.sidebar.cornerOpen.enable
                onCheckedChanged: { Config.options.sidebar.cornerOpen.enable = checked }
            }
            ConfigSwitch {
                buttonIcon: "highlight_mouse_cursor"
                text: Translation.tr("Hover to trigger")
                checked: Config.options.sidebar.cornerOpen.clickless
                onCheckedChanged: { Config.options.sidebar.cornerOpen.clickless = checked }
            }
            ConfigSwitch {
                buttonIcon: "vertical_align_bottom"
                text: Translation.tr("Place at bottom")
                checked: Config.options.sidebar.cornerOpen.bottom
                onCheckedChanged: { Config.options.sidebar.cornerOpen.bottom = checked }
            }
            ConfigSwitch {
                buttonIcon: "unfold_more_double"
                text: Translation.tr("Value scroll")
                checked: Config.options.sidebar.cornerOpen.valueScroll
                onCheckedChanged: { Config.options.sidebar.cornerOpen.valueScroll = checked }
            }
            ConfigSwitch {
                buttonIcon: "visibility"
                text: Translation.tr("Visualize region")
                checked: Config.options.sidebar.cornerOpen.visualize
                onCheckedChanged: { Config.options.sidebar.cornerOpen.visualize = checked }
            }
            ConfigSwitch {
                enabled: Config.options.sidebar.cornerOpen.clickless
                buttonIcon: "ads_click"
                text: Translation.tr("Force hover at absolute corner")
                checked: Config.options.sidebar.cornerOpen.clicklessCornerEnd
                onCheckedChanged: { Config.options.sidebar.cornerOpen.clicklessCornerEnd = checked }
            }
            ConfigSpinBox {
                enabled: Config.options.sidebar.cornerOpen.clickless
                icon: "arrow_cool_down"
                text: Translation.tr("Vertical offset")
                value: Config.options.sidebar.cornerOpen.clicklessCornerVerticalOffset
                from: 0; to: 20; stepSize: 1
                onValueChanged: { Config.options.sidebar.cornerOpen.clicklessCornerVerticalOffset = value }
            }
            ConfigSpinBox {
                icon: "arrow_range"
                text: Translation.tr("Region width")
                value: Config.options.sidebar.cornerOpen.cornerRegionWidth
                from: 1; to: 300; stepSize: 1
                onValueChanged: { Config.options.sidebar.cornerOpen.cornerRegionWidth = value }
            }
            ConfigSpinBox {
                icon: "height"
                text: Translation.tr("Region height")
                value: Config.options.sidebar.cornerOpen.cornerRegionHeight
                from: 1; to: 300; stepSize: 1
                onValueChanged: { Config.options.sidebar.cornerOpen.cornerRegionHeight = value }
            }
        }
    }
    ContentSubsection {
        title: Translation.tr("Bottom")
        GroupedList {
            ConfigComboBox {
                Layout.fillWidth: true
                buttonIcon: "position_bottom_left"
                text: Translation.tr("Bottom-left")
                textRole: "displayName"
                fieldWidth: 50
                model: GlobalStates.hotCornerOptions
                currentValue: Config.options.sidebar.cornerOpen.bottomLeftAction
                onSelected: newValue => { Config.options.sidebar.cornerOpen.bottomLeftAction = newValue }
            }
            ConfigComboBox {
                Layout.fillWidth: true
                buttonIcon: "position_bottom_right"
                text: Translation.tr("Bottom-right")
                textRole: "displayName"
                fieldWidth: 55
                model: GlobalStates.hotCornerOptions
                currentValue: Config.options.sidebar.cornerOpen.bottomRightAction
                onSelected: newValue => { Config.options.sidebar.cornerOpen.bottomRightAction = newValue }
            }
        }
    }
}
