pragma Singleton

// Installed applications: find them, launch them, pin them.
//
//     PluginApps.all                     // [{ id, name, comment, icon, categories, launch() }]
//     PluginApps.search("code")          // fuzzy, ranked, same matcher the launcher uses
//     PluginApps.launch("firefox")       // by id, name, or executable
//     PluginApps.byId("org.kde.dolphin")
//     PluginApps.pinned / PluginApps.togglePin(id)
//
// Entries are plain objects, so a grid delegate never holds a DesktopEntry that could be
// invalidated by a package being installed while the menu is open.
//
// launch() runs the entry through its own DesktopEntry, which means the exec line is parsed
// properly - field codes stripped, Terminal=true honoured, DBusActivatable respected - rather
// than being handed to a shell. Passing a URL or a file path uses the entry's %u / %f slot.
//
// The fuzzy matcher is the shell's own AppSearch, so a plugin's results rank the same way the
// launcher's do; a plugin that wants its own scoring can still read `all` and sort it.

import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.core

Singleton {
    id: root

    readonly property var all: AppSearch.list.map(entry => root.__shape(entry))

    readonly property int count: root.all.length

    // In the order the user arranged them, skipping any that are no longer installed.
    readonly property var pinned: (Config.options.launcher.pinnedApps ?? [])
        .map(id => root.all.find(entry => entry.id === id || entry.wmClass === id))
        .filter(entry => !!entry)

    function __shape(entry: var): var {
        return {
            id: entry.id,
            name: entry.name ?? "",
            comment: entry.comment ?? "",
            genericName: entry.genericName ?? "",
            icon: entry.icon ?? "",
            categories: entry.categories ?? [],
            keywords: entry.keywords ?? [],
            wmClass: entry.startupClass ?? "",
            terminal: entry.runInTerminal ?? false,
            noDisplay: entry.noDisplay ?? false,
            entry: entry,
            // A desktop file can declare extra actions ("New Private Window"); a launcher that
            // ignores them is missing half of what the application offers.
            actions: (entry.actions ?? []).map(action => ({
                name: action.name ?? "",
                icon: action.icon ?? "",
                execute: () => action.execute()
            })),
            launch: () => entry.execute(),
            launchWith: target => root.__launchWith(entry, target),
            pin: () => LauncherApps.togglePin(entry.id),
            isPinned: () => LauncherApps.isPinned(entry.id)
        };
    }

    // ----------------------------------------------------------------- finding

    function byId(id: string): var {
        return root.all.find(entry => entry.id === id) ?? null;
    }

    // id, then exact name, then window class, then case-insensitive name. In that order
    // because "firefox" is an id on one distribution and a name on another.
    function find(needle: string): var {
        const wanted = `${needle ?? ""}`;
        if (wanted.length === 0)
            return null;
        const lower = wanted.toLowerCase();
        return root.all.find(entry => entry.id === wanted)
            ?? root.all.find(entry => entry.name === wanted)
            ?? root.all.find(entry => entry.wmClass === wanted)
            ?? root.all.find(entry => entry.name.toLowerCase() === lower)
            ?? root.all.find(entry => entry.id.toLowerCase() === lower)
            ?? null;
    }

    // Ranked fuzzy search, best first. Empty query returns everything, alphabetically, which
    // is what a launcher shows before anything is typed.
    function search(query: string, limit: int): var {
        const wanted = `${query ?? ""}`.trim();
        const results = wanted.length === 0
            ? AppSearch.list.slice().sort((a, b) => (a.name ?? "").localeCompare(b.name ?? ""))
            : AppSearch.fuzzyQuery(wanted);
        const shaped = results.map(entry => root.__shape(entry));
        return limit > 0 ? shaped.slice(0, limit) : shaped;
    }

    // Applications in a freedesktop category ("Development", "Graphics", "Game").
    function inCategory(category: string): var {
        return root.all.filter(entry => entry.categories.some(candidate => candidate.toLowerCase() === category.toLowerCase()));
    }

    readonly property var categories: {
        const names = new Set();
        for (const entry of root.all) {
            for (const category of entry.categories)
                names.add(category);
        }
        return Array.from(names).sort();
    }

    // --------------------------------------------------------------- launching

    // Returns false when nothing matched, so a caller can fall back instead of silently
    // doing nothing.
    function launch(needle: string): bool {
        const found = root.find(needle);
        if (!found)
            return false;
        found.launch();
        return true;
    }

    // Opens `target` (a file path or URL) with the given application.
    function launchWith(needle: string, target: string): bool {
        const found = root.find(needle);
        if (!found)
            return false;
        found.launchWith(target);
        return true;
    }

    function __launchWith(entry: var, target: string): void {
        // DesktopEntry.execute() takes no arguments, so a target has to go through the exec
        // line. Field codes are replaced rather than appended: an entry whose exec is
        // `foo --file %f -q` must not become `foo --file -q %f`.
        const parts = (entry.command ?? []).slice();
        if (parts.length === 0) {
            entry.execute();
            return;
        }
        const expanded = [];
        let substituted = false;
        for (const part of parts) {
            if (/^%[fFuU]$/.test(part)) {
                expanded.push(target);
                substituted = true;
            } else if (/%[dDnNickvm]/.test(part)) {
                // Deprecated field codes: dropped, as the specification requires.
                continue;
            } else {
                expanded.push(part);
            }
        }
        if (!substituted)
            expanded.push(target);
        PluginUtils.exec(expanded);
    }

    // Opens a file or URL with whatever the system considers its default handler.
    function open(target: string): void {
        PluginUtils.openUrl(target);
    }

    // ------------------------------------------------------------------ pinning

    function isPinned(id: string): bool {
        return LauncherApps.isPinned(id);
    }

    function togglePin(id: string): void {
        LauncherApps.togglePin(id);
    }

    function icon(name: string): string {
        return AppSearch.guessIcon(name);
    }
}
