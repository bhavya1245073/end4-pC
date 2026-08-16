import QtQuick
import Quickshell
import qs.core

ShellRoot {
    PluginModuleAnchors {}

    Component.onCompleted: {
        const targets = (Quickshell.env("QMLCHECK_TARGETS") ?? "").split(",").filter(t => t.length > 0);
        let failed = 0;
        for (const t of targets) {
            const c = Qt.createComponent(t, Component.PreferSynchronous);
            if (c.status === Component.Error) {
                failed++;
                console.log("QMLCHECK FAIL " + t);
                console.log(c.errorString());
            }
        }
        console.log("QMLCHECK DONE checked=" + targets.length + " failures=" + failed);
    }
}
