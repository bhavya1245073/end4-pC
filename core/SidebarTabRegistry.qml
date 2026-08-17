pragma Singleton

// Tabs in the left sidebar, the shell's own and plugins' alike.
//
// A plugin declares one in its manifest:
//
//     "sidebarTabs": [
//         {
//             "id": "tasks",
//             "label": "Tasks",
//             "icon": "checklist",
//             "entry": "TasksTab.qml",
//             "order": 45
//         }
//     ]
//
// and gets a full-height page in the sidebar, in the tab strip, reorderable by `order`, with the
// same navigation, animation and keyboard handling as the shell's own tabs.
//
// The shell's four tabs - Intelligence, Translator, Media, Anime - are rows in this same list,
// addressed by URL exactly like a plugin's. They were a literal array in SidebarLeftContent with a
// matching array of Components next to it, which meant the sidebar was the only place a tab could
// exist and the two arrays had to be kept in the same order by hand.
//
// `requires` gates a row on a config option, which is how the shell's tabs are switched off without
// the sidebar knowing what any of them are: "policies.ai" is read from Config and a falsy value
// (0, false, "") removes the tab.

import QtQuick
import Quickshell
import qs.modules.common
import qs.services

Singleton {
    id: root

    readonly property string __sidebarDir: `file://${Quickshell.shellDir}/modules/ii/sidebarLeft`

    readonly property var builtins: [
        {
            id: "intelligence",
            label: Translation.tr("Intelligence"),
            icon: "neurology",
            order: 10,
            url: `${root.__sidebarDir}/AiChat.qml`,
            requires: "policies.ai"
        },
        {
            id: "translator",
            label: Translation.tr("Translator"),
            icon: "translate",
            order: 20,
            url: `${root.__sidebarDir}/Translator.qml`,
            requires: "sidebar.translator.enable"
        },
        {
            id: "media",
            label: Translation.tr("Media"),
            icon: "music_note",
            order: 30,
            url: `${root.__sidebarDir}/SidebarPlayerControl.qml`,
            requires: "sidebar.media.enable"
        },
        {
            id: "anime",
            label: Translation.tr("Anime"),
            icon: "bookmark_heart",
            order: 40,
            url: `${root.__sidebarDir}/Anime.qml`,
            // Two states matter here: off (0) removes the tab, and "closet" (2) also removes it -
            // that is the whole point of the setting - so a plain truthiness check is not enough.
            requires: "policies.weeb",
            requiresValue: 1
        }
    ]

    readonly property var all: Stable.list("SidebarTabRegistry.all", (() => {
        const rows = [];

        for (const tab of root.builtins) {
            if (!root.__satisfied(tab))
                continue;
            rows.push(Object.assign({ pluginId: "" }, tab));
        }

        for (const tab of PluginRegistry.sidebarTabs) {
            if (!tab.id || !tab.url)
                continue;
            if (tab.requires && !root.__satisfied(tab))
                continue;
            rows.push({
                id: `${tab.pluginId}:${tab.id}`,
                label: tab.label ?? tab.id,
                icon: tab.icon ?? "extension",
                order: tab.order ?? 50,
                url: tab.url,
                pluginId: tab.pluginId
            });
        }

        return rows.sort((a, b) => (a.order ?? 50) - (b.order ?? 50));
    })())

    // What the tab strip needs: an icon and a name per tab.
    readonly property var buttons: root.all.map(tab => ({ icon: tab.icon, name: tab.label }))

    readonly property var ids: Stable.ids("SidebarTabRegistry.ids", root.all.map(tab => tab.id))

    function indexOf(id: string): int {
        return root.all.findIndex(tab => tab.id === id);
    }

    // Dotted path into Config.options, so a row can be gated on any setting without this file
    // knowing which settings exist.
    function __satisfied(tab: var): bool {
        const path = `${tab.requires ?? ""}`;
        if (path.length === 0)
            return true;
        let value = Config.options;
        for (const part of path.split(".")) {
            if (value === undefined || value === null)
                return false;
            value = value[part];
        }
        if (tab.requiresValue !== undefined)
            return value === tab.requiresValue;
        return !!value;
    }
}
