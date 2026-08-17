#!/usr/bin/env bash
# One-off: move the plugin-specific booleans out of GlobalStates and onto PanelRegistry.
#
# Kept as a script rather than done by hand so that every one of the ~250 call sites is rewritten
# the same way, and so the mapping is reviewable in one place. Run from the repository root.
#
#   GlobalStates.fooOpen = !GlobalStates.fooOpen   ->  PanelRegistry.toggle("foo")
#   GlobalStates.fooOpen = true                    ->  PanelRegistry.open("foo")
#   GlobalStates.fooOpen = false                   ->  PanelRegistry.close("foo")
#   GlobalStates.fooOpen                           ->  PanelRegistry.state("foo").open
#
# Change *handlers* are not touched: `function onFooOpenChanged()` inside a
# `Connections { target: GlobalStates }` has to become a Connections on the panel's state object,
# which is a structural edit, not a substitution. They are listed at the end.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# property -> panel id
declare -A panels=(
    [overviewOpen]=overview
    [sessionOpen]=sessionScreen
    [oskOpen]=onScreenKeyboard
    [mediaControlsOpen]=mediaControls
    [wallpaperSelectorOpen]=wallpaperSelector
    [dropShelfOpen]=dropover
    [desktopMenuOpen]=desktopMenu
    [regionSelectorOpen]=regionSelector
    [screenTranslatorOpen]=screenTranslator
    [overlayOpen]=overlay
    [settingsOpen]=settings
    [sidebarLeftOpen]=sidebarLeft
    [sidebarRightOpen]=sidebarRight
    [barOpen]=bar
)

files=$(grep -rl "GlobalStates\." --include='*.qml' . | grep -v '^./GlobalStates.qml$' | sort)

for property in "${!panels[@]}"; do
    id="${panels[$property]}"
    for file in $files; do
        grep -q "GlobalStates\.$property" "$file" || continue
        perl -i -pe "
            s/GlobalStates\\.$property\\s*=\\s*!\\s*GlobalStates\\.$property/PanelRegistry.toggle(\"$id\")/g;
            s/GlobalStates\\.$property\\s*=\\s*true/PanelRegistry.open(\"$id\")/g;
            s/GlobalStates\\.$property\\s*=\\s*false/PanelRegistry.close(\"$id\")/g;
            s/GlobalStates\\.$property(?!\\w)/PanelRegistry.state(\"$id\").open/g;
        " "$file"
    done
done

echo "== files touched:"
for file in $files; do
    grep -q "PanelRegistry\." "$file" && echo "   ${file#./}"
done

echo
echo "== remaining GlobalStates references (should be compositor state only):"
grep -rn "GlobalStates\." --include='*.qml' . | grep -v '^./GlobalStates.qml' | sed -E 's/^([^:]+):([0-9]+):.*(GlobalStates\.[A-Za-z]+).*/   \3  \1:\2/' | sort -u | head -40

echo
echo "== change handlers needing a structural edit:"
grep -rn "function on\(Overview\|Session\|Osk\|MediaControls\|WallpaperSelector\|DropShelf\|DesktopMenu\|RegionSelector\|ScreenTranslator\|Overlay\|Settings\|SidebarLeft\|SidebarRight\|Bar\)OpenChanged" --include='*.qml' . | sed 's/^/   /'
